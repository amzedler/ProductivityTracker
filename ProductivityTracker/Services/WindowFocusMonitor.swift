import Foundation
import AppKit
import Accessibility
import Combine

/// WindowFocusMonitor tracks application and window focus changes.
/// Enhanced with concurrent context tracking for parallel work streams.
@MainActor
final class WindowFocusMonitor: ObservableObject {
    static let shared = WindowFocusMonitor()

    private let storageManager = StorageManager.shared

    // Current focus state
    @Published var currentAppName: String?
    @Published var currentWindowTitle: String?
    @Published var currentBundleIdentifier: String?

    // Concurrent context tracking
    @Published var activeContexts: [ActiveContext] = []

    // Focus history
    @Published var focusHistory: [FocusEvent] = []

    // Monitoring state
    @Published var isMonitoring = false

    // Accessibility permission state
    @Published var hasAccessibilityPermission: Bool = false

    /// Time after which a context is considered stale (30 minutes)
    private let contextStaleThreshold: TimeInterval = 30 * 60

    /// Time interval for focus polling (1 second)
    private let pollInterval: TimeInterval = 1.0

    private var focusTimer: Timer?
    private var lastFocusEvent: FocusEvent?
    private var lastFocusTime: Date = Date()

    private init() {
        // Check accessibility permission on init
        _ = checkAccessibilityPermission()

        // Trigger accessibility API usage to make app appear in System Settings
        triggerAccessibilityRegistration()
    }

    /// Trigger a minimal accessibility API call to register the app in System Settings
    private func triggerAccessibilityRegistration() {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return }
        let pid = frontApp.processIdentifier
        let appRef = AXUIElementCreateApplication(pid)

