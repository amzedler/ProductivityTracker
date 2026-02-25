import Foundation
import GRDB

/// Project represents an explicit project entity with AI-learned patterns.
/// Replaces inline projectName strings with structured, trackable entities.
struct Project: Codable, Identifiable, Hashable {
    var id: Int64?
    var name: String
    var roleId: Int64?
    var defaultCategoryId: Int64?

    /// JSON-encoded array of detection patterns (e.g., ["DISP-123", "disputes-roadmap"])
    var patterns: String

    /// JSON-encoded array of source hints (e.g., ["Linear", "Slack #disputes"])
    var sources: String

    var isActive: Bool
    var isAISuggested: Bool
    var isUserConfirmed: Bool
    var confidence: Double
    var totalDuration: TimeInterval
    var lastSeen: Date?
    var createdAt: Date
    var notes: String?

    init(
        id: Int64? = nil,
        name: String,
        roleId: Int64? = nil,
        defaultCategoryId: Int64? = nil,
        patterns: [String] = [],
        sources: [String] = [],
        isActive: Bool = true,
        isAISuggested: Bool = false,
        isUserConfirmed: Bool = false,
        confidence: Double = 1.0,
        totalDuration: TimeInterval = 0,
        lastSeen: Date? = nil,
        createdAt: Date = Date(),
        notes: String? = nil
    ) {
        self.id = id
        self.name = name
        self.roleId = roleId
        self.defaultCategoryId = defaultCategoryId
        self.patterns = Self.encodePatterns(patterns)
        self.sources = Self.encodePatterns(sources)
        self.isActive = isActive
        self.isAISuggested = isAISuggested
        self.isUserConfirmed = isUserConfirmed
        self.confidence = confidence
        self.totalDuration = totalDuration
        self.lastSeen = lastSeen
        self.createdAt = createdAt
        self.notes = notes
    }

    // MARK: - Pattern Helpers

    /// Decoded patterns array
    var patternsArray: [String] {
        Self.decodePatterns(patterns)
    }

    /// Decoded sources array
    var sourcesArray: [String] {
        Self.decodePatterns(sources)
    }

    /// Update patterns array
    mutating func setPatterns(_ newPatterns: [String]) {
        patterns = Self.encodePatterns(newPatterns)
    }

    /// Update sources array
    mutating func setSources(_ newSources: [String]) {
        sources = Self.encodePatterns(newSources)
    }

    /// Add a new pattern if not already present
    mutating func addPattern(_ pattern: String) {
        var current = patternsArray
        if !current.contains(pattern) {
            current.append(pattern)
            setPatterns(current)
        }
    }

    /// Add a new source if not already present
    mutating func addSource(_ source: String) {
        var current = sourcesArray
        if !current.contains(source) {
            current.append(source)
            setSources(current)
        }
    }

    private static func encodePatterns(_ patterns: [String]) -> String {
        guard let data = try? JSONEncoder().encode(patterns),
              let string = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return string
    }

    private static func decodePatterns(_ json: String) -> [String] {
        guard let data = json.data(using: .utf8),
              let patterns = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return patterns
    }
}

// MARK: - GRDB Support
extension Project: FetchableRecord, MutablePersistableRecord {
    static var databaseTableName: String { "projects" }

    enum Columns: String, ColumnExpression {
        case id, name, roleId, defaultCategoryId, patterns, sources
        case isActive, isAISuggested, isUserConfirmed, confidence
        case totalDuration, lastSeen, createdAt, notes
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

// MARK: - Project Matching
extension Project {
    /// Check if this project matches the given context
    func matches(projectName: String?, appName: String?, windowTitle: String?) -> Bool {
        let patterns = patternsArray
        if patterns.isEmpty { return false }

        let searchText = [projectName, appName, windowTitle]
            .compactMap { $0?.lowercased() }
            .joined(separator: " ")

        return patterns.contains { pattern in
            searchText.contains(pattern.lowercased())
        }
    }

    /// Calculate match confidence based on pattern matches
    func matchConfidence(projectName: String?, appName: String?, windowTitle: String?) -> Double {
        let patterns = patternsArray
        if patterns.isEmpty { return 0.0 }

        let searchText = [projectName, appName, windowTitle]
            .compactMap { $0?.lowercased() }
            .joined(separator: " ")

        let matchCount = patterns.filter { pattern in
            searchText.contains(pattern.lowercased())
        }.count

        return Double(matchCount) / Double(patterns.count)
    }
}

// MARK: - Relationships
extension Project {
    static let role = belongsTo(ProjectRole.self)
    static let category = belongsTo(WorkCategory.self, key: "defaultCategory", using: ForeignKey(["defaultCategoryId"]))

    var role: QueryInterfaceRequest<ProjectRole> {
        request(for: Project.role)
    }

    var category: QueryInterfaceRequest<WorkCategory> {
        request(for: Project.category)
    }
}
