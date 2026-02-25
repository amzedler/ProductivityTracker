import Foundation
import GRDB

/// ActivitySession represents a tracked productivity session.
/// Enhanced with AI categorization, project linking, and concurrent context support.
struct ActivitySession: Codable, Identifiable, Hashable {
    var id: Int64?

    // Timing
    var startTime: Date
    var endTime: Date?
    var duration: TimeInterval

    // Context
    var appName: String?
    var windowTitle: String?
    var bundleIdentifier: String?

    // AI-Generated Content
    var summary: String?
    var keyInsights: String?  // JSON array of insights

    // Legacy field (for migration compatibility)
    var workType: String?
    var projectName: String?

    // New: Category and Project References
    var workCategoryId: Int64?
    var projectId: Int64?

    // New: AI Categorization Metadata
    var aiConfidence: Double?
    var isAICategorized: Bool

    // New: Concurrent Context Tracking
    var concurrentContextIds: String  // JSON array of project IDs active during this session

    // Session State
    var isActive: Bool
    var screenshotCount: Int

    var createdAt: Date
    var updatedAt: Date

    init(
        id: Int64? = nil,
        startTime: Date = Date(),
        endTime: Date? = nil,
        duration: TimeInterval = 0,
        appName: String? = nil,
        windowTitle: String? = nil,
        bundleIdentifier: String? = nil,
        summary: String? = nil,
        keyInsights: [String]? = nil,
        workType: String? = nil,
        projectName: String? = nil,
        workCategoryId: Int64? = nil,
        projectId: Int64? = nil,
        aiConfidence: Double? = nil,
        isAICategorized: Bool = false,
        concurrentContextIds: [Int64] = [],
        isActive: Bool = true,
        screenshotCount: Int = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
        self.duration = duration
        self.appName = appName
        self.windowTitle = windowTitle
        self.bundleIdentifier = bundleIdentifier
        self.summary = summary
        self.keyInsights = Self.encodeArray(keyInsights ?? [])
        self.workType = workType
        self.projectName = projectName
        self.workCategoryId = workCategoryId
        self.projectId = projectId
        self.aiConfidence = aiConfidence
        self.isAICategorized = isAICategorized
        self.concurrentContextIds = Self.encodeInt64Array(concurrentContextIds)
        self.isActive = isActive
        self.screenshotCount = screenshotCount
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    // MARK: - Array Helpers

    var keyInsightsArray: [String] {
        Self.decodeArray(keyInsights ?? "[]")
    }

    var concurrentContextIdsArray: [Int64] {
        Self.decodeInt64Array(concurrentContextIds)
    }

    mutating func setKeyInsights(_ insights: [String]) {
        keyInsights = Self.encodeArray(insights)
    }

    mutating func setConcurrentContextIds(_ ids: [Int64]) {
        concurrentContextIds = Self.encodeInt64Array(ids)
    }

    private static func encodeArray(_ array: [String]) -> String {
        guard let data = try? JSONEncoder().encode(array),
              let string = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return string
    }

    private static func decodeArray(_ json: String) -> [String] {
        guard let data = json.data(using: .utf8),
              let array = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return array
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
extension ActivitySession: FetchableRecord, MutablePersistableRecord {
    static var databaseTableName: String { "activity_sessions" }

    enum Columns: String, ColumnExpression {
        case id, startTime, endTime, duration
        case appName, windowTitle, bundleIdentifier
        case summary, keyInsights, workType, projectName
        case workCategoryId, projectId, aiConfidence, isAICategorized
        case concurrentContextIds, isActive, screenshotCount
        case createdAt, updatedAt
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

// MARK: - Relationships
extension ActivitySession {
    static let workCategory = belongsTo(WorkCategory.self)
    static let project = belongsTo(Project.self)

    var workCategory: QueryInterfaceRequest<WorkCategory> {
        request(for: ActivitySession.workCategory)
    }

    var project: QueryInterfaceRequest<Project> {
        request(for: ActivitySession.project)
    }
}

// MARK: - Computed Properties
extension ActivitySession {
    /// Formatted duration string
    var formattedDuration: String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        let seconds = Int(duration) % 60

        if hours > 0 {
            return String(format: "%dh %dm", hours, minutes)
        } else if minutes > 0 {
            return String(format: "%dm %ds", minutes, seconds)
        } else {
            return String(format: "%ds", seconds)
        }
    }

    /// Whether the session has AI categorization
    var hasAICategorization: Bool {
        isAICategorized && workCategoryId != nil
    }

    /// Whether the session has low AI confidence
    var hasLowConfidence: Bool {
        guard let confidence = aiConfidence else { return false }
        return confidence < 0.7
    }

    /// Confidence level for display
    var confidenceLevel: String {
        guard let confidence = aiConfidence else { return "Unknown" }
        switch confidence {
        case 0..<0.5: return "Low"
        case 0.5..<0.7: return "Medium"
        case 0.7..<0.9: return "High"
        default: return "Very High"
        }
    }
}

// MARK: - Session Updates
extension ActivitySession {
    /// End the session with current time
    mutating func end() {
        endTime = Date()
        isActive = false
        duration = endTime!.timeIntervalSince(startTime)
        updatedAt = Date()
    }

    /// Update duration for an active session
    mutating func updateDuration() {
        if isActive {
            duration = Date().timeIntervalSince(startTime)
            updatedAt = Date()
        }
    }

    /// Increment screenshot count
    mutating func incrementScreenshotCount() {
        screenshotCount += 1
        updatedAt = Date()
    }

    /// Apply AI categorization results
    mutating func applyAICategorization(
        categoryId: Int64?,
        projectId: Int64?,
        confidence: Double,
        concurrentIds: [Int64] = []
    ) {
        self.workCategoryId = categoryId
        self.projectId = projectId
        self.aiConfidence = confidence
        self.isAICategorized = true
        self.setConcurrentContextIds(concurrentIds)
        self.updatedAt = Date()
    }
}