        // Attempt to get the app's title (this will cause macOS to register the app)
        var titleValue: CFTypeRef?
        _ = AXUIElementCopyAttributeValue(appRef, kAXTitleAttribute as CFString, &titleValue)
    }

    // MARK: - Monitoring Control

    /// Start monitoring window focus changes
    func startMonitoring() {
        guard !isMonitoring else { return }

        isMonitoring = true

        // Initial capture
        updateCurrentFocus()

        // Start polling timer
        focusTimer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateCurrentFocus()
            }
        }

        // Register for app activation notifications
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(activeAppChanged),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
    }

    /// Stop monitoring
    func stopMonitoring() {
        guard isMonitoring else { return }

        isMonitoring = false
        focusTimer?.invalidate()
        focusTimer = nil

        NSWorkspace.shared.notificationCenter.removeObserver(self)

        // Finalize last focus event
        finalizeLastFocusEvent()
    }

    // MARK: - Focus Updates

    @objc private func activeAppChanged(_ notification: Notification) {
        updateCurrentFocus()
    }

    private func updateCurrentFocus() {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return }

        let appName = frontApp.localizedName ?? "Unknown"
        let bundleId = frontApp.bundleIdentifier
        let windowTitle = getActiveWindowTitle(for: frontApp)

        // Check if focus has changed
        let focusChanged = appName != currentAppName || windowTitle != currentWindowTitle

        if focusChanged {
            // Finalize the previous focus event
            finalizeLastFocusEvent()

            // Update current state
            currentAppName = appName
            currentWindowTitle = windowTitle
            currentBundleIdentifier = bundleId

            // Create new focus event
            createFocusEvent(appName: appName, bundleId: bundleId, windowTitle: windowTitle)

            // Update concurrent contexts
            updateConcurrentContexts(appName: appName, windowTitle: windowTitle)
        }

        // Update focus duration for active context
        updateActiveFocusDuration()
    }

    private func getActiveWindowTitle(for app: NSRunningApplication) -> String? {
        // Use Accessibility API to get window title
        guard let pid = app.processIdentifier as pid_t? else { return nil }

        let appRef = AXUIElementCreateApplication(pid)
        var windowValue: CFTypeRef?

        let result = AXUIElementCopyAttributeValue(appRef, kAXFocusedWindowAttribute as CFString, &windowValue)

        guard result == .success, let windowRef = windowValue else { return nil }

        var titleValue: CFTypeRef?
        let titleResult = AXUIElementCopyAttributeValue(windowRef as! AXUIElement, kAXTitleAttribute as CFString, &titleValue)

        guard titleResult == .success, let title = titleValue as? String else { return nil }

        return title
    }

    // MARK: - Focus Events

    private func createFocusEvent(appName: String, bundleId: String?, windowTitle: String?) {
        let concurrentIds = activeContexts.compactMap { $0.projectId }

        var event = FocusEvent(
            timestamp: Date(),
            appName: appName,
            bundleIdentifier: bundleId,
            windowTitle: windowTitle,
            concurrentContextIds: concurrentIds
        )

        lastFocusEvent = event
        lastFocusTime = Date()

        // Add to history (keep last 100)
        focusHistory.insert(event, at: 0)
        if focusHistory.count > 100 {
            focusHistory = Array(focusHistory.prefix(100))
        }

        // Save to database asynchronously
        Task {
            try? await storageManager.saveFocusEvent(&event)
        }
    }

    private func finalizeLastFocusEvent() {
        guard let lastEvent = lastFocusEvent, let eventId = lastEvent.id else { return }

        let duration = Date().timeIntervalSince(lastFocusTime)

        Task {
            try? await storageManager.updateFocusEventDuration(eventId, duration: duration)
        }
    }

    // MARK: - Concurrent Context Tracking

    /// Update concurrent contexts based on current focus
    private func updateConcurrentContexts(appName: String, windowTitle: String?) {
        let now = Date()

        // Find or create context for current focus
        if let existingIndex = activeContexts.firstIndex(where: {
            $0.appName == appName && $0.windowTitle == windowTitle
        }) {
            // Update existing context
            var context = activeContexts[existingIndex]
            context.updateFocus(isFocused: true, duration: pollInterval)
            activeContexts[existingIndex] = context
        } else {
            // Create new context
            let context = ActiveContext(
                projectName: extractProjectName(from: windowTitle) ?? appName,
                appName: appName,
                windowTitle: windowTitle,
                isFocused: true
            )
            activeContexts.append(context)
        }

        // Update focus state for all contexts
        for i in activeContexts.indices {
            let isCurrentlyFocused = activeContexts[i].appName == appName &&
                                     activeContexts[i].windowTitle == windowTitle
            activeContexts[i].isFocused = isCurrentlyFocused
        }

        // Age out stale contexts
        ageOutStaleContexts()

        // Recalculate focus percentages
        recalculateFocusPercentages()
    }

    /// Update focus duration for the active context
    private func updateActiveFocusDuration() {
        for i in activeContexts.indices where activeContexts[i].isFocused {
            activeContexts[i].focusedDuration += pollInterval
            activeContexts[i].lastSeenAt = Date()
        }
    }

    /// Remove contexts not seen in 30+ minutes
    private func ageOutStaleContexts() {
        activeContexts.removeAll { $0.isStale }
    }

    /// Recalculate focus percentages for all active contexts
    private func recalculateFocusPercentages() {
        for i in activeContexts.indices {
            activeContexts[i].updateFocusPercentage()
        }
    }

    // MARK: - Project Detection

    /// Extract project name from window title
    private func extractProjectName(from windowTitle: String?) -> String? {
        guard let title = windowTitle else { return nil }

        // Common patterns for project detection
        let patterns = [
            // Linear ticket: DISP-123, SCAM-456
            "([A-Z]+-\\d+)",
            // GitHub: username/repo
            "([\\w-]+/[\\w-]+)",
            // Figma file names
            "^(.+?)\\s*[-–—]\\s*Figma",
            // Generic: Project Name - App
            "^(.+?)\\s*[-–—]"
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []),
               let match = regex.firstMatch(in: title, options: [], range: NSRange(title.startIndex..., in: title)),
               let range = Range(match.range(at: 1), in: title) {
                return String(title[range])
            }
        }

        return nil
    }

    // MARK: - Context Queries

    /// Get the most active context
    var primaryContext: ActiveContext? {
        activeContexts.max(by: { $0.focusPercentage < $1.focusPercentage })
    }

    /// Get contexts sorted by focus percentage
    var sortedContexts: [ActiveContext] {
        activeContexts.sorted { $0.focusPercentage > $1.focusPercentage }
    }

    /// Total focused time across all contexts
    var totalFocusedTime: TimeInterval {
        activeContexts.reduce(0) { $0 + $1.focusedDuration }
    }

    // MARK: - Project Linking

    /// Link a context to a project
    func linkContextToProject(_ contextId: UUID, projectId: Int64) {
        if let index = activeContexts.firstIndex(where: { $0.id == contextId }) {
            activeContexts[index].projectId = projectId
        }
    }

    /// Get active project IDs
    var activeProjectIds: [Int64] {
        activeContexts.compactMap { $0.projectId }
    }

    // MARK: - Statistics

    struct FocusStats {
        let totalFocusTime: TimeInterval
        let contextCount: Int
        let switchCount: Int
        let mostActiveApp: String?
        let focusPercentages: [String: Double]
    }

    func getStats(since startDate: Date) async -> FocusStats {
        let events = focusHistory.filter { $0.timestamp >= startDate }

        var appDurations: [String: TimeInterval] = [:]
        for event in events {
            let duration = event.duration ?? 0
            appDurations[event.appName, default: 0] += duration
        }

        let totalTime = appDurations.values.reduce(0, +)
        let percentages = appDurations.mapValues { ($0 / totalTime) * 100 }

        return FocusStats(
            totalFocusTime: totalTime,
            contextCount: activeContexts.count,
            switchCount: events.count,
            mostActiveApp: appDurations.max(by: { $0.value < $1.value })?.key,
            focusPercentages: percentages
        )
    }
}

// MARK: - Accessibility Permissions

extension WindowFocusMonitor {
    func checkAccessibilityPermission() -> Bool {
        let hasPermission = AXIsProcessTrusted()
        Task { @MainActor in
            self.hasAccessibilityPermission = hasPermission
        }
        return hasPermission
    }

    func requestAccessibilityPermission() {
        // Try to actually use an accessibility API - this will trigger the system
        // to register the app and show the permission dialog
        if let frontApp = NSWorkspace.shared.frontmostApplication {
            let pid = frontApp.processIdentifier
            let appRef = AXUIElementCreateApplication(pid)

            // Try to get focused window - this requires accessibility permission
            var windowValue: CFTypeRef?
            let result = AXUIElementCopyAttributeValue(appRef, kAXFocusedWindowAttribute as CFString, &windowValue)

            if result != .success {
                // Permission not granted yet - show the prompt
                let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
                _ = AXIsProcessTrustedWithOptions(options)

                // Also open System Settings as backup
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }

        // Check permission status after a delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            _ = self?.checkAccessibilityPermission()
        }
    }
}
