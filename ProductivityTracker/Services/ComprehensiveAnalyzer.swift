import Foundation
import SwiftUI
import Combine

/// Response structure for comprehensive analysis from Claude
struct ComprehensiveAnalysisResponse: Codable {
    let overview: String
    let workSegments: [WorkSegmentResponse]
    let timelineSegments: [TimelineSegmentResponse]?
    let contextAnalysis: String
    let keyInsights: [String]
    let recommendations: [String]
}

struct WorkSegmentResponse: Codable {
    let name: String
    let description: String
    let duration: TimeInterval
    let focusQuality: String?
    let sessionIds: [Int64]
}

struct TimelineSegmentResponse: Codable {
    let startTime: String
    let endTime: String
    let activityType: String
    let categoryColor: String
    let appName: String?
}

/// ComprehensiveAnalyzer orchestrates Claude-powered analysis of productivity data
@MainActor
final class ComprehensiveAnalyzer: ObservableObject {
    static let shared = ComprehensiveAnalyzer()

    @Published var currentAnalysis: ComprehensiveAnalysis?
    @Published var isAnalyzing = false
    @Published var conversationHistory: [AnalysisExchange] = []
    @Published var lastError: Error?

    private let apiClient: ClaudeAPIClient
    private let storageManager: StorageManager

    init(
        apiClient: ClaudeAPIClient? = nil,
        storageManager: StorageManager? = nil
    ) {
        self.apiClient = apiClient ?? ClaudeAPIClient.shared
        self.storageManager = storageManager ?? StorageManager.shared
    }

    // MARK: - Main Analysis

    /// Analyze productivity data for a given period
    func analyzeData(
        sessions: [ActivitySession],
        period: TimePeriod,
        date: Date = Date()
    ) async throws -> ComprehensiveAnalysis {
        guard !sessions.isEmpty else {
            throw AnalyzerError.noDataAvailable
        }

        isAnalyzing = true
        defer { isAnalyzing = false }

        // Check for cached analysis first
        if let cached = try? storageManager.getComprehensiveAnalysis(for: date, period: period),
           Calendar.current.isDate(cached.analysisTimestamp, inSameDayAs: Date()) {
            currentAnalysis = cached
            conversationHistory = cached.followUpExchanges
            return cached
        }

        // Get relevant feedback for context
        let recentFeedback = try? await storageManager.getRecentFeedback(limit: 10)

        // Generate new analysis
        let response = try await apiClient.generateComprehensiveAnalysis(
            sessions: sessions,
            period: period,
            previousFeedback: recentFeedback
        )

        // Calculate metadata
        let totalTime = sessions.reduce(0) { $0 + $1.duration }
        let sessionCount = sessions.count

        // Convert response to model
        let workSegments = response.workSegments.map { segment in
            WorkSegment(
                name: segment.name,
                description: segment.description,
                duration: segment.duration,
                focusQuality: segment.focusQuality,
                sessionIds: segment.sessionIds
            )
        }

        // Convert timeline segments
        let timelineSegments = (response.timelineSegments ?? []).compactMap { segment -> TimelineSegment? in
            let dateFormatter = ISO8601DateFormatter()
            guard let startTime = dateFormatter.date(from: segment.startTime),
                  let endTime = dateFormatter.date(from: segment.endTime) else {
                return nil
            }

            return TimelineSegment(
                startTime: startTime,
                endTime: endTime,
                activityType: segment.activityType,
                categoryColor: segment.categoryColor,
                appName: segment.appName
            )
        }

        let analysis = ComprehensiveAnalysis(
            date: date,
            period: period,
            overview: response.overview,
            workSegments: workSegments,
            timelineSegments: timelineSegments,
            contextAnalysis: response.contextAnalysis,
            keyInsights: response.keyInsights,
            recommendations: response.recommendations,
            totalTime: totalTime,
            sessionCount: sessionCount,
            analysisTimestamp: Date(),
            followUpExchanges: []
        )

        // Save to database
        try await storageManager.saveComprehensiveAnalysis(analysis)

        currentAnalysis = analysis
        conversationHistory = []
        lastError = nil

        return analysis
    }

