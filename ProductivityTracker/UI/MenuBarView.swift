import SwiftUI

/// Menu bar popup view showing current status and quick actions
@available(macOS 14.0, *)
struct MenuBarView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.openWindow) var openWindow
    @Environment(\.openSettings) var openSettings

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerSection

            Divider()

            // Status section
            statusSection

            Divider()

            // Quick actions
            actionsSection

            Divider()

            // Footer
            footerSection
        }
        .frame(width: 280)
        .padding(.vertical, 8)
    }

    // MARK: - Sections

    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Productivity Tracker")
                    .font(.headline)

                Text(appState.isCapturing ? "Tracking active" : "Not tracking")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if appState.pendingSuggestionsCount > 0 {
                Badge(count: appState.pendingSuggestionsCount)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let session = appState.currentSession {
                HStack {
                    Image(systemName: "app.fill")
                        .foregroundColor(.blue)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(session.appName ?? "Unknown App")
                            .font(.subheadline)
                            .fontWeight(.medium)

                        if let windowTitle = session.windowTitle {
                            Text(windowTitle)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }

                    Spacer()

                    Text(session.formattedDuration)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                }
            } else {
                Text("No active session")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            // Concurrent contexts
            if !appState.windowMonitor.activeContexts.isEmpty {
                ConcurrentContextsCompact(contexts: appState.windowMonitor.sortedContexts.prefix(3).map { $0 })
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var actionsSection: some View {
        VStack(spacing: 4) {
            Button(action: {
                Task {
                    if appState.isCapturing {
                        await appState.stopCapturing()
                    } else {
                        await appState.startCapturing()
                    }
                }
            }) {
                Label(
                    appState.isCapturing ? "Stop Tracking" : "Start Tracking",
                    systemImage: appState.isCapturing ? "stop.fill" : "play.fill"
                )
            }
            .buttonStyle(MenuButtonStyle(isDestructive: appState.isCapturing))

            Button(action: {
                openWindow(id: "dashboard")
            }) {
                Label("Open Dashboard", systemImage: "chart.bar.fill")
            }
            .buttonStyle(MenuButtonStyle())

            if appState.pendingSuggestionsCount > 0 {
                Button(action: {
                    openSettings()
                }) {
                    Label("Review \(appState.pendingSuggestionsCount) Suggestions", systemImage: "sparkles")
                }
                .buttonStyle(MenuButtonStyle())
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var footerSection: some View {
        HStack {
            Button(action: {
                openSettings()
            }) {
                Image(systemName: "gear")
            }
            .buttonStyle(.plain)

            Spacer()

            Button(action: {
                NSApplication.shared.terminate(nil)
            }) {
                Text("Quit")
                    .font(.caption)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

// MARK: - Supporting Views

struct Badge: View {
    let count: Int

    var body: some View {
        Text("\(count)")
            .font(.caption2)
            .fontWeight(.semibold)
            .foregroundColor(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.orange)
            .clipShape(Capsule())
    }
}

struct ConcurrentContextsCompact: View {
    let contexts: [ActiveContext]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Active Contexts")
                .font(.caption2)
                .foregroundColor(.secondary)
                .textCase(.uppercase)

            ForEach(contexts) { context in
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color(hex: context.statusColor))
                        .frame(width: 6, height: 6)

                    Text(context.projectName)
                        .font(.caption)
                        .lineLimit(1)

                    Spacer()

                    Text(context.formattedFocusPercentage)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                }
            }
        }
        .padding(.top, 4)
    }
}

struct MenuButtonStyle: ButtonStyle {
    var isDestructive: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(configuration.isPressed ? Color.gray.opacity(0.2) : Color.clear)
            )
            .foregroundColor(isDestructive ? .red : .primary)
    }
}

@available(macOS 14.0, *)
#Preview {
    MenuBarView()
        .environmentObject(AppState.shared)
}
