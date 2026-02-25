import SwiftUI
import Combine

@available(macOS 14.0, *)
@main
struct ProductivityTrackerApp: App {
    @StateObject private var appState = AppState.shared

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(appState)
        } label: {
            Image(systemName: appState.isCapturing ? "record.circle.fill" : "clock.fill")
                .symbolRenderingMode(.hierarchical)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(appState)
        }

        WindowGroup("Dashboard", id: "dashboard") {
            DashboardView()
                .environmentObject(appState)
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}

/// Global application state
@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    // Services
    let storageManager = StorageManager.shared
    let captureService = CaptureService.shared
    let windowMonitor = WindowFocusMonitor.shared
    let aiCategorizer = AICategorizer.shared

    // UI State
    @Published var isCapturing = false
    @Published var isInitialized = false
    @Published var pendingSuggestionsCount = 0
    @Published var currentSession: ActivitySession?
    @Published var lastError: String?

    private init() {
        Task {
            await initialize()
        }
    }

    private func initialize() async {
        do {
            // Initialize database
            try await storageManager.initialize()

            // Run migrations
            try await MigrationManager.shared.runMigrations()

            // Load pending suggestions count
            pendingSuggestionsCount = try await storageManager.pendingSuggestionsCount()

            isInitialized = true
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - Actions

    func startCapturing() async {
        do {
            try await captureService.startCapturing()
            windowMonitor.startMonitoring()
            isCapturing = true
            currentSession = captureService.currentSession
        } catch {
            lastError = error.localizedDescription
        }
    }

    func stopCapturing() async {
        do {
            try await captureService.stopCapturing()
            windowMonitor.stopMonitoring()
            isCapturing = false
            currentSession = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func refreshPendingSuggestionsCount() async {
        pendingSuggestionsCount = (try? await storageManager.pendingSuggestionsCount()) ?? 0
    }
}
