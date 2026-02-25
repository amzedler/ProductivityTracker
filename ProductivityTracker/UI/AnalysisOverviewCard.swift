import SwiftUI

/// Card displaying the high-level overview of the analysis
@available(macOS 14.0, *)
struct AnalysisOverviewCard: View {
    let analysis: ComprehensiveAnalysis

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Image(systemName: "chart.bar.doc.horizontal")
                    .font(.title2)
                    .foregroundColor(.blue)

                Text("Overview")
                    .font(.headline)

                Spacer()

                // Metadata
                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(analysis.formattedTotalTime)")
                        .font(.title3)
                        .fontWeight(.bold)

                    Text("\(analysis.sessionCount) sessions")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Divider()

            // Overview text
            Text(analysis.overview)
                .font(.body)
                .foregroundColor(.primary)
                .lineSpacing(4)

            // Quick stats
            HStack(spacing: 24) {
                StatItem(
                    icon: "square.grid.3x3.square",
                    label: "Segments",
                    value: "\(analysis.workSegments.count)"
                )

                StatItem(
                    icon: "lightbulb.fill",
                    label: "Insights",
                    value: "\(analysis.keyInsights.count)"
                )

                StatItem(
                    icon: "sparkles",
                    label: "Recommendations",
                    value: "\(analysis.recommendations.count)"
                )

                Spacer()

                // Analysis timestamp
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Generated")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(analysis.analysisTimestamp, style: .relative)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(
            LinearGradient(
                colors: [Color.blue.opacity(0.1), Color.purple.opacity(0.1)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.blue.opacity(0.3), lineWidth: 1)
        )
    }
}

struct StatItem: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(.blue)

            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.title3)
                    .fontWeight(.bold)
                Text(label)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}
