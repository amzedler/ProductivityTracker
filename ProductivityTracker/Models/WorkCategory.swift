import Foundation
import GRDB

/// WorkCategory represents a user-centric work category for activity classification.
/// Replaces the old workType string with a structured, user-editable category system.
struct WorkCategory: Codable, Identifiable, Hashable {
    var id: Int64?
    var name: String
    var slug: String
    var icon: String
    var color: String
    var description: String
    var isBuiltIn: Bool
    var isActive: Bool
    var sortOrder: Int
    var createdAt: Date

    init(
        id: Int64? = nil,
        name: String,
        slug: String,
        icon: String,
        color: String,
        description: String,
        isBuiltIn: Bool = false,
        isActive: Bool = true,
        sortOrder: Int = 0,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.slug = slug
        self.icon = icon
        self.color = color
        self.description = description
        self.isBuiltIn = isBuiltIn
        self.isActive = isActive
        self.sortOrder = sortOrder
        self.createdAt = createdAt
    }
}

// MARK: - GRDB Support
extension WorkCategory: FetchableRecord, MutablePersistableRecord {
    static var databaseTableName: String { "work_categories" }

    enum Columns: String, ColumnExpression {
        case id, name, slug, icon, color, description
        case isBuiltIn, isActive, sortOrder, createdAt
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

// MARK: - Default Categories
extension WorkCategory {
    /// Default built-in categories that are seeded on first launch
    static let defaults: [WorkCategory] = [
        WorkCategory(
            name: "Personal",
            slug: "personal",
            icon: "person.fill",
            color: "#9CA3AF",
            description: "Non-work activities, personal browsing, entertainment",
            isBuiltIn: true,
            sortOrder: 0
        ),
        WorkCategory(
            name: "Discovery",
            slug: "discovery",
            icon: "magnifyingglass",
            color: "#8B5CF6",
            description: "Research, learning, exploration, reading documentation",
            isBuiltIn: true,
            sortOrder: 1
        ),
        WorkCategory(
            name: "Responding",
            slug: "responding",
            icon: "envelope.fill",
            color: "#3B82F6",
            description: "Email, Slack, reviews, approvals, feedback",
            isBuiltIn: true,
            sortOrder: 2
        ),
        WorkCategory(
            name: "Creating",
            slug: "creating",
            icon: "pencil.and.outline",
            color: "#10B981",
            description: "Writing, coding, designing, building new things",
            isBuiltIn: true,
            sortOrder: 3
        ),
        WorkCategory(
            name: "Meetings",
            slug: "meetings",
            icon: "video.fill",
            color: "#F59E0B",
            description: "Video calls, calendar events, syncs",
            isBuiltIn: true,
            sortOrder: 4
        ),
        WorkCategory(
            name: "Planning",
            slug: "planning",
            icon: "calendar.badge.clock",
            color: "#EC4899",
            description: "Roadmaps, strategy, prioritization, backlog grooming",
            isBuiltIn: true,
            sortOrder: 5
        ),
        WorkCategory(
            name: "Coordinating",
            slug: "coordinating",
            icon: "person.3.fill",
            color: "#14B8A6",
            description: "Cross-functional work, stakeholder management, alignment",
            isBuiltIn: true,
            sortOrder: 6
        )
    ]

    /// Maps old workType strings to new category slugs
    static func slugFromLegacyWorkType(_ workType: String) -> String {
        switch workType.lowercased() {
        case "coding", "documentation", "debugging", "design":
            return "creating"
        case "research", "browsing":
            return "discovery"
        case "communication":
            return "responding"
        case "meetings":
            return "meetings"
        case "planning":
            return "planning"
        case "entertainment", "other":
            return "personal"
        default:
            return "personal"
        }
    }
}
