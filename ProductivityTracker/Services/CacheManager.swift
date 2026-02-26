import Foundation
import GRDB
import Combine

/// CachedCategorization stores a recent AI categorization for offline use
struct CachedCategorization: Codable, Identifiable {
    var id: Int64?
    var appName: String
    var windowTitle: String?
    var projectName: String
    var projectRole: String
    var workCategory: String
    var patterns: [String]  // Detection patterns from this categorization
    var confidence: Double
    var timestamp: Date
    var useCount: Int  // How many times this pattern has been reused

    init(
        id: Int64? = nil,
        appName: String,
        windowTitle: String? = nil,
        projectName: String,
        projectRole: String,
        workCategory: String,
        patterns: [String] = [],
        confidence: Double = 1.0,
        timestamp: Date = Date(),
        useCount: Int = 0
    ) {
        self.id = id
        self.appName = appName
        self.windowTitle = windowTitle
        self.projectName = projectName
        self.projectRole = projectRole
        self.workCategory = workCategory
        self.patterns = patterns
        self.confidence = confidence
        self.timestamp = timestamp
        self.useCount = useCount
    }
}

// MARK: - GRDB Support
extension CachedCategorization: FetchableRecord, MutablePersistableRecord {
    static var databaseTableName: String { "cached_categorizations" }

    enum Columns: String, ColumnExpression {
        case id, appName, windowTitle
        case projectName, projectRole, workCategory
        case patternsJSON, confidence, timestamp, useCount
    }

    enum CodingKeys: String, CodingKey {
        case id, appName, windowTitle
        case projectName, projectRole, workCategory
        case patternsJSON, confidence, timestamp, useCount
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(Int64.self, forKey: .id)
        appName = try container.decode(String.self, forKey: .appName)
        windowTitle = try container.decodeIfPresent(String.self, forKey: .windowTitle)
        projectName = try container.decode(String.self, forKey: .projectName)
        projectRole = try container.decode(String.self, forKey: .projectRole)
        workCategory = try container.decode(String.self, forKey: .workCategory)

        let patternsJSON = try container.decode(String.self, forKey: .patternsJSON)
        patterns = (try? JSONDecoder().decode([String].self, from: Data(patternsJSON.utf8))) ?? []

        confidence = try container.decode(Double.self, forKey: .confidence)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        useCount = try container.decode(Int.self, forKey: .useCount)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(id, forKey: .id)
        try container.encode(appName, forKey: .appName)
        try container.encodeIfPresent(windowTitle, forKey: .windowTitle)
        try container.encode(projectName, forKey: .projectName)
        try container.encode(projectRole, forKey: .projectRole)
        try container.encode(workCategory, forKey: .workCategory)

        let patternsData = try JSONEncoder().encode(patterns)
        let patternsJSON = String(data: patternsData, encoding: .utf8) ?? "[]"
        try container.encode(patternsJSON, forKey: .patternsJSON)

        try container.encode(confidence, forKey: .confidence)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(useCount, forKey: .useCount)
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

/// CacheManager handles local caching of categorizations for offline tracking
@MainActor
final class CacheManager: ObservableObject {
    static let shared = CacheManager()

    @Published var isOfflineMode = false
    @Published var cacheSize: Int = 0

    private var dbQueue: DatabaseQueue?

    // Cache retention period (keep patterns for 30 days)
    private let retentionPeriod: TimeInterval = 30 * 24 * 60 * 60

    // Maximum cache size (keep most recent 1000 entries)
    private let maxCacheSize = 1000

    private init() {
        Task {
            await initialize()
        }
    }

    // MARK: - Initialization

    func initialize() async {
        do {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let appFolder = appSupport.appendingPathComponent("ProductivityTracker", isDirectory: true)
            let databasePath = appFolder.appendingPathComponent("productivity.sqlite")

            var config = Configuration()
            config.foreignKeysEnabled = true
            dbQueue = try DatabaseQueue(path: databasePath.path, configuration: config)

            try await createCacheTable()
            cacheSize = try await getCacheSize()
        } catch {
            print("❌ CacheManager initialization error: \(error)")
        }
    }

    private func createCacheTable() async throws {
        guard let db = dbQueue else { return }

        try await db.write { db in
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

            // Create indexes for fast pattern matching
            try db.create(index: "idx_cache_app", on: "cached_categorizations", columns: ["appName"], ifNotExists: true)
            try db.create(index: "idx_cache_timestamp", on: "cached_categorizations", columns: ["timestamp"], ifNotExists: true)
        }
    }

    // MARK: - Cache Operations

    /// Cache a successful AI categorization for offline use
    func cacheCategorization(
        appName: String,
        windowTitle: String?,
        projectName: String,
        projectRole: String,
        workCategory: String,
        patterns: [String],
        confidence: Double
    ) async throws {
        guard let db = dbQueue else { return }

        var cached = CachedCategorization(
            appName: appName,
            windowTitle: windowTitle,
            projectName: projectName,
            projectRole: projectRole,
            workCategory: workCategory,
            patterns: patterns,
            confidence: confidence
        )

        try await db.write { db in
            try cached.insert(db)
        }

        cacheSize = try await getCacheSize()

        // Clean up old entries if cache is too large
        if cacheSize > maxCacheSize {
            try await pruneCache()
        }
    }

