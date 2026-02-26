import Foundation
import GRDB
import Combine

/// StorageManager handles all database operations using GRDB.
/// Manages tables for sessions, projects, categories, roles, and AI suggestions.
@MainActor
final class StorageManager: ObservableObject {
    static let shared = StorageManager()

    private var dbQueue: DatabaseQueue?
    private let databasePath: URL

    @Published var isInitialized = false
    @Published var lastError: Error?

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appFolder = appSupport.appendingPathComponent("ProductivityTracker", isDirectory: true)

        // Create directory if needed
        try? FileManager.default.createDirectory(at: appFolder, withIntermediateDirectories: true)

        databasePath = appFolder.appendingPathComponent("productivity.sqlite")
    }

    // MARK: - Initialization

    func initialize() async throws {
        var config = Configuration()
        config.foreignKeysEnabled = true

        dbQueue = try DatabaseQueue(path: databasePath.path, configuration: config)

        try await createTables()
        try await seedDefaultData()

        isInitialized = true
    }

    /// Get database queue for use by other services (e.g., CacheManager)
    func getDatabaseQueue() -> DatabaseQueue? {
        return dbQueue
    }

    private func createTables() async throws {
        guard let dbQueue = dbQueue else { return }

        try await dbQueue.write { db in
            // Work Categories table
            try db.create(table: "work_categories", ifNotExists: true) { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull()
                t.column("slug", .text).notNull().unique()
                t.column("icon", .text).notNull()
                t.column("color", .text).notNull()
                t.column("description", .text).notNull()
                t.column("isBuiltIn", .boolean).notNull().defaults(to: false)
                t.column("isActive", .boolean).notNull().defaults(to: true)
                t.column("sortOrder", .integer).notNull().defaults(to: 0)
                t.column("createdAt", .datetime).notNull()
            }

            // Project Roles table
            try db.create(table: "project_roles", ifNotExists: true) { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull()
                t.column("description", .text).notNull()
                t.column("color", .text).notNull()
                t.column("icon", .text).notNull()
                t.column("isDefault", .boolean).notNull().defaults(to: false)
                t.column("isUserDefined", .boolean).notNull().defaults(to: true)
                t.column("isActive", .boolean).notNull().defaults(to: true)
                t.column("sortOrder", .integer).notNull().defaults(to: 0)
                t.column("createdAt", .datetime).notNull()
            }

            // Projects table
            try db.create(table: "projects", ifNotExists: true) { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull()
                t.column("roleId", .integer).references("project_roles", onDelete: .setNull)
                t.column("defaultCategoryId", .integer).references("work_categories", onDelete: .setNull)
                t.column("patterns", .text).notNull().defaults(to: "[]")
                t.column("sources", .text).notNull().defaults(to: "[]")
                t.column("isActive", .boolean).notNull().defaults(to: true)
                t.column("isAISuggested", .boolean).notNull().defaults(to: false)
                t.column("isUserConfirmed", .boolean).notNull().defaults(to: false)
                t.column("confidence", .double).notNull().defaults(to: 1.0)
                t.column("totalDuration", .double).notNull().defaults(to: 0)
                t.column("lastSeen", .datetime)
                t.column("createdAt", .datetime).notNull()
                t.column("notes", .text)
            }

            // Activity Sessions table
            try db.create(table: "activity_sessions", ifNotExists: true) { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("startTime", .datetime).notNull()
                t.column("endTime", .datetime)
                t.column("duration", .double).notNull().defaults(to: 0)
                t.column("appName", .text)
                t.column("windowTitle", .text)
                t.column("bundleIdentifier", .text)
                t.column("summary", .text)
                t.column("keyInsights", .text)
                t.column("workType", .text)  // Legacy
                t.column("projectName", .text)  // Legacy
                t.column("workCategoryId", .integer).references("work_categories", onDelete: .setNull)
                t.column("projectId", .integer).references("projects", onDelete: .setNull)
                t.column("aiConfidence", .double)
                t.column("isAICategorized", .boolean).notNull().defaults(to: false)
                t.column("concurrentContextIds", .text).notNull().defaults(to: "[]")
                t.column("isActive", .boolean).notNull().defaults(to: true)
                t.column("screenshotCount", .integer).notNull().defaults(to: 0)
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }

            // AI Suggestions table
            try db.create(table: "ai_suggestions", ifNotExists: true) { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("sessionId", .integer).notNull().references("activity_sessions", onDelete: .cascade)
                t.column("suggestionType", .text).notNull()
                t.column("suggestedValue", .text).notNull()
                t.column("confidence", .double).notNull()
                t.column("reasoning", .text).notNull()
                t.column("context", .text).notNull().defaults(to: "{}")
                t.column("status", .text).notNull().defaults(to: "pending")
                t.column("userModifiedValue", .text)
                t.column("createdAt", .datetime).notNull()
                t.column("resolvedAt", .datetime)
            }

            // Focus Events table
            try db.create(table: "focus_events", ifNotExists: true) { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("timestamp", .datetime).notNull()
                t.column("appName", .text).notNull()
                t.column("bundleIdentifier", .text)
                t.column("windowTitle", .text)
                t.column("projectId", .integer).references("projects", onDelete: .setNull)
                t.column("categoryId", .integer).references("work_categories", onDelete: .setNull)
                t.column("concurrentContextIds", .text).notNull().defaults(to: "[]")
                t.column("duration", .double)
                t.column("createdAt", .datetime).notNull()
            }

            // Insight Feedback table - tracks user feedback on AI insights
            try db.create(table: "insight_feedback", ifNotExists: true) { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("insightType", .text).notNull()
                t.column("insightContent", .text).notNull()
                t.column("feedbackAction", .text).notNull()
                t.column("targetType", .text).notNull()
                t.column("targetId", .integer)
                t.column("targetName", .text)
                t.column("appliedChanges", .text).notNull().defaults(to: "{}")
                t.column("confidence", .double).notNull().defaults(to: 1.0)
                t.column("createdAt", .datetime).notNull()
                t.column("appliedAt", .datetime)
            }

            // Comprehensive Analyses table - stores Claude-powered analysis results
            try db.create(table: "comprehensive_analyses", ifNotExists: true) { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("date", .date).notNull()
                t.column("period", .text).notNull()
                t.column("overview", .text).notNull()
                t.column("workSegmentsJSON", .text).notNull().defaults(to: "[]")
                t.column("contextAnalysis", .text).notNull()
                t.column("keyInsightsJSON", .text).notNull().defaults(to: "[]")
                t.column("recommendationsJSON", .text).notNull().defaults(to: "[]")
                t.column("totalTime", .double).notNull()
                t.column("sessionCount", .integer).notNull()
                t.column("analysisTimestamp", .datetime).notNull()
                t.column("followUpExchangesJSON", .text).notNull().defaults(to: "[]")
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }

            // Cached Categorizations table - for offline tracking
            try db.create(table: "cached_categorizations", ifNotExists: true) { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("appName", .text).notNull()
                t.column("windowTitle", .text)
                t.column("projectName", .text).notNull()
                t.column("projectRole", .text).notNull()
                t.column("workCategory", .text).notNull()
                t.column("patternsJSON", .text).notNull().defaults(to: "[]")
                t.column("confidence", .double).notNull()
                t.column("timestamp", .datetime).notNull()
                t.column("useCount", .integer).notNull().defaults(to: 0)
            }

            // Create indexes for better query performance
            try db.create(index: "idx_sessions_startTime", on: "activity_sessions", columns: ["startTime"], ifNotExists: true)
            try db.create(index: "idx_sessions_projectId", on: "activity_sessions", columns: ["projectId"], ifNotExists: true)
            try db.create(index: "idx_sessions_categoryId", on: "activity_sessions", columns: ["workCategoryId"], ifNotExists: true)
            try db.create(index: "idx_suggestions_status", on: "ai_suggestions", columns: ["status"], ifNotExists: true)
            try db.create(index: "idx_focus_timestamp", on: "focus_events", columns: ["timestamp"], ifNotExists: true)
            try db.create(index: "idx_projects_roleId", on: "projects", columns: ["roleId"], ifNotExists: true)
            try db.create(index: "idx_feedback_type", on: "insight_feedback", columns: ["insightType"], ifNotExists: true)
            try db.create(index: "idx_analyses_date_period", on: "comprehensive_analyses", columns: ["date", "period"], ifNotExists: true)
            try db.create(index: "idx_analyses_timestamp", on: "comprehensive_analyses", columns: ["analysisTimestamp"], ifNotExists: true)
            try db.create(index: "idx_cache_app", on: "cached_categorizations", columns: ["appName"], ifNotExists: true)
            try db.create(index: "idx_cache_timestamp", on: "cached_categorizations", columns: ["timestamp"], ifNotExists: true)
        }
    }

    private func seedDefaultData() async throws {
        guard let dbQueue = dbQueue else { return }

        try await dbQueue.write { db in
            // Seed default categories if none exist
            let categoryCount = try WorkCategory.fetchCount(db)
            if categoryCount == 0 {
                for var category in WorkCategory.defaults {
                    try category.insert(db)
                }
            }

            // Seed default roles if none exist
            let roleCount = try ProjectRole.fetchCount(db)
            if roleCount == 0 {
                for var role in ProjectRole.defaults {
                    try role.insert(db)
                }
            }
        }
    }

    // MARK: - Work Categories CRUD

    func fetchAllCategories() async throws -> [WorkCategory] {
        guard let dbQueue = dbQueue else { return [] }
        return try await dbQueue.read { db in
            try WorkCategory
                .filter(WorkCategory.Columns.isActive == true)
                .order(WorkCategory.Columns.sortOrder)
                .fetchAll(db)
        }
    }

    func fetchCategory(bySlug slug: String) async throws -> WorkCategory? {
        guard let dbQueue = dbQueue else { return nil }
        return try await dbQueue.read { db in
            try WorkCategory
                .filter(WorkCategory.Columns.slug == slug)
                .fetchOne(db)
        }
    }

    func fetchCategory(byId id: Int64) async throws -> WorkCategory? {
        guard let dbQueue = dbQueue else { return nil }
        return try await dbQueue.read { db in
            try WorkCategory.fetchOne(db, key: id)
        }
    }

    func saveCategory(_ category: inout WorkCategory) async throws {
        guard let dbQueue = dbQueue else { return }
        var mutableCategory = category
        try await dbQueue.write { db in
            try mutableCategory.save(db)
        }
        category = mutableCategory
    }

    func deleteCategory(_ category: WorkCategory) async throws {
        guard let dbQueue = dbQueue, let id = category.id else { return }
        _ = try await dbQueue.write { db in
            try WorkCategory.deleteOne(db, key: id)
        }
    }

    // MARK: - Project Roles CRUD

    func fetchAllRoles() async throws -> [ProjectRole] {
        guard let dbQueue = dbQueue else { return [] }
        return try await dbQueue.read { db in
            try ProjectRole
                .filter(ProjectRole.Columns.isActive == true)
                .order(ProjectRole.Columns.sortOrder)
                .fetchAll(db)
        }
    }

    func fetchRole(byId id: Int64) async throws -> ProjectRole? {
        guard let dbQueue = dbQueue else { return nil }
        return try await dbQueue.read { db in
            try ProjectRole.fetchOne(db, key: id)
        }
    }

    func fetchDefaultRole() async throws -> ProjectRole? {
        guard let dbQueue = dbQueue else { return nil }
        return try await dbQueue.read { db in
            try ProjectRole
                .filter(ProjectRole.Columns.isDefault == true)
                .fetchOne(db)
        }
    }

    func saveRole(_ role: inout ProjectRole) async throws {
        guard let dbQueue = dbQueue else { return }
        var mutableRole = role
        try await dbQueue.write { db in
            try mutableRole.save(db)
        }
        role = mutableRole
    }

    func deleteRole(_ role: ProjectRole) async throws {
        guard let dbQueue = dbQueue, let id = role.id else { return }
        _ = try await dbQueue.write { db in
            try ProjectRole.deleteOne(db, key: id)
        }
    }

    // MARK: - Projects CRUD

    func fetchAllProjects() async throws -> [Project] {
        guard let dbQueue = dbQueue else { return [] }
        return try await dbQueue.read { db in
            try Project
                .filter(Project.Columns.isActive == true)
                .order(Project.Columns.lastSeen.desc)
                .fetchAll(db)
        }
    }

    func fetchProjects(byRoleId roleId: Int64) async throws -> [Project] {
        guard let dbQueue = dbQueue else { return [] }
        return try await dbQueue.read { db in
            try Project
                .filter(Project.Columns.roleId == roleId)
                .filter(Project.Columns.isActive == true)
                .order(Project.Columns.lastSeen.desc)
                .fetchAll(db)
        }
    }

    func fetchProject(byId id: Int64) async throws -> Project? {
        guard let dbQueue = dbQueue else { return nil }
        return try await dbQueue.read { db in
            try Project.fetchOne(db, key: id)
        }
    }

    func fetchProject(byName name: String) async throws -> Project? {
        guard let dbQueue = dbQueue else { return nil }
        return try await dbQueue.read { db in
            try Project
                .filter(Project.Columns.name.like(name))
                .fetchOne(db)
        }
    }

    func saveProject(_ project: inout Project) async throws {
        guard let dbQueue = dbQueue else { return }
        var mutableProject = project
        try await dbQueue.write { db in
            try mutableProject.save(db)
        }
        project = mutableProject
    }

    func deleteProject(_ project: Project) async throws {
        guard let dbQueue = dbQueue, let id = project.id else { return }
        _ = try await dbQueue.write { db in
            try Project.deleteOne(db, key: id)
        }
    }

    func updateProjectDuration(_ projectId: Int64, additionalDuration: TimeInterval) async throws {
        guard let dbQueue = dbQueue else { return }
        try await dbQueue.write { db in
            try db.execute(sql: """
                UPDATE projects
                SET totalDuration = totalDuration + ?,
                    lastSeen = ?
                WHERE id = ?
                """, arguments: [additionalDuration, Date(), projectId])
        }
    }

    // MARK: - Activity Sessions CRUD

    func fetchRecentSessions(limit: Int = 50) async throws -> [ActivitySession] {
        guard let dbQueue = dbQueue else { return [] }
        return try await dbQueue.read { db in
            try ActivitySession
                .order(ActivitySession.Columns.startTime.desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    func fetchSessions(from startDate: Date, to endDate: Date) async throws -> [ActivitySession] {
        guard let dbQueue = dbQueue else { return [] }
        return try await dbQueue.read { db in
            try ActivitySession
                .filter(ActivitySession.Columns.startTime >= startDate)
                .filter(ActivitySession.Columns.startTime <= endDate)
                .order(ActivitySession.Columns.startTime.desc)
                .fetchAll(db)
        }
    }

    func fetchActiveSession() async throws -> ActivitySession? {
        guard let dbQueue = dbQueue else { return nil }
        return try await dbQueue.read { db in
            try ActivitySession
                .filter(ActivitySession.Columns.isActive == true)
                .order(ActivitySession.Columns.startTime.desc)
                .fetchOne(db)
        }
    }

    func fetchSession(byId id: Int64) async throws -> ActivitySession? {
        guard let dbQueue = dbQueue else { return nil }
        return try await dbQueue.read { db in
            try ActivitySession.fetchOne(db, key: id)
        }
    }

    func saveSession(_ session: inout ActivitySession) async throws {
        guard let dbQueue = dbQueue else { return }
        var mutableSession = session
        try await dbQueue.write { db in
            try mutableSession.save(db)
        }
        session = mutableSession
    }

    func deleteSession(_ session: ActivitySession) async throws {
        guard let dbQueue = dbQueue, let id = session.id else { return }
        _ = try await dbQueue.write { db in
            try ActivitySession.deleteOne(db, key: id)
        }
    }

    // MARK: - AI Suggestions CRUD

    func fetchPendingSuggestions() async throws -> [AISuggestion] {
        guard let dbQueue = dbQueue else { return [] }
        return try await dbQueue.read { db in
            try AISuggestion
                .filter(AISuggestion.Columns.status == AISuggestion.SuggestionStatus.pending.rawValue)
                .order(AISuggestion.Columns.createdAt.desc)
                .fetchAll(db)
        }
    }

    func fetchSuggestions(forSessionId sessionId: Int64) async throws -> [AISuggestion] {
        guard let dbQueue = dbQueue else { return [] }
        return try await dbQueue.read { db in
            try AISuggestion
                .filter(AISuggestion.Columns.sessionId == sessionId)
                .order(AISuggestion.Columns.createdAt.desc)
                .fetchAll(db)
        }
    }

    func pendingSuggestionsCount() async throws -> Int {
        guard let dbQueue = dbQueue else { return 0 }
        return try await dbQueue.read { db in
            try AISuggestion
                .filter(AISuggestion.Columns.status == AISuggestion.SuggestionStatus.pending.rawValue)
                .fetchCount(db)
        }
    }

    func saveSuggestion(_ suggestion: inout AISuggestion) async throws {
        guard let dbQueue = dbQueue else { return }
        var mutableSuggestion = suggestion
        try await dbQueue.write { db in
            try mutableSuggestion.save(db)
        }
        suggestion = mutableSuggestion
    }

    func acceptSuggestion(_ suggestion: inout AISuggestion) async throws {
        suggestion.accept()
        try await saveSuggestion(&suggestion)
    }

    func rejectSuggestion(_ suggestion: inout AISuggestion) async throws {
        suggestion.reject()
        try await saveSuggestion(&suggestion)
    }

    func modifySuggestion(_ suggestion: inout AISuggestion, newValue: String) async throws {
        suggestion.modify(newValue: newValue)
        try await saveSuggestion(&suggestion)
    }

    // MARK: - Focus Events CRUD

    func saveFocusEvent(_ event: inout FocusEvent) async throws {
        guard let dbQueue = dbQueue else { return }
        var mutableEvent = event
        try await dbQueue.write { db in
            try mutableEvent.save(db)
        }
        event = mutableEvent
    }

    func fetchRecentFocusEvents(limit: Int = 100) async throws -> [FocusEvent] {
        guard let dbQueue = dbQueue else { return [] }
        return try await dbQueue.read { db in
            try FocusEvent
                .order(FocusEvent.Columns.timestamp.desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    func updateFocusEventDuration(_ eventId: Int64, duration: TimeInterval) async throws {
        guard let dbQueue = dbQueue else { return }
        try await dbQueue.write { db in
            try db.execute(sql: "UPDATE focus_events SET duration = ? WHERE id = ?",
                          arguments: [duration, eventId])
        }
    }

    // MARK: - Statistics

    func fetchCategoryStatistics(from startDate: Date, to endDate: Date) async throws -> [(WorkCategory, TimeInterval)] {
        guard let dbQueue = dbQueue else { return [] }
        return try await dbQueue.read { db in
            let sql = """
                SELECT c.*, SUM(s.duration) as totalDuration
                FROM work_categories c
                LEFT JOIN activity_sessions s ON s.workCategoryId = c.id
                    AND s.startTime >= ? AND s.startTime <= ?
                GROUP BY c.id
                ORDER BY totalDuration DESC
                """
            let rows = try Row.fetchAll(db, sql: sql, arguments: [startDate, endDate])
            return try rows.compactMap { row -> (WorkCategory, TimeInterval)? in
                let category = try WorkCategory(row: row)
                let duration = row["totalDuration"] as? TimeInterval ?? 0
                return (category, duration)
            }
        }
    }

    func fetchProjectStatistics(from startDate: Date, to endDate: Date) async throws -> [(Project, TimeInterval)] {
        guard let dbQueue = dbQueue else { return [] }
        return try await dbQueue.read { db in
            let sql = """
                SELECT p.*, SUM(s.duration) as totalDuration
                FROM projects p
                LEFT JOIN activity_sessions s ON s.projectId = p.id
                    AND s.startTime >= ? AND s.startTime <= ?
                WHERE p.isActive = 1
                GROUP BY p.id
                ORDER BY totalDuration DESC
                """
            let rows = try Row.fetchAll(db, sql: sql, arguments: [startDate, endDate])
            return try rows.compactMap { row -> (Project, TimeInterval)? in
                let project = try Project(row: row)
                let duration = row["totalDuration"] as? TimeInterval ?? 0
                return (project, duration)
            }
        }
    }

    func totalDuration(from startDate: Date, to endDate: Date) async throws -> TimeInterval {
        guard let dbQueue = dbQueue else { return 0 }
        return try await dbQueue.read { db in
            let sql = """
                SELECT SUM(duration) FROM activity_sessions
                WHERE startTime >= ? AND startTime <= ?
                """
            return try TimeInterval.fetchOne(db, sql: sql, arguments: [startDate, endDate]) ?? 0
        }
    }

    // MARK: - Insight Feedback CRUD

    func saveInsightFeedback(_ feedback: inout InsightFeedback) async throws {
        guard let dbQueue = dbQueue else { return }
        var mutableFeedback = feedback
        try await dbQueue.write { db in
            try mutableFeedback.save(db)
        }
        feedback = mutableFeedback
    }

    func fetchRecentFeedback(limit: Int = 50) async throws -> [InsightFeedback] {
        guard let dbQueue = dbQueue else { return [] }
        return try await dbQueue.read { db in
            try InsightFeedback
                .order(InsightFeedback.Columns.createdAt.desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    func fetchFeedback(byType type: InsightFeedback.InsightType) async throws -> [InsightFeedback] {
        guard let dbQueue = dbQueue else { return [] }
        return try await dbQueue.read { db in
            try InsightFeedback
                .filter(InsightFeedback.Columns.insightType == type.rawValue)
                .order(InsightFeedback.Columns.createdAt.desc)
                .fetchAll(db)
        }
    }

    func fetchAppliedFeedback() async throws -> [InsightFeedback] {
        guard let dbQueue = dbQueue else { return [] }
        return try await dbQueue.read { db in
            try InsightFeedback
                .filter(InsightFeedback.Columns.feedbackAction == InsightFeedback.FeedbackAction.applied.rawValue)
                .order(InsightFeedback.Columns.appliedAt.desc)
                .fetchAll(db)
        }
    }

    func feedbackCount(byAction action: InsightFeedback.FeedbackAction) async throws -> Int {
        guard let dbQueue = dbQueue else { return 0 }
        return try await dbQueue.read { db in
            try InsightFeedback
                .filter(InsightFeedback.Columns.feedbackAction == action.rawValue)
                .fetchCount(db)
        }
    }

    // MARK: - Bulk Updates for Feedback

    /// Update multiple sessions with a new category
    func bulkUpdateSessionCategory(sessionIds: [Int64], categoryId: Int64) async throws {
        guard let dbQueue = dbQueue, !sessionIds.isEmpty else { return }
        try await dbQueue.write { db in
            let placeholders = sessionIds.map { _ in "?" }.joined(separator: ",")
            try db.execute(
                sql: "UPDATE activity_sessions SET workCategoryId = ?, isAICategorized = 1 WHERE id IN (\(placeholders))",
                arguments: StatementArguments([categoryId] + sessionIds)
            )
        }
    }

    /// Update multiple sessions with a new project
    func bulkUpdateSessionProject(sessionIds: [Int64], projectId: Int64) async throws {
        guard let dbQueue = dbQueue, !sessionIds.isEmpty else { return }
        try await dbQueue.write { db in
            let placeholders = sessionIds.map { _ in "?" }.joined(separator: ",")
            try db.execute(
                sql: "UPDATE activity_sessions SET projectId = ? WHERE id IN (\(placeholders))",
                arguments: StatementArguments([projectId] + sessionIds)
            )
        }
    }

    /// Add pattern to project
    func addPatternToProject(projectId: Int64, pattern: String) async throws {
        guard let dbQueue = dbQueue else { return }
        try await dbQueue.write { db in
            if var project = try Project.fetchOne(db, key: projectId) {
                project.addPattern(pattern)
                try project.update(db)
            }
        }
    }

    /// Update project's default category
    func updateProjectDefaultCategory(projectId: Int64, categoryId: Int64) async throws {
        guard let dbQueue = dbQueue else { return }
        try await dbQueue.write { db in
            try db.execute(
                sql: "UPDATE projects SET defaultCategoryId = ? WHERE id = ?",
                arguments: [categoryId, projectId]
            )
        }
    }

    /// Update project's role
    func updateProjectRole(projectId: Int64, roleId: Int64) async throws {
        guard let dbQueue = dbQueue else { return }
        try await dbQueue.write { db in
            try db.execute(
                sql: "UPDATE projects SET roleId = ? WHERE id = ?",
                arguments: [roleId, projectId]
            )
        }
    }

    // MARK: - Comprehensive Analysis CRUD

    /// Save a comprehensive analysis
    func saveComprehensiveAnalysis(_ analysis: ComprehensiveAnalysis) async throws {
        guard let dbQueue = dbQueue else { return }
        var mutableAnalysis = analysis
        try await dbQueue.write { db in
            try mutableAnalysis.save(db)
        }
    }

    /// Get comprehensive analysis for a specific date and period
    func getComprehensiveAnalysis(for date: Date, period: TimePeriod) -> ComprehensiveAnalysis? {
        guard let dbQueue = dbQueue else { return nil }

        return try? dbQueue.read { db in
            let calendar = Calendar.current
            let startOfDay = calendar.startOfDay(for: date)
            let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

            return try ComprehensiveAnalysis
                .filter(ComprehensiveAnalysis.Columns.date >= startOfDay)
                .filter(ComprehensiveAnalysis.Columns.date < endOfDay)
                .filter(ComprehensiveAnalysis.Columns.period == period.rawValue)
                .order(ComprehensiveAnalysis.Columns.analysisTimestamp.desc)
                .fetchOne(db)
        }
    }

    /// Get recent analyses
    func getRecentAnalyses(limit: Int = 10) async throws -> [ComprehensiveAnalysis] {
        guard let dbQueue = dbQueue else { return [] }
        return try await dbQueue.read { db in
            try ComprehensiveAnalysis
                .order(ComprehensiveAnalysis.Columns.analysisTimestamp.desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    /// Update an existing comprehensive analysis
    func updateComprehensiveAnalysis(_ analysis: ComprehensiveAnalysis) async throws {
        guard let dbQueue = dbQueue else { return }
        var mutableAnalysis = analysis
        try await dbQueue.write { db in
            try mutableAnalysis.update(db)
        }
    }

    /// Delete a comprehensive analysis
    func deleteComprehensiveAnalysis(_ analysis: ComprehensiveAnalysis) async throws {
        guard let dbQueue = dbQueue, let id = analysis.id else { return }
        _ = try await dbQueue.write { db in
            try ComprehensiveAnalysis.deleteOne(db, key: id)
        }
    }

    /// Get feedback for analysis context (convenience wrapper)
    func getRecentFeedback(limit: Int = 10) async throws -> [InsightFeedback] {
        return try await fetchRecentFeedback(limit: limit)
    }

    /// Save feedback (convenience wrapper)
    func saveFeedback(_ feedback: InsightFeedback) async throws {
        guard let dbQueue = dbQueue else { return }
        var mutableFeedback = feedback
        try await dbQueue.write { db in
            try mutableFeedback.save(db)
        }
    }
}
