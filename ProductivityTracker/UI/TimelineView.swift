import SwiftUI

/// TimelineView displays a visual timeline of activities throughout the day
@available(macOS 14.0, *)
struct TimelineView: View {
    let segments: [TimelineSegment]
    let totalDuration: TimeInterval

    // Calculate start and end of the timeline
    private var timelineStart: Date {
        segments.map { $0.startTime }.min() ?? Date()
    }

    private var timelineEnd: Date {
        segments.map { $0.endTime }.max() ?? Date()
    }

    private var timelineDuration: TimeInterval {
        timelineEnd.timeIntervalSince(timelineStart)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Text("Activity Timeline")
                    .font(.headline)
                    .fontWeight(.semibold)

                Spacer()

                Text(formatTimeRange(start: timelineStart, end: timelineEnd))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if segments.isEmpty {
                emptyState
            } else {
                // Timeline visualization
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        ForEach(segments) { segment in
                            TimelineSegmentView(
                                segment: segment,
                                totalDuration: timelineDuration
                            )
                        }
                    }
                    .frame(height: 80)
                    .frame(minWidth: 600)
                }

                // Legend
                legendView
            }
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .cornerRadius(12)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.bar.xaxis")
                .font(.largeTitle)
                .foregroundColor(.secondary)

            Text("No timeline data available")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private var legendView: some View {
        let uniqueActivities = Dictionary(grouping: segments, by: { $0.activityType })
            .map { (type, segments) in
                (type: type,
                 color: segments.first?.categoryColor ?? "#666666",
                 duration: segments.reduce(0) { $0 + $1.duration })
            }
            .sorted { $0.duration > $1.duration }

        return VStack(alignment: .leading, spacing: 6) {
            Text("Activity Types")
                .font(.caption2)
                .foregroundColor(.secondary)
                .textCase(.uppercase)

            FlowLayout(spacing: 8) {
                ForEach(uniqueActivities, id: \.type) { activity in
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color(hex: activity.color))
                            .frame(width: 8, height: 8)

                        Text(activity.type)
                            .font(.caption)

                        Text("(\(formatDuration(activity.duration)))")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(6)
                }
            }
        }
    }

    private func formatTimeRange(start: Date, end: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return "\(formatter.string(from: start)) - \(formatter.string(from: end))"
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        if minutes < 60 {
            return "\(minutes)m"
        } else {
            let hours = minutes / 60
            let mins = minutes % 60
            return "\(hours)h \(mins)m"
        }
    }
}

/// Individual segment in the timeline
@available(macOS 14.0, *)
struct TimelineSegmentView: View {
    let segment: TimelineSegment
    let totalDuration: TimeInterval

    @State private var isHovered = false

    private var widthPercentage: CGFloat {
        guard totalDuration > 0 else { return 0 }
        return CGFloat(segment.duration / totalDuration)
    }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // Activity bar
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(hex: segment.categoryColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(Color.white.opacity(0.3), lineWidth: 1)
                    )
                    .frame(height: 40)

                // Time label
                if widthPercentage > 0.05 { // Only show if segment is wide enough
                    Text(segment.activityType)
                        .font(.caption2)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 4)
                }
            }
            .frame(width: max(geometry.size.width * widthPercentage, 20))
        }
        .frame(width: max(600 * widthPercentage, 20))
        .popover(isPresented: $isHovered) {
            TimelineSegmentDetailView(segment: segment)
        }
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

/// Detail view shown when hovering over a timeline segment
@available(macOS 14.0, *)
struct TimelineSegmentDetailView: View {
    let segment: TimelineSegment

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle()
                    .fill(Color(hex: segment.categoryColor))
                    .frame(width: 10, height: 10)

                Text(segment.activityType)
                    .font(.headline)
            }

            if let appName = segment.appName {
                HStack {
                    Image(systemName: "app.fill")
                        .foregroundColor(.secondary)
                        .font(.caption)
                    Text(appName)
                        .font(.subheadline)
                }
            }

            Divider()

            HStack {
                Image(systemName: "clock")
                    .foregroundColor(.secondary)
                    .font(.caption)
                Text(formatTime(segment.startTime))
                Text("-")
                Text(formatTime(segment.endTime))
            }
            .font(.caption)

            HStack {
                Image(systemName: "hourglass")
                    .foregroundColor(.secondary)
                    .font(.caption)
                Text(segment.formattedDuration)
            }
            .font(.caption)
        }
        .padding(12)
        .frame(minWidth: 200)
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

/// Flow layout for wrapping legend items
struct FlowLayout: Layout {
    var spacing: CGFloat = 10

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(
            in: proposal.replacingUnspecifiedDimensions().width,
            subviews: subviews,
            spacing: spacing
        )
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(
            in: bounds.width,
            subviews: subviews,
            spacing: spacing
        )
        for (index, subview) in subviews.enumerated() {
            subview.place(at: result.positions[index], proposal: .unspecified)
        }
    }

    struct FlowResult {
        var size: CGSize
        var positions: [CGPoint]

        init(in width: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var positions: [CGPoint] = []
            var size: CGSize = .zero
            var x: CGFloat = 0
            var y: CGFloat = 0
            var lineHeight: CGFloat = 0

            for subview in subviews {
                let subviewSize = subview.sizeThatFits(.unspecified)

                if x + subviewSize.width > width, x > 0 {
                    x = 0
                    y += lineHeight + spacing
                    lineHeight = 0
                }

                positions.append(CGPoint(x: x, y: y))
                x += subviewSize.width + spacing
                lineHeight = max(lineHeight, subviewSize.height)
                size.width = max(size.width, x - spacing)
            }

            size.height = y + lineHeight
            self.size = size
            self.positions = positions
        }
    }
}

@available(macOS 14.0, *)
#Preview {
    let sampleSegments = [
        TimelineSegment(
            startTime: Date().addingTimeInterval(-7200),
            endTime: Date().addingTimeInterval(-5400),
            activityType: "Coding",
            categoryColor: "#4A90E2",
            appName: "Xcode"
        ),
        TimelineSegment(
            startTime: Date().addingTimeInterval(-5400),
            endTime: Date().addingTimeInterval(-4800),
            activityType: "Meeting",
            categoryColor: "#F5A623",
            appName: "Zoom"
        ),
        TimelineSegment(
            startTime: Date().addingTimeInterval(-4800),
            endTime: Date().addingTimeInterval(-3600),
            activityType: "Coding",
            categoryColor: "#4A90E2",
            appName: "Xcode"
        )
    ]

    TimelineView(segments: sampleSegments, totalDuration: 3600)
        .padding()
        .frame(width: 800)
}
