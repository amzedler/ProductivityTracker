import SwiftUI

/// Card displaying a single work segment with expandable details
@available(macOS 14.0, *)
struct WorkSegmentCard: View {
    let segment: WorkSegment
    let sessions: [ActivitySession]
    @State private var isExpanded = false

    private var segmentSessions: [ActivitySession] {
        sessions.filter { session in
            if let id = session.id {
                return segment.sessionIds.contains(id)
            }
            return false
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Main card content
            Button(action: { withAnimation { isExpanded.toggle() } }) {
                HStack(spacing: 12) {
                    // Focus quality indicator
                    Circle()
                        .fill(focusQualityColor)
                        .frame(width: 12, height: 12)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(segment.name)
                            .font(.headline)
                            .foregroundColor(.primary)

                        Text(segment.description)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .lineLimit(isExpanded ? nil : 2)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 4) {
                        Text(segment.formattedDuration)
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)

                        if let quality = segment.focusQuality {
                            HStack(spacing: 4) {
                                Text(segment.focusQualityEmoji)
                                Text(quality.capitalized)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundColor(.secondary)
                }
                .padding()
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Expanded details
            if isExpanded {
                Divider()

                VStack(alignment: .leading, spacing: 12) {
                    // Session count
                    HStack {
                        Image(systemName: "square.stack.3d.up")
                            .foregroundColor(.blue)
                        Text("\(segmentSessions.count) sessions")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    // Session list
                    if !segmentSessions.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(segmentSessions.prefix(5)) { session in
                                SessionRow(session: session)
                            }

                            if segmentSessions.count > 5 {
                                Text("+ \(segmentSessions.count - 5) more sessions")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .padding(.leading, 28)
                            }
                        }
                    }
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(focusQualityColor.opacity(0.3), lineWidth: 1)
        )
    }

    private var focusQualityColor: Color {
        guard let quality = segment.focusQuality?.lowercased() else {
            return .gray
        }

        switch quality {
        case "excellent":
            return .green
        case "good":
            return .yellow
        case "fragmented", "poor":
            return .red
        default:
            return .gray
        }
    }
}

struct SessionRow: View {
    let session: ActivitySession

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "circle.fill")
                .font(.system(size: 6))
                .foregroundColor(.blue)

            if let app = session.appName {
                Text(app)
                    .font(.caption)
                    .foregroundColor(.primary)
            }

            if let window = session.windowTitle {
                Text("•")
                    .foregroundColor(.secondary)
                Text(window)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text(session.formattedDuration)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}
