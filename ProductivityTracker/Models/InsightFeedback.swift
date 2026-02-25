import Foundation
import GRDB

/// InsightFeedback tracks user feedback on AI-generated insights.
/// This creates a learning loop where insights improve categorization over time.
struct InsightFeedback: Codable, Identifiable, Hashable {
    var id: Int64?
    var insightType: InsightType
    var insightContent: String
    var feedbackAction: FeedbackAction
    var targetType: TargetType
    var targetId: Int64?
    var targetName: String?
    var appliedChanges: String  // JSON description of changes made
    var confidence: Double
    var createdAt: Date
    var appliedAt: Date?

    init(
        id: Int64? = nil,
        insightType: InsightType,
        insightContent: String,
        feedbackAction: FeedbackAction,
        targetType: TargetType,
        targetId: Int64? = nil,
        targetName: String? = nil,
        appliedChanges: [String: Any] = [:],
        confidence: Double = 1.0,
        createdAt: Date = Date(),
        appliedAt: Date? = nil
    ) {
        self.id = id
        self.insightType = insightType
        self.insightContent = insightContent
        self.feedbackAction = feedbackAction
        self.targetType = targetType
        self.targetId = targetId
        self.targetName = targetName
        self.appliedChanges = Self.encodeChanges(appliedChanges)
        self.confidence = confidence
        self.createdAt = createdAt
        self.appliedAt = appliedAt
    }

    // MARK: - JSON Helpers

    var appliedChangesDict: [String: Any] {
        Self.decodeChanges(appliedChanges)
    }

    mutating func setAppliedChanges(_ changes: [String: Any]) {
        appliedChanges = Self.encodeChanges(changes)
    }

    private static func encodeChanges(_ changes: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: changes),
              let string = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return string
    }

    private static func decodeChanges(_ json: String) -> [String: Any] {
        guard let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return dict
    }
}

// MARK: - Enums

extension InsightFeedback {
    enum InsightType: String, Codable, CaseIterable {
        case workPattern = "work_pattern"
        case projectSuggestion = "project_suggestion"
        case categorySuggestion = "category_suggestion"
        case roleSuggestion = "role_suggestion"
        case focusPattern = "focus_pattern"
        case contextSwitch = "context_switch"
        case timeAllocation = "time_allocation"

        var displayName: String {
            switch self {
            case .workPattern: return "Work Pattern"
            case .projectSuggestion: return "Project Suggestion"
            case .categorySuggestion: return "Category Suggestion"
            case .roleSuggestion: return "Role Suggestion"
            case .focusPattern: return "Focus Pattern"
            case .contextSwitch: return "Context Switching"
            case .timeAllocation: return "Time Allocation"
            }
        }

        var icon: String {
            switch self {
            case .workPattern: return "waveform.path.ecg"
            case .projectSuggestion: return "folder.badge.plus"
            case .categorySuggestion: return "tag.fill"
            case .roleSuggestion: return "person.crop.rectangle.fill"
            case .focusPattern: return "brain.head.profile"
            case .contextSwitch: return "arrow.triangle.branch"
            case .timeAllocation: return "clock.fill"
            }
        }
    }

    enum FeedbackAction: String, Codable, CaseIterable {
        case applied = "applied"
        case dismissed = "dismissed"
        case modified = "modified"
        case deferred = "deferred"

        var displayName: String {
            switch self {
            case .applied: return "Applied"
            case .dismissed: return "Dismissed"
            case .modified: return "Modified"
            case .deferred: return "Deferred"
            }
        }
    }

    enum TargetType: String, Codable, CaseIterable {
        case project = "project"
        case category = "category"
        case role = "role"
        case session = "session"
        case global = "global"

        var displayName: String {
            switch self {
            case .project: return "Project"
            case .category: return "Category"
            case .role: return "Role"
            case .session: return "Session"
            case .global: return "Global Setting"
            }
        }
    }
}

// MARK: - GRDB Support

extension InsightFeedback: FetchableRecord, MutablePersistableRecord {
    static var databaseTableName: String { "insight_feedback" }

    enum Columns: String, ColumnExpression {
        case id, insightType, insightContent, feedbackAction
        case targetType, targetId, targetName, appliedChanges
        case confidence, createdAt, appliedAt
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

// MARK: - Actionable Insight

/// Represents an insight that can be acted upon
struct ActionableInsight: Identifiable {
    let id = UUID()
    let type: InsightFeedback.InsightType
    let title: String
    let description: String
    let confidence: Double
    let suggestedActions: [SuggestedAction]
    let relatedSessions: [Int64]
    let metadata: [String: Any]

    struct SuggestedAction: Identifiable {
        let id = UUID()
        let label: String
        let description: String
        let targetType: InsightFeedback.TargetType
        let targetId: Int64?
        let targetName: String?
        let changes: [String: Any]
        let impact: ActionImpact
    }

    enum ActionImpact: String {
        case low = "Low"
        case medium = "Medium"
        case high = "High"

        var color: String {
            switch self {
            case .low: return "#10B981"
            case .medium: return "#F59E0B"
            case .high: return "#EF4444"
            }
        }
    }
}

// MARK: - Insight Analysis Result

/// Result of analyzing sessions for actionable insights
struct InsightAnalysisResult {
    let insights: [ActionableInsight]
    let summary: String
    let totalSessionsAnalyzed: Int
    let coveragePercentage: Double
    let generatedAt: Date

    static var empty: InsightAnalysisResult {
        InsightAnalysisResult(
            insights: [],
            summary: "No insights available",
            totalSessionsAnalyzed: 0,
            coveragePercentage: 0,
            generatedAt: Date()
        )
    }
}
