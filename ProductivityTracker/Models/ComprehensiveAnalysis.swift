import Foundation
import GRDB

/// TimePeriod represents the analysis period
enum TimePeriod: String, Codable {
    case today
    case yesterday
    case last7Days
    case last30Days
    case custom

    var displayName: String {
        switch self {
        case .today: return "Today"
        case .yesterday: return "Yesterday"
        case .last7Days: return "Last 7 Days"
        case .last30Days: return "Last 30 Days"
        case .custom: return "Custom Period"
        }
    }
}

/// WorkSegment represents a Claude-identified work segment
struct WorkSegment: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String              // Claude-decided name
    var description: String        // What this work was about
    var duration: TimeInterval
    var focusQuality: String?     // Claude's assessment
    var sessionIds: [Int64]       // Links back to raw data

    init(
        id: UUID = UUID(),
        name: String,
        description: String,
        duration: TimeInterval,
        focusQuality: String? = nil,
        sessionIds: [Int64] = []
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.duration = duration
        self.focusQuality = focusQuality
        self.sessionIds = sessionIds
    }

    var formattedDuration: String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60

        if hours > 0 {
            return String(format: "%dh %dm", hours, minutes)
        } else {
            return String(format: "%dm", minutes)
        }
    }

    var focusQualityEmoji: String {
        guard let quality = focusQuality?.lowercased() else { return "" }
        switch quality {
        case "excellent": return "🟢"
        case "good": return "🟡"
        case "fragmented", "poor": return "🔴"
        default: return ""
        }
    }
}

/// AnalysisExchange represents a Q&A exchange about the analysis
struct AnalysisExchange: Codable, Identifiable, Hashable {
    var id: UUID
    var question: String
    var answer: String
    var timestamp: Date

    init(
        id: UUID = UUID(),
        question: String,
        answer: String,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.question = question
        self.answer = answer
        self.timestamp = timestamp
    }
}

/// ComprehensiveAnalysis represents a Claude-powered analysis of productivity data
struct ComprehensiveAnalysis: Codable, Identifiable, Hashable {
    var id: Int64?
    var date: Date
    var period: TimePeriod

    // Claude's structured analysis
    var overview: String
    var workSegments: [WorkSegment]  // Claude-defined groups
    var contextAnalysis: String
    var keyInsights: [String]
    var recommendations: [String]

    // Metadata
    var totalTime: TimeInterval
    var sessionCount: Int
    var analysisTimestamp: Date

    // Conversation
    var followUpExchanges: [AnalysisExchange]

    var createdAt: Date
    var updatedAt: Date

    init(
        id: Int64? = nil,
        date: Date = Date(),
        period: TimePeriod = .today,
        overview: String = "",
        workSegments: [WorkSegment] = [],
        contextAnalysis: String = "",
        keyInsights: [String] = [],
        recommendations: [String] = [],
        totalTime: TimeInterval = 0,
        sessionCount: Int = 0,
        analysisTimestamp: Date = Date(),
        followUpExchanges: [AnalysisExchange] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.date = date
        self.period = period
        self.overview = overview
        self.workSegments = workSegments
        self.contextAnalysis = contextAnalysis
        self.keyInsights = keyInsights
        self.recommendations = recommendations
        self.totalTime = totalTime
        self.sessionCount = sessionCount
        self.analysisTimestamp = analysisTimestamp
        self.followUpExchanges = followUpExchanges
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var formattedTotalTime: String {
        let hours = Int(totalTime) / 3600
        let minutes = (Int(totalTime) % 3600) / 60

        if hours > 0 {
            return String(format: "%dh %dm", hours, minutes)
        } else {
            return String(format: "%dm", minutes)
        }
    }

    var hasConversation: Bool {
        !followUpExchanges.isEmpty
    }
}

// MARK: - Database Codable Helpers
extension ComprehensiveAnalysis {
    enum CodingKeys: String, CodingKey {
        case id, date, period
        case overview, workSegmentsJSON, contextAnalysis
        case keyInsightsJSON, recommendationsJSON
        case totalTime, sessionCount, analysisTimestamp
        case followUpExchangesJSON
        case createdAt, updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decodeIfPresent(Int64.self, forKey: .id)
        date = try container.decode(Date.self, forKey: .date)
        period = try container.decode(TimePeriod.self, forKey: .period)
        overview = try container.decode(String.self, forKey: .overview)