    /// Find a matching cached categorization for offline use
    func findMatchingCategorization(
        appName: String,
        windowTitle: String?
    ) async throws -> CachedCategorization? {
        guard let db = dbQueue else { return nil }

        return try await db.read { db in
            // First try exact match on app + window title
            if let windowTitle = windowTitle, !windowTitle.isEmpty {
                if let exact = try CachedCategorization
                    .filter(Column("appName") == appName)
                    .filter(Column("windowTitle") == windowTitle)
                    .order(Column("useCount").desc, Column("timestamp").desc)
                    .fetchOne(db) {
                    return exact
                }
            }

            // Try pattern matching on window title
            if let windowTitle = windowTitle {
                let candidates = try CachedCategorization
                    .filter(Column("appName") == appName)
                    .order(Column("useCount").desc, Column("timestamp").desc)
                    .fetchAll(db)

                for candidate in candidates {
                    // Check if any of the cached patterns match the window title
                    for pattern in candidate.patterns where !pattern.isEmpty {
                        if windowTitle.localizedCaseInsensitiveContains(pattern) {
                            return candidate
                        }
                    }
                }
            }

            // Fallback: most recent categorization for this app
            return try CachedCategorization
                .filter(Column("appName") == appName)
                .order(Column("useCount").desc, Column("timestamp").desc)
                .fetchOne(db)
        }
    }

    /// Increment use count for a cached entry
    func incrementUseCount(for id: Int64) async throws {
        guard let db = dbQueue else { return }

        try await db.write { db in
            try db.execute(sql: """
                UPDATE cached_categorizations
                SET useCount = useCount + 1
                WHERE id = ?
                """, arguments: [id])
        }
    }

    // MARK: - Cache Maintenance

    /// Get current cache size
    func getCacheSize() async throws -> Int {
        guard let db = dbQueue else { return 0 }

        return try await db.read { db in
            try CachedCategorization.fetchCount(db)
        }
    }

    /// Remove old entries beyond retention period
    func pruneCache() async throws {
        guard let db = dbQueue else { return }

        let cutoffDate = Date().addingTimeInterval(-retentionPeriod)

        try await db.write { db in
            // Delete old entries
            try db.execute(sql: """
                DELETE FROM cached_categorizations
                WHERE timestamp < ?
                """, arguments: [cutoffDate])

            // If still too large, keep only the most recent and most used
            let count = try CachedCategorization.fetchCount(db)
            if count > self.maxCacheSize {
                let keepCount = Int(Double(self.maxCacheSize) * 0.8) // Keep 80% of max

                try db.execute(sql: """
                    DELETE FROM cached_categorizations
                    WHERE id NOT IN (
                        SELECT id FROM cached_categorizations
                        ORDER BY useCount DESC, timestamp DESC
                        LIMIT ?
                    )
                    """, arguments: [keepCount])
            }
        }

        cacheSize = try await getCacheSize()
    }

    /// Clear all cached categorizations
    func clearCache() async throws {
        guard let db = dbQueue else { return }

        try await db.write { db in
            try db.execute(sql: "DELETE FROM cached_categorizations")
        }

        cacheSize = 0
    }

    // MARK: - Offline Mode Detection

    /// Check if network is available
    func checkNetworkAvailability() async -> Bool {
        // Simple check: try to resolve api.anthropic.com
        guard let url = URL(string: "https://api.anthropic.com") else { return false }

        do {
            let (_, response) = try await URLSession.shared.data(from: url)
            if let httpResponse = response as? HTTPURLResponse {
                isOfflineMode = httpResponse.statusCode >= 500 // Treat server errors as offline
                return httpResponse.statusCode < 500
            }
            isOfflineMode = false
            return true
        } catch {
            isOfflineMode = true
            return false
        }
    }

    /// Get cache statistics for display
    func getCacheStats() async throws -> CacheStats {
        guard let db = dbQueue else {
            return CacheStats(totalEntries: 0, uniqueApps: 0, avgConfidence: 0, oldestEntry: nil, newestEntry: nil)
        }

        return try await db.read { db in
            let total = try CachedCategorization.fetchCount(db)
            let uniqueApps = try Int.fetchOne(db, sql: "SELECT COUNT(DISTINCT appName) FROM cached_categorizations") ?? 0
            let avgConfidence = try Double.fetchOne(db, sql: "SELECT AVG(confidence) FROM cached_categorizations") ?? 0
            let oldest = try Date.fetchOne(db, sql: "SELECT MIN(timestamp) FROM cached_categorizations")
            let newest = try Date.fetchOne(db, sql: "SELECT MAX(timestamp) FROM cached_categorizations")

            return CacheStats(
                totalEntries: total,
                uniqueApps: uniqueApps,
                avgConfidence: avgConfidence,
                oldestEntry: oldest,
                newestEntry: newest
            )
        }
    }
}

struct CacheStats {
    let totalEntries: Int
    let uniqueApps: Int
    let avgConfidence: Double
    let oldestEntry: Date?
    let newestEntry: Date?
}
