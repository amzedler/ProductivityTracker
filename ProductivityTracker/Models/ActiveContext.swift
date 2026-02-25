import Foundation

/// ActiveContext represents a currently active work context for concurrent tracking.
/// Used by WindowFocusMonitor to track multiple parallel work streams.
struct ActiveContext: Codable, Identifiable, Hashable {
    let id: UUID
    var projectId: Int64?
    var projectName: String
    var roleId: Int64?
    var appName: String?
    var windowTitle: String?

    /// When this context was first detected
    var startedAt: Date

    /// Last time this context was seen in focus
    var lastSeenAt: Date

    /// Total focused time in this context (seconds)
    var focusedDuration: TimeInterval

    /// Whether this is the currently focused context
    var isFocused: Bool

    /// Focus percentage relative to total session time
    var focusPercentage: Double

    init(
        id: UUID = UUID(),
        projectId: Int64? = nil,
        projectName: String,
        roleId: Int64? = nil,
        appName: String? = nil,
        windowTitle: String? = nil,
        startedAt: Date = Date(),
        lastSeenAt: Date = Date(),
        focusedDuration: TimeInterval = 0,
        isFocused: Bool = false,
        focusPercentage: Double = 0
    ) {
        self.id = id
        self.projectId = projectId
        self.projectName = projectName
        self.roleId = roleId
        self.appName = appName
        self.windowTitle = windowTitle
        self.startedAt = startedAt
        self.lastSeenAt = lastSeenAt
        self.focusedDuration = focusedDuration
        self.isFocused = isFocused
        self.focusPercentage = focusPercentage
    }

    /// Whether this context is stale (not seen in 30+ minutes)
    var isStale: Bool {
        Date().timeIntervalSince(lastSeenAt) > 30 * 60
    }

    /// Time since last focus
    var timeSinceLastFocus: TimeInterval {
        Date().timeIntervalSince(lastSeenAt)
    }

    /// Age of this context
    var age: TimeInterval {
        Date().timeIntervalSince(startedAt)
    }

    /// Update focus state
    mutating func updateFocus(isFocused: Bool, duration: TimeInterval = 0) {
        self.isFocused = isFocused
        if isFocused {
            self.lastSeenAt = Date()
            self.focusedDuration += duration
        }
    }

    /// Calculate focus percentage based on total elapsed time
    mutating func updateFocusPercentage() {
        let totalTime = age
        if totalTime > 0 {
            focusPercentage = (focusedDuration / totalTime) * 100
        }
    }
}

// MARK: - Context Comparison
extension ActiveContext {
    /// Check if this context matches another context (same project)
    func matches(_ other: ActiveContext) -> Bool {
        if let projectId = projectId, let otherProjectId = other.projectId {
            return projectId == otherProjectId
        }
        return projectName.lowercased() == other.projectName.lowercased()
    }

    /// Check if this context matches an app/window combination
    func matchesWindow(appName: String?, windowTitle: String?) -> Bool {
        guard let contextApp = self.appName, let targetApp = appName else {
            return false
        }
        return contextApp == targetApp &&
               self.windowTitle?.contains(windowTitle ?? "") == true
    }
}

// MARK: - Display Helpers
extension ActiveContext {
    /// Formatted focus duration
    var formattedFocusedDuration: String {
        let hours = Int(focusedDuration) / 3600
        let minutes = (Int(focusedDuration) % 3600) / 60

        if hours > 0 {
            return String(format: "%dh %dm", hours, minutes)
        } else {
            return String(format: "%dm", minutes)
        }
    }

    /// Formatted focus percentage
    var formattedFocusPercentage: String {
        String(format: "%.0f%%", focusPercentage)
    }

    /// Status color based on focus state
    var statusColor: String {
        if isFocused {
            return "#10B981"  // Green - focused
        } else if timeSinceLastFocus < 5 * 60 {
            return "#F59E0B"  // Yellow - recently active
        } else {
            return "#6B7280"  // Gray - background
        }
    }

    /// Status description
    var statusDescription: String {
        if isFocused {
            return "Focused"
        } else if isStale {
            return "Inactive"
        } else {
            let minutes = Int(timeSinceLastFocus / 60)
            return "Last active \(minutes)m ago"
        }
    }
}
