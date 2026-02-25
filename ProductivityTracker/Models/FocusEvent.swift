import Foundation
import GRDB

/// FocusEvent represents a window focus change event.
/// Used for tracking application and window transitions.
struct FocusEvent: Codable, Identifiable, Hashable {
    var id: Int64?
    var timestamp: Date
    var appName: String
    var bundleIdentifier: String?
    var windowTitle: String?

    // Associated project/category (if determined)
    var projectId: Int64?
    var categoryId: Int64?

    // Concurrent context IDs active at this moment
    var concurrentContextIds: String

    // Duration in this focus state (until next event)
    var duration: TimeInterval?

    var createdAt: Date

    init(
        id: Int64? = nil,
        timestamp: Date = Date(),
        appName: String,
        bundleIdentifier: String? = nil,
        windowTitle: String? = nil,
        projectId: Int64? = nil,
        categoryId: Int64? = nil,
        concurrentContextIds: [Int64] = [],
        duration: TimeInterval? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.timestamp = timestamp
        self.appName = appName
        self.bundleIdentifier = bundleIdentifier
        self.windowTitle = windowTitle
        self.projectId = projectId
        self.categoryId = categoryId
        self.concurrentContextIds = Self.encodeInt64Array(concurrentContextIds)
        self.duration = duration
        self.createdAt = createdAt
    }

    // MARK: - Concurrent Context Helpers

    var concurrentContextIdsArray: [Int64] {
        Self.decodeInt64Array(concurrentContextIds)
    }

    mutating func setConcurrentContextIds(_ ids: [Int64]) {
        concurrentContextIds = Self.encodeInt64Array(ids)
    }

    private static func encodeInt64Array(_ array: [Int64]) -> String {
        guard let data = try? JSONEncoder().encode(array),
              let string = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return string
    }

    private static func decodeInt64Array(_ json: String) -> [Int64] {
        guard let data = json.data(using: .utf8),
              let array = try? JSONDecoder().decode([Int64].self, from: data) else {
            return []
        }
        return array
    }
}

// MARK: - GRDB Support
extension FocusEvent: FetchableRecord, MutablePersistableRecord {
    static var databaseTableName: String { "focus_events" }

    enum Columns: String, ColumnExpression {
        case id, timestamp, appName, bundleIdentifier, windowTitle
        case projectId, categoryId, concurrentContextIds, duration, createdAt
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

// MARK: - Display Helpers
extension FocusEvent {
    /// Formatted duration string
    var formattedDuration: String? {
        guard let duration = duration else { return nil }
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60

        if minutes > 0 {
            return String(format: "%dm %ds", minutes, seconds)
        } else {
            return String(format: "%ds", seconds)
        }
    }

    /// Short app name for display
    var shortAppName: String {
        // Remove common suffixes
        let suffixes = [".app", " Helper", " Agent"]
        var name = appName
        for suffix in suffixes {
            if name.hasSuffix(suffix) {
                name = String(name.dropLast(suffix.count))
            }
        }
        return name
    }

    /// Icon name based on app type
    var appIcon: String {
        switch appName.lowercased() {
        case let name where name.contains("slack"):
            return "bubble.left.and.bubble.right.fill"
        case let name where name.contains("chrome") || name.contains("safari") || name.contains("firefox"):
            return "globe"
        case let name where name.contains("code") || name.contains("xcode"):
            return "chevron.left.forwardslash.chevron.right"
        case let name where name.contains("terminal") || name.contains("iterm"):
            return "terminal.fill"
        case let name where name.contains("zoom") || name.contains("meet"):
            return "video.fill"
        case let name where name.contains("mail") || name.contains("outlook"):
            return "envelope.fill"
        case let name where name.contains("figma") || name.contains("sketch"):
            return "paintbrush.fill"
        case let name where name.contains("notion") || name.contains("notes"):
            return "doc.text.fill"
        default:
            return "app.fill"
        }
    }
}
