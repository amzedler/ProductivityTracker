import Foundation
import GRDB

/// ProjectRole represents a work role for segmenting projects.
/// Roles are fully user-editable and can evolve as work changes over time.
/// AI learns from user corrections to better categorize into roles.
struct ProjectRole: Codable, Identifiable, Hashable {
    var id: Int64?
    var name: String
    var description: String
    var color: String
    var icon: String
    var isDefault: Bool
    var isUserDefined: Bool
    var isActive: Bool
    var sortOrder: Int
    var createdAt: Date

    init(
        id: Int64? = nil,
        name: String,
        description: String,
        color: String,
        icon: String,
        isDefault: Bool = false,
        isUserDefined: Bool = true,
        isActive: Bool = true,
        sortOrder: Int = 0,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.color = color
        self.icon = icon
        self.isDefault = isDefault
        self.isUserDefined = isUserDefined
        self.isActive = isActive
        self.sortOrder = sortOrder
        self.createdAt = createdAt
    }
}

// MARK: - GRDB Support
extension ProjectRole: FetchableRecord, MutablePersistableRecord {
    static var databaseTableName: String { "project_roles" }

    enum Columns: String, ColumnExpression {
        case id, name, description, color, icon
        case isDefault, isUserDefined, isActive, sortOrder, createdAt
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

// MARK: - Default Roles
extension ProjectRole {
    /// Default roles for a Product Lead at Cash App (Disputes & Scams)
    /// Users can fully edit, add, rename, or archive these as work evolves
    static let defaults: [ProjectRole] = [
        ProjectRole(
            name: "Disputes",
            description: "Dispute resolution, chargebacks, customer disputes",
            color: "#EF4444",
            icon: "exclamationmark.triangle.fill",
            isDefault: true,
            isUserDefined: false,
            sortOrder: 0
        ),
        ProjectRole(
            name: "Scams",
            description: "Scam prevention, fraud detection, user protection",
            color: "#F97316",
            icon: "shield.lefthalf.filled",
            isDefault: false,
            isUserDefined: false,
            sortOrder: 1
        ),
        ProjectRole(
            name: "Cross-team",
            description: "Cross-functional initiatives, company-wide projects",
            color: "#8B5CF6",
            icon: "arrow.triangle.branch",
            isDefault: false,
            isUserDefined: false,
            sortOrder: 2
        ),
        ProjectRole(
            name: "Personal",
            description: "Personal development, learning, non-work activities",
            color: "#6B7280",
            icon: "person.fill",
            isDefault: false,
            isUserDefined: false,
            sortOrder: 3
        )
    ]

    /// Detection patterns for AI to identify roles from context
    static let detectionPatterns: [String: [String]] = [
        "Disputes": ["DISP-", "dispute", "chargeback", "refund", "claim"],
        "Scams": ["SCAM-", "scam", "fraud", "suspicious", "security"],
        "Cross-team": ["cross-team", "company-wide", "platform", "initiative"],
        "Personal": ["personal", "learning", "development", "side project"]
    ]
}
