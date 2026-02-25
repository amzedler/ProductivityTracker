import Foundation
import GRDB

/// MigrationManager handles database schema migrations and data transformations.
/// Migrates legacy data (workType, projectName) to new structured format.
@MainActor
final class MigrationManager {
    static let shared = MigrationManager()

    private let storageManager = StorageManager.shared
    private var dbQueue: DatabaseQueue?

    private init() {}

    // MARK: - Migration Entry Point

    /// Run all pending migrations
    func runMigrations() async throws {
        // Get database connection
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appFolder = appSupport.appendingPathComponent("ProductivityTracker", isDirectory: true)
        let databasePath = appFolder.appendingPathComponent("productivity.sqlite")

        var config = Configuration()
        config.foreignKeysEnabled = true
        dbQueue = try DatabaseQueue(path: databasePath.path, configuration: config)

        guard let db = dbQueue else { return }

        // Check migration version
        let currentVersion = try await getCurrentMigrationVersion(db)

        // Run migrations in order
        if currentVersion < 1 {
            try await migrateWorkTypesToCategories(db)
            try await setMigrationVersion(db, version: 1)
        }

        if currentVersion < 2 {
            try await migrateProjectNamesToProjects(db)
            try await setMigrationVersion(db, version: 2)
        }

        if currentVersion < 3 {
            try await linkSessionsToProjects(db)
            try await setMigrationVersion(db, version: 3)
        }

        if currentVersion < 4 {
            try await addTimelineSegmentsColumn(db)
            try await setMigrationVersion(db, version: 4)
        }
    }

    // MARK: - Migration Version Tracking