    // MARK: - Follow-up Questions

    /// Ask a follow-up question about the analysis
    func askQuestion(
        _ question: String,
        context: ComprehensiveAnalysis,
        sessions: [ActivitySession]
    ) async throws -> String {
        guard var analysis = currentAnalysis else {
            throw AnalyzerError.noActiveAnalysis
        }

        isAnalyzing = true
        defer { isAnalyzing = false }

        // Get answer from Claude
        let answer = try await apiClient.answerFollowUpQuestion(
            question: question,
            analysis: context,
            sessions: sessions,
            previousExchanges: conversationHistory
        )

        // Create exchange record
        let exchange = AnalysisExchange(
            question: question,
            answer: answer,
            timestamp: Date()
        )

        // Update conversation history
        conversationHistory.append(exchange)
        analysis.followUpExchanges.append(exchange)

        // Update stored analysis
        try await storageManager.updateComprehensiveAnalysis(analysis)

        currentAnalysis = analysis
        lastError = nil

        return answer
    }

    // MARK: - Feedback Integration

    /// Provide feedback about the analysis
    func provideFeedback(
        _ feedback: String,
        analysis: ComprehensiveAnalysis
    ) async throws {
        guard !feedback.isEmpty else {
            throw AnalyzerError.emptyFeedback
        }

        isAnalyzing = true
        defer { isAnalyzing = false }

        // Process feedback with Claude to extract actionable items
        let processedFeedback = try await apiClient.processFeedbackForAnalysis(
            feedback: feedback,
            analysis: analysis
        )

        // Save feedback to storage
        try await storageManager.saveFeedback(processedFeedback)

        lastError = nil
    }

    // MARK: - Cache Management

    /// Load cached analysis for a specific date and period
    func loadCachedAnalysis(for date: Date, period: TimePeriod) throws -> ComprehensiveAnalysis? {
        let analysis = try storageManager.getComprehensiveAnalysis(for: date, period: period)
        if let analysis = analysis {
            currentAnalysis = analysis
            conversationHistory = analysis.followUpExchanges
        }
        return analysis
    }

    /// Check if we should auto-analyze (once per day)
    func shouldAutoAnalyze(for date: Date, period: TimePeriod) -> Bool {
        guard let cached = try? storageManager.getComprehensiveAnalysis(for: date, period: period) else {
            return true // No cached analysis exists
        }

        // Auto-analyze if cached analysis is from a different day
        return !Calendar.current.isDate(cached.analysisTimestamp, inSameDayAs: Date())
    }

    /// Clear current analysis
    func clearCurrentAnalysis() {
        currentAnalysis = nil
        conversationHistory = []
    }

    // MARK: - Regeneration

    /// Regenerate analysis (force refresh)
    func regenerateAnalysis(
        sessions: [ActivitySession],
        period: TimePeriod,
        date: Date = Date()
    ) async throws -> ComprehensiveAnalysis {
        // Delete cached analysis if exists
        if let existing = try? storageManager.getComprehensiveAnalysis(for: date, period: period) {
            try? await storageManager.deleteComprehensiveAnalysis(existing)
        }

        // Generate fresh analysis
        return try await analyzeData(sessions: sessions, period: period, date: date)
    }
}

// MARK: - Errors

enum AnalyzerError: LocalizedError {
    case noDataAvailable
    case noActiveAnalysis
    case emptyFeedback
    case analysisGenerationFailed

    var errorDescription: String? {
        switch self {
        case .noDataAvailable:
            return "No productivity data available for the selected period."
        case .noActiveAnalysis:
            return "No active analysis to ask questions about."
        case .emptyFeedback:
            return "Please provide feedback text."
        case .analysisGenerationFailed:
            return "Failed to generate analysis. Please try again."
        }
    }
}
