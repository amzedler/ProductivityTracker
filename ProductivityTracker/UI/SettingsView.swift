import SwiftUI

/// Main settings view with navigation to all settings sections
@available(macOS 14.0, *)
struct SettingsView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            ProjectsSettingsView()
                .tabItem {
                    Label("Projects", systemImage: "folder.fill")
                }
                .badge(appState.pendingSuggestionsCount > 0 ? Text("\(appState.pendingSuggestionsCount)") : nil)

            WorkCategoriesView()
                .tabItem {
                    Label("Categories", systemImage: "tag.fill")
                }

            ProjectRolesView()
                .tabItem {
                    Label("Roles", systemImage: "person.crop.rectangle.fill")
                }

            AISuggestionsView()
                .tabItem {
                    Label("AI Suggestions", systemImage: "sparkles")
                }
                .badge(appState.pendingSuggestionsCount)

            APISettingsView()
                .tabItem {
                    Label("API", systemImage: "key.fill")
                }
        }
        .frame(minWidth: 600, minHeight: 450)
        .environmentObject(appState)
    }
}

// MARK: - General Settings

@available(macOS 14.0, *)
struct GeneralSettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var captureInterval: Double = 60
    @State private var enableAICategorization = true
    @State private var launchAtLogin = false
    @State private var hasScreenPermission = false

    var body: some View {
        Form {
            Section("Capture Settings") {
                Slider(value: $captureInterval, in: 15...300, step: 15) {
                    Text("Capture Interval")
                } minimumValueLabel: {
                    Text("15s")
                } maximumValueLabel: {
                    Text("5m")
                }

                Text("Screenshots captured every \(Int(captureInterval)) seconds")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Toggle("Enable AI Categorization", isOn: $enableAICategorization)
            }

            Section("Permissions") {
                PermissionRow(
                    title: "Screen Recording",
                    description: "Required for capturing screenshots",
                    isGranted: hasScreenPermission,
                    action: {
                        appState.captureService.requestScreenCapturePermission()
                    }
                )

                PermissionRow(
                    title: "Accessibility",
                    description: "Required for tracking window focus",
                    isGranted: appState.windowMonitor.hasAccessibilityPermission,
                    action: {
                        appState.windowMonitor.requestAccessibilityPermission()
                    }
                )
            }

            Section("Startup") {
                Toggle("Launch at Login", isOn: $launchAtLogin)
            }
        }
        .formStyle(.grouped)
        .padding()
        .task {
            hasScreenPermission = await appState.captureService.hasScreenCapturePermission()
            _ = appState.windowMonitor.checkAccessibilityPermission()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            // Refresh permissions when app becomes active (user might have just granted permission)
            Task {
                hasScreenPermission = await appState.captureService.hasScreenCapturePermission()
                _ = appState.windowMonitor.checkAccessibilityPermission()
            }
        }
    }
}

@available(macOS 14.0, *)
struct PermissionRow: View {
    let title: String
    let description: String
    let isGranted: Bool
    let action: () -> Void

    @State private var justClicked = false
    @State private var showAlert = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    Text(description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if isGranted {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                } else {
                    Button(action: {
                        action()
                        justClicked = true
                        showAlert = true
                        // Reset after 10 seconds
                        DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
                            justClicked = false
                        }
                    }) {
                        Text("Request Permission")
                    }
                    .buttonStyle(.bordered)
                }
            }

            if justClicked && !isGranted {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle.fill")
                            .foregroundColor(.blue)
                        Text("Follow these steps:")
                            .font(.caption)
                            .fontWeight(.semibold)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("1. A system dialog should appear - click 'Open System Settings'")
                        Text("2. In System Settings, find and enable 'ProductivityTracker'")
                        Text("3. If no dialog appeared, manually open: System Settings > Privacy & Security > Accessibility")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.leading, 22)
                }
                .padding(.leading, 2)
            }
        }
        .alert("Accessibility Permission Required", isPresented: $showAlert) {
            Button("Open System Settings") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                    NSWorkspace.shared.open(url)
                }
            }
            Button("OK", role: .cancel) {}
        } message: {
            Text("ProductivityTracker needs Accessibility permission to track which apps and windows you're using.\n\nIn System Settings, find 'ProductivityTracker' in the list and toggle it on.")
        }
    }
}

// MARK: - API Settings

@available(macOS 14.0, *)
struct APISettingsView: View {
    @State private var apiKey = ""
    @State private var showKey = false
    @State private var isTesting = false
    @State private var testResult: String?

    private let claudeClient = ClaudeAPIClient.shared

    var body: some View {
        Form {
            Section("Anthropic API") {
                HStack {
                    if showKey {
                        TextField("API Key", text: $apiKey)
                            .textFieldStyle(.roundedBorder)
                    } else {
                        SecureField("API Key", text: $apiKey)
                            .textFieldStyle(.roundedBorder)
                    }

                    Button(action: { showKey.toggle() }) {
                        Image(systemName: showKey ? "eye.slash.fill" : "eye.fill")
                    }
                    .buttonStyle(.plain)
                }

                HStack {
                    Button("Save Key") {
                        claudeClient.setAPIKey(apiKey)
                    }
                    .disabled(apiKey.isEmpty)

                    Button("Test Connection") {
                        testConnection()
                    }
                    .disabled(!claudeClient.hasAPIKey || isTesting)

                    if isTesting {
                        ProgressView()
                            .scaleEffect(0.7)
                    }
                }

                if let result = testResult {
                    Text(result)
                        .font(.caption)
                        .foregroundColor(result.contains("Success") ? .green : .red)
                }
            }

            Section("Model") {
                Text("Using Claude claude-sonnet-4-20250514 for screenshot analysis")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            if claudeClient.hasAPIKey {
                apiKey = "••••••••••••••••"
            }
        }
    }

    private func testConnection() {
        isTesting = true
        testResult = nil

        Task {
            do {
                // Try a simple API call
                let _ = try await claudeClient.generateScreenshotSummary(
                    screenshot: NSImage(size: NSSize(width: 100, height: 100))
                )
                testResult = "Success! API connection working."
            } catch {
                testResult = "Error: \(error.localizedDescription)"
            }
            isTesting = false
        }
    }
}

@available(macOS 14.0, *)
#Preview {
    SettingsView()
        .environmentObject(AppState.shared)
}