    private func getCurrentMigrationVersion(_ db: DatabaseQueue) async throws -> Int {
        try await db.read { db in
            // Create migrations table if not exists
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS migrations (
                    id INTEGER PRIMARY KEY,
                    version INTEGER NOT NULL,
                    migratedAt DATETIME NOT NULL
                )
                """)

            let sql = "SELECT MAX(version) FROM migrations"
            return try Int.fetchOne(db, sql: sql) ?? 0
        }
    }

    private func setMigrationVersion(_ db: DatabaseQueue, version: Int) async throws {
        try await db.write { db in
            try db.execute(sql: """
                INSERT INTO migrations (version, migratedAt) VALUES (?, ?)
                """, arguments: [version, Date()])
        }
    }

    // MARK: - Migration 1: WorkTypes to Categories

    /// Migrate legacy workType strings to workCategoryId references
    private func migrateWorkTypesToCategories(_ db: DatabaseQueue) async throws {
        try await db.write { db in
            // Fetch all categories for mapping
            let categories = try WorkCategory.fetchAll(db)
            let categoryMap = Dictionary(uniqueKeysWithValues: categories.compactMap { cat in
                cat.id.map { ($0, cat.slug) }
            }.map { ($1, $0) })

            // Fetch all sessions with workType but no categoryId
            let sql = """
                SELECT id, workType FROM activity_sessions
                WHERE workType IS NOT NULL AND workCategoryId IS NULL
                """
            let rows = try Row.fetchAll(db, sql: sql)

            for row in rows {
                guard let sessionId = row["id"] as? Int64,
                      let workType = row["workType"] as? String else { continue }

                // Map legacy workType to category slug
                let slug = WorkCategory.slugFromLegacyWorkType(workType)

                if let categoryId = categoryMap[slug] {
                    try db.execute(sql: """
                        UPDATE activity_sessions
                        SET workCategoryId = ?, isAICategorized = 0
                        WHERE id = ?
                        """, arguments: [categoryId, sessionId])
                }
            }
        }
    }

    // MARK: - Migration 2: ProjectNames to Projects

    /// Extract unique projectName values and create Project entities
    private func migrateProjectNamesToProjects(_ db: DatabaseQueue) async throws {
        try await db.write { db in
            // Fetch all unique project names
            let sql = """
                SELECT DISTINCT projectName FROM activity_sessions
                WHERE projectName IS NOT NULL AND projectName != ''
                """
            let projectNames = try String.fetchAll(db, sql: sql)

            // Fetch default role for assignment
            let defaultRole = try ProjectRole
                .filter(ProjectRole.Columns.isDefault == true)
                .fetchOne(db)

            for name in projectNames {
                // Check if project already exists
                let existingProject = try Project
                    .filter(Project.Columns.name == name)
                    .fetchOne(db)

                if existingProject == nil {
                    // Determine role based on pattern matching
                    let roleId = self.determineRoleForProject(name: name, patterns: ProjectRole.detectionPatterns)
                        ?? defaultRole?.id

                    // Create new project
                    var project = Project(
                        name: name,
                        roleId: roleId,
                        patterns: [name.lowercased()],
                        isAISuggested: true,
                        isUserConfirmed: false,
                        confidence: 0.5
                    )
                    try project.insert(db)
                }
            }
        }
    }

    /// Determine role based on project name patterns
    nonisolated private func determineRoleForProject(name: String, patterns: [String: [String]]) -> Int64? {
        let lowercaseName = name.lowercased()

        for (roleName, rolePatterns) in patterns {
            for pattern in rolePatterns {
                if lowercaseName.contains(pattern.lowercased()) {
                    // This is a simplified lookup - in production, query the role ID
                    return nil  // Will fall back to default role
                }
            }
        }
        return nil
    }

    // MARK: - Migration 3: Link Sessions to Projects

    /// Link existing sessions to newly created projects
    private func linkSessionsToProjects(_ db: DatabaseQueue) async throws {
        try await db.write { db in
            // Fetch all projects
            let projects = try Project.fetchAll(db)

            for project in projects {
                guard let projectId = project.id else { continue }

                // Update sessions with matching projectName
                try db.execute(sql: """
                    UPDATE activity_sessions
                    SET projectId = ?
                    WHERE projectName = ? AND projectId IS NULL
                    """, arguments: [projectId, project.name])

                // Calculate total duration for this project
                let sql = """
                    SELECT SUM(duration) FROM activity_sessions WHERE projectId = ?
                    """
                let totalDuration = try TimeInterval.fetchOne(db, sql: sql, arguments: [projectId]) ?? 0

                // Get last seen date
                let lastSeenSql = """
                    SELECT MAX(startTime) FROM activity_sessions WHERE projectId = ?
                    """
                let lastSeen = try Date.fetchOne(db, sql: lastSeenSql, arguments: [projectId])

                // Update project statistics
                try db.execute(sql: """
                    UPDATE projects
                    SET totalDuration = ?, lastSeen = ?
                    WHERE id = ?
                    """, arguments: [totalDuration, lastSeen, projectId])
            }
        }
    }

    // MARK: - Manual Migration Helpers

    /// Force re-categorize all sessions using AI
    func recategorizeAllSessions() async throws {
        // This would be called manually to re-run AI categorization
        // Implementation would call AICategorizer for each uncategorized session
    }

    /// Merge duplicate projects
    func mergeProjects(sourceId: Int64, targetId: Int64) async throws {
        guard let db = dbQueue else { return }

        try await db.write { db in
            // Update all sessions to point to target project
            try db.execute(sql: """
                UPDATE activity_sessions
                SET projectId = ?
                WHERE projectId = ?
                """, arguments: [targetId, sourceId])

            // Merge patterns
            if let sourceProject = try Project.fetchOne(db, key: sourceId),
               var targetProject = try Project.fetchOne(db, key: targetId) {
                let sourcePatterns = sourceProject.patternsArray
                var targetPatterns = targetProject.patternsArray
                targetPatterns.append(contentsOf: sourcePatterns)
                targetProject.setPatterns(Array(Set(targetPatterns)))  // Dedupe
                try targetProject.update(db)
            }

            // Delete source project
            try Project.deleteOne(db, key: sourceId)
        }
    }

    // MARK: - Migration 4: Add Timeline Segments Column

    /// Add timelineSegmentsJSON column to comprehensive_analyses table
    private func addTimelineSegmentsColumn(_ db: DatabaseQueue) async throws {
        try await db.write { db in
            // Check if column already exists
            let columns = try db.columns(in: "comprehensive_analyses")
            if !columns.contains(where: { $0.name == "timelineSegmentsJSON" }) {
                try db.execute(sql: """
                    ALTER TABLE comprehensive_analyses
                    ADD COLUMN timelineSegmentsJSON TEXT NOT NULL DEFAULT '[]'
                    """)
            }
        }
    }

    /// Archive inactive projects (not seen in 30+ days)
    func archiveInactiveProjects(olderThan days: Int = 30) async throws {
        guard let db = dbQueue else { return }

        let cutoffDate = Calendar.current.date(byAdding: .day, value: -days, to: Date())!

        try await db.write { db in
            try db.execute(sql: """
                UPDATE projects
                SET isActive = 0
                WHERE lastSeen < ? OR lastSeen IS NULL
                """, arguments: [cutoffDate])
        }
    }
}
