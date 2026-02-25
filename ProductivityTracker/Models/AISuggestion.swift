import Foundation
import GRDB

/// AISuggestion represents a pending AI suggestion for user review.
/// Low-confidence categorizations are queued here for user verification.
struct AISuggestion: Codable, Identifiable, Hashable {
    var id: Int64?
    var sessionId: Int64
    var suggestionType: SuggestionType
    var suggestedValue: String
    var confidence: Double
    var reasoning: String
    var context: String  // JSON-encoded context data
    var status: SuggestionStatus
    var userModifiedValue: String?
    var createdAt: Date
    var resolvedAt: Date?

    init(
        id: Int64? = nil,
        sessionId: Int64,
        suggestionType: SuggestionType,
        suggestedValue: String,
        confidence: Double,
        reasoning: String,
        context: [String: String] = [:],
        status: SuggestionStatus = .pending,
        userModifiedValue: String? = nil,
        createdAt: Date = Date(),
        resolvedAt: Date? = nil
    ) {
        self.id = id
        self.sessionId = sessionId
        self.suggestionType = suggestionType
        self.suggestedValue = suggestedValue
        self.confidence = confidence
        self.reasoning = reasoning
        self.context = Self.encodeContext(context)
        self.status = status
        self.userModifiedValue = userModifiedValue
        self.createdAt = createdAt
        self.resolvedAt = resolvedAt
    }

    // MARK: - Context Helpers

    var contextDict: [String: String] {
        Self.decodeContext(context)
    }

    mutating func setContext(_ newContext: [String: String]) {
        context = Self.encodeContext(newContext)
    }

    private static func encodeContext(_ context: [String: String]) -> String {
        guard let data = try? JSONEncoder().encode(context),
              let string = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return string
    }

    private static func decodeContext(_ json: String) -> [String: String] {
        guard let data = json.data(using: .utf8),
              let context = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return context
    }
}

// MARK: - Suggestion Types
extension AISuggestion {
    enum SuggestionType: String, Codable, CaseIterable {
        case project = "project"
        case category = "category"
        case role = "role"
        case newProject = "new_project"

        var displayName: String {
            switch self {
            case .project: return "Project"
            case .category: return "Category"
            case .role: return "Role"
            case .newProject: return "New Project"
            }
        }

        var icon: String {
            switch self {
            case .project: return "folder.fill"
            case .category: return "tag.fill"
            case .role: return "person.crop.rectangle.fill"
            case .newProject: return "plus.rectangle.fill"
            }
        }
    }

    enum SuggestionStatus: String, Codable, CaseIterable {
        case pending = "pending"
        case accepted = "accepted"
        case rejected = "rejected"
        case modified = "modified"

        var displayName: String {
            switch self {
            case .pending: return "Pending"
            case .accepted: return "Accepted"
            case .rejected: return "Rejected"
            case .modified: return "Modified"
            }
        }

        var color: String {
            switch self {
            case .pending: return "#F59E0B"
            case .accepted: return "#10B981"
            case .rejected: return "#EF4444"
            case .modified: return "#3B82F6"
            }
        }
    }
}

// MARK: - GRDB Support
extension AISuggestion: FetchableRecord, MutablePersistableRecord {
    static var databaseTableName: String { "ai_suggestions" }

    enum Columns: String, ColumnExpression {
        case id, sessionId, suggestionType, suggestedValue, confidence
        case reasoning, context, status, userModifiedValue, createdAt, resolvedAt
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

// MARK: - Computed Properties
extension AISuggestion {
    /// Whether this suggestion needs user attention
    var needsReview: Bool {
        status == .pending
    }

    /// Confidence level description
    var confidenceLevel: ConfidenceLevel {
        switch confidence {
        case 0..<0.5: return .low
        case 0.5..<0.7: return .medium
        case 0.7..<0.9: return .high
        default: return .veryHigh
        }
    }

    enum ConfidenceLevel: String {
        case low = "Low"
        case medium = "Medium"
        case high = "High"
        case veryHigh = "Very High"

        var color: String {
            switch self {
            case .low: return "#EF4444"
            case .medium: return "#F59E0B"
            case .high: return "#10B981"
            case .veryHigh: return "#059669"
            }
        }
    }

    /// Format confidence as percentage string
    var confidencePercentage: String {
        "\(Int(confidence * 100))%"
    }
}

// MARK: - Actions
extension AISuggestion {
    /// Accept the suggestion as-is
    mutating func accept() {
        status = .accepted
        resolvedAt = Date()
    }

    /// Reject the suggestion
    mutating func reject() {
        status = .rejected
        resolvedAt = Date()
    }

    /// Modify the suggestion with a new value
    mutating func modify(newValue: String) {
        status = .modified
        userModifiedValue = newValue
        resolvedAt = Date()
    }
}
