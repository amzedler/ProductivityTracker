import Foundation
import AppKit
import ScreenCaptureKit
import Combine

/// CaptureService handles periodic screenshot capture and AI analysis.
/// Integrates with AICategorizer for immediate categorization at capture time.
@MainActor
final class CaptureService: ObservableObject {
    static let shared = CaptureService()

    private let storageManager = StorageManager.shared
    private let aiCategorizer = AICategorizer.shared
    private let windowMonitor = WindowFocusMonitor.shared

    /// Capture interval in seconds
    var captureInterval: TimeInterval = 60

    /// Whether capture is currently active
    @Published var isCapturing = false

    /// Current active session
    @Published var currentSession: ActivitySession?

    /// Last captured screenshot (for preview)
    @Published var lastScreenshot: NSImage?

    /// Last error from capture or processing
    @Published var lastError: Error?

    /// Statistics
    @Published var captureCount: Int = 0

    private var captureTimer: Timer?
    private var sessionStartTime: Date?

    private init() {}

    // MARK: - Capture Control

    /// Start periodic screenshot capture
    func startCapturing() async throws {
        guard !isCapturing else { return }

        // Check for screen capture permission
        guard await hasScreenCapturePermission() else {
            throw CaptureError.permissionDenied
        }

        isCapturing = true
        sessionStartTime = Date()

        // Create a new session
        var session = ActivitySession(
            startTime: Date(),
            appName: windowMonitor.currentAppName,
            windowTitle: windowMonitor.currentWindowTitle,
            bundleIdentifier: windowMonitor.currentBundleIdentifier
        )
        try await storageManager.saveSession(&session)
        currentSession = session

        // Start the capture timer
        captureTimer = Timer.scheduledTimer(withTimeInterval: captureInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.captureAndProcess()
            }
        }

        // Perform initial capture
        await captureAndProcess()
    }

    /// Stop capturing and finalize the session
    func stopCapturing() async throws {
        guard isCapturing else { return }

        captureTimer?.invalidate()
        captureTimer = nil
        isCapturing = false

        // End the current session
        if var session = currentSession {
            session.end()
            try await storageManager.saveSession(&session)

            // Update project duration
            if let projectId = session.projectId {
                try await storageManager.updateProjectDuration(projectId, additionalDuration: session.duration)
            }
        }

        currentSession = nil
        sessionStartTime = nil
    }

    /// Pause capturing without ending the session
    func pauseCapturing() {
        captureTimer?.invalidate()
        captureTimer = nil
    }

    /// Resume capturing
    func resumeCapturing() {
        guard isCapturing else { return }

        captureTimer = Timer.scheduledTimer(withTimeInterval: captureInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.captureAndProcess()
            }
        }
    }

    // MARK: - Screenshot Capture

    private func captureAndProcess() async {
        do {
            // Capture screenshot
            let screenshot = try await captureScreenshot()
            lastScreenshot = screenshot
            captureCount += 1

            // Update session with current window info
            guard var session = currentSession else { return }
            session.appName = windowMonitor.currentAppName
            session.windowTitle = windowMonitor.currentWindowTitle
            session.bundleIdentifier = windowMonitor.currentBundleIdentifier
            session.incrementScreenshotCount()
            session.updateDuration()

            // Get concurrent context IDs from window monitor
            let concurrentIds = windowMonitor.activeContexts.compactMap { $0.projectId }
            session.setConcurrentContextIds(concurrentIds)

            // Run AI categorization
            try await aiCategorizer.categorize(screenshot: screenshot, session: &session)

            currentSession = session
            lastError = nil

        } catch {
            lastError = error
            print("Capture error: \(error.localizedDescription)")
        }
    }

    private func captureScreenshot() async throws -> NSImage {
        // Get the main display
        guard let mainDisplay = CGMainDisplayID() as CGDirectDisplayID? else {
            throw CaptureError.noDisplay
        }

        // Use ScreenCaptureKit for modern capture
        if #available(macOS 14.0, *) {
            return try await captureWithScreenCaptureKit()
        } else {
            throw CaptureError.notSupported
        }
    }

    @available(macOS 14.0, *)
    private func captureWithScreenCaptureKit() async throws -> NSImage {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)

        guard let display = content.displays.first else {
            throw CaptureError.noDisplay
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.width = Int(display.width)
        config.height = Int(display.height)
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.scalesToFit = true

        let image = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: config
        )
        return NSImage(cgImage: image, size: NSSize(width: display.width, height: display.height))
    }


    // MARK: - Permissions

    func hasScreenCapturePermission() async -> Bool {
        if #available(macOS 12.3, *) {
            do {
                // Try to get shareable content - this will fail if no permission
                _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                return true
            } catch {
                return false
            }
        } else {
            // Check using CGDisplayStream
            let stream = CGDisplayStream(
                display: CGMainDisplayID(),
                outputWidth: 1,
                outputHeight: 1,
                pixelFormat: Int32(kCVPixelFormatType_32BGRA),
                properties: nil,
                handler: { _, _, _, _ in }
            )
            return stream != nil
        }
    }

    func requestScreenCapturePermission() {
        // Open System Preferences to the Screen Recording pane
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Manual Capture

    /// Capture a single screenshot on demand
    func captureOnDemand() async throws -> NSImage {
        let screenshot = try await captureScreenshot()
        lastScreenshot = screenshot
        captureCount += 1
        return screenshot
    }

    /// Capture and categorize without a session
    func captureAndCategorize() async throws -> AICategorization {
        let screenshot = try await captureScreenshot()
        lastScreenshot = screenshot

        // Create a temporary session for categorization
        var tempSession = ActivitySession(
            startTime: Date(),
            appName: windowMonitor.currentAppName,
            windowTitle: windowMonitor.currentWindowTitle,
            bundleIdentifier: windowMonitor.currentBundleIdentifier
        )

        try await aiCategorizer.categorize(screenshot: screenshot, session: &tempSession)

        guard let categorization = aiCategorizer.lastCategorization else {
            throw CaptureError.categorizationFailed
        }

        return categorization
    }
}

// MARK: - Errors

enum CaptureError: LocalizedError {
    case permissionDenied
    case noDisplay
    case captureFailed
    case categorizationFailed
    case notSupported

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Screen capture permission denied. Please grant access in System Preferences."
        case .noDisplay:
            return "No display found for capture."
        case .captureFailed:
            return "Failed to capture screenshot."
        case .categorizationFailed:
            return "Failed to categorize the screenshot."
        case .notSupported:
            return "Screen capture is not supported on this OS version. macOS 14.0 or later required."
        }
    }
}

// MARK: - Capture Settings

extension CaptureService {
    struct Settings: Codable {
        var captureInterval: TimeInterval = 60
        var enableAICategorization: Bool = true
        var captureOnlyActiveWindow: Bool = false
        var excludedApps: [String] = []
    }

    func loadSettings() -> Settings {
        guard let data = UserDefaults.standard.data(forKey: "captureSettings"),
              let settings = try? JSONDecoder().decode(Settings.self, from: data) else {
            return Settings()
        }
        return settings
    }

    func saveSettings(_ settings: Settings) {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: "captureSettings")
            captureInterval = settings.captureInterval
        }
    }
}
