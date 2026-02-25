import SwiftUI

/// Enhanced dashboard with Claude-powered AI analysis
@available(macOS 14.0, *)
struct DashboardView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.openSettings) var openSettings

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerSection
                .padding()

            Divider()

            // AI Analysis View - replaces old tab-based reporting
            AIAnalysisView()
                .environmentObject(appState)
        }
        .frame(minWidth: 1000, minHeight: 700)
    }

    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Productivity Dashboard")
                    .font(.title)
                    .fontWeight(.bold)

                Text("AI-powered insights and analysis")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button(action: {
                openSettings()
            }) {
                Image(systemName: "gear")
                    .font(.title2)
            }
            .buttonStyle(.plain)
        }
    }
}

@available(macOS 14.0, *)
#Preview {
    DashboardView()
        .environmentObject(AppState.shared)
}