        // Decode JSON strings to arrays
        let workSegmentsJSON = try container.decode(String.self, forKey: .workSegmentsJSON)
        workSegments = Self.decodeWorkSegments(workSegmentsJSON)

        contextAnalysis = try container.decode(String.self, forKey: .contextAnalysis)

        let keyInsightsJSON = try container.decode(String.self, forKey: .keyInsightsJSON)
        keyInsights = Self.decodeStringArray(keyInsightsJSON)

        let recommendationsJSON = try container.decode(String.self, forKey: .recommendationsJSON)
        recommendations = Self.decodeStringArray(recommendationsJSON)

        totalTime = try container.decode(TimeInterval.self, forKey: .totalTime)
        sessionCount = try container.decode(Int.self, forKey: .sessionCount)
        analysisTimestamp = try container.decode(Date.self, forKey: .analysisTimestamp)

        let exchangesJSON = try container.decode(String.self, forKey: .followUpExchangesJSON)
        followUpExchanges = Self.decodeExchanges(exchangesJSON)

        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encodeIfPresent(id, forKey: .id)
        try container.encode(date, forKey: .date)
        try container.encode(period, forKey: .period)
        try container.encode(overview, forKey: .overview)

        // Encode arrays to JSON strings
        try container.encode(Self.encodeWorkSegments(workSegments), forKey: .workSegmentsJSON)
        try container.encode(contextAnalysis, forKey: .contextAnalysis)
        try container.encode(Self.encodeStringArray(keyInsights), forKey: .keyInsightsJSON)
        try container.encode(Self.encodeStringArray(recommendations), forKey: .recommendationsJSON)

        try container.encode(totalTime, forKey: .totalTime)
        try container.encode(sessionCount, forKey: .sessionCount)
        try container.encode(analysisTimestamp, forKey: .analysisTimestamp)

        try container.encode(Self.encodeExchanges(followUpExchanges), forKey: .followUpExchangesJSON)

        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }

    // MARK: - JSON Encoding/Decoding Helpers

    private static func encodeStringArray(_ array: [String]) -> String {
        guard let data = try? JSONEncoder().encode(array),
              let string = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return string
    }

    private static func decodeStringArray(_ json: String) -> [String] {
        guard let data = json.data(using: .utf8),
              let array = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return array
    }

    private static func encodeWorkSegments(_ segments: [WorkSegment]) -> String {
        guard let data = try? JSONEncoder().encode(segments),
              let string = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return string
    }

    private static func decodeWorkSegments(_ json: String) -> [WorkSegment] {
        guard let data = json.data(using: .utf8),
              let array = try? JSONDecoder().decode([WorkSegment].self, from: data) else {
            return []
        }
        return array
    }

    private static func encodeExchanges(_ exchanges: [AnalysisExchange]) -> String {
        guard let data = try? JSONEncoder().encode(exchanges),
              let string = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return string
    }

    private static func decodeExchanges(_ json: String) -> [AnalysisExchange] {
        guard let data = json.data(using: .utf8),
              let array = try? JSONDecoder().decode([AnalysisExchange].self, from: data) else {
            return []
        }
        return array
    }
}

// MARK: - GRDB Support
extension ComprehensiveAnalysis: FetchableRecord, MutablePersistableRecord {
    static var databaseTableName: String { "comprehensive_analyses" }

    enum Columns: String, ColumnExpression {
        case id, date, period
        case overview, workSegmentsJSON, contextAnalysis
        case keyInsightsJSON, recommendationsJSON
        case totalTime, sessionCount, analysisTimestamp
        case followUpExchangesJSON
        case createdAt, updatedAt
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
