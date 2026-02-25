import Foundation
import AppKit
import Combine

/// Categorization errors
enum CategorizationError: LocalizedError {
    case noCategorizationAvailable
    case offlineModeNoCache

    var errorDescription: String? {
        switch self {
        case .noCategorizationAvailable:
            return "Unable to categorize activity. No online connection or cached patterns available."
        case .offlineModeNoCache:
            return "Offline mode: No cached patterns found for this app."
        }
    }
}

/// AICategorizer provides AI-first categorization for captured screenshots.
/// Called immediately at capture time to extract project/category/role information.
@MainActor
final class AICategorizer: ObservableObject {
    static let shared = AICategorizer()

    private let claudeClient = ClaudeAPIClient.shared
    private let storageManager = StorageManager.shared
    private let cacheManager = CacheManager.shared

    /// Confidence threshold below which suggestions are queued for user review
    private let confidenceThreshold: Double = 0.7

    @Published var isProcessing = false
    @Published var lastCategorization: AICategorization?
    @Published var lastError: Error?
    @Published var isOfflineMode = false

    private init() {}

    // MARK: - Main Categorization Entry Point

    /// Categorize a screenshot and update the session with AI results.
    /// Low-confidence results are queued as suggestions for user review.
    /// Falls back to cached patterns when offline.
    func categorize(
        screenshot: NSImage,
        session: inout ActivitySession
    ) async throws {
        isProcessing = true
        defer { isProcessing = false }

        // Fetch context data
        let roles = try await storageManager.fetchAllRoles()
        let categories = try await storageManager.fetchAllCategories()
        let existingProjects = try await storageManager.fetchAllProjects()

        // Try online categorization first
        var categorization: AICategorization?
        var usedOfflineMode = false

        do {
            // Call Claude API for categorization
            categorization = try await claudeClient.generateRoleAwareScreenshotSummary(
                screenshot: screenshot,
                appName: session.appName,
                windowTitle: session.windowTitle,
                availableRoles: roles,
                availableCategories: categories,
                existingProjects: existingProjects
            )
            isOfflineMode = false
        } catch {
            // API failed - try offline mode
            print("⚠️ API categorization failed, falling back to cache: \(error.localizedDescription)")
            categorization = try await offlineCategorization(
                appName: session.appName,
                windowTitle: session.windowTitle
            )
            usedOfflineMode = true
            isOfflineMode = true
            lastError = error
        }

        guard let categorization = categorization else {
            throw CategorizationError.noCategorizationAvailable
        }

        lastCategorization = categorization

        // Cache successful online categorizations for future offline use
        if !usedOfflineMode {
            try? await cacheManager.cacheCategorization(
                appName: session.appName ?? "Unknown",
                windowTitle: session.windowTitle,
                projectName: categorization.projectName,
                projectRole: categorization.projectRole,
                workCategory: categorization.workCategory,
                patterns: categorization.suggestedPatterns,
                confidence: categorization.confidence
            )
        }

        // Process the categorization result
        try await applyCategorization(categorization, to: &session, existingProjects: existingProjects)
    }

    /// Offline categorization using cached patterns
    private func offlineCategorization(
        appName: String?,
        windowTitle: String?
    ) async throws -> AICategorization? {
        guard let appName = appName else { return nil }

        // Look for cached categorization
        guard let cached = try await cacheManager.findMatchingCategorization(
            appName: appName,
            windowTitle: windowTitle
        ) else {
            return nil
        }

        // Increment use count for this cache entry
        if let id = cached.id {
            try? await cacheManager.incrementUseCount(for: id)
        }

        // Convert cached entry to AICategorization
        return AICategorization(
            projectName: cached.projectName,
            projectRole: cached.projectRole,
            workCategory: cached.workCategory,
            confidence: cached.confidence * 0.8, // Reduce confidence for cached results
            reasoning: "Categorized using cached pattern (offline mode)",
            suggestedPatterns: cached.patterns,
            keyInsights: ["Offline categorization based on previous activity"],
            summary: "Working on \(cached.projectName)"
        )
    }

    // MARK: - Apply Categorization

    private func applyCategorization(
        _ categorization: AICategorization,
        to session: inout ActivitySession,
        existingProjects: [Project]
    ) async throws {
        // Find or create the work category
        let category = try await storageManager.fetchCategory(bySlug: categorization.workCategory)
        let categoryId = category?.id

        // Find or create the project
        let projectId = try await findOrCreateProject(
            name: categorization.projectName,
            roleName: categorization.projectRole,
            patterns: categorization.suggestedPatterns,
            existingProjects: existingProjects
        )

        // Update the session
        session.workCategoryId = categoryId
        session.projectId = projectId
        session.aiConfidence = categorization.confidence
        session.isAICategorized = true
        session.summary = categorization.summary
        session.setKeyInsights(categorization.keyInsights ?? [])

        // Save updated session
        try await storageManager.saveSession(&session)

        // If confidence is low, queue suggestions for review
        if categorization.confidence < confidenceThreshold {
            try await queueSuggestionsForReview(categorization, sessionId: session.id!)
        }

        // Update project statistics
        if let projectId = projectId {
            try await storageManager.updateProjectDuration(projectId, additionalDuration: session.duration)
        }
    }

    // MARK: - Project Management

    private func findOrCreateProject(
        name: String,
        roleName: String,
        patterns: [String],
        existingProjects: [Project]
    ) async throws -> Int64? {
        // First, try to match an existing project by name
        if let existing = existingProjects.first(where: {
            $0.name.lowercased() == name.lowercased()
        }) {
            // Update patterns if we have new ones
            if !patterns.isEmpty {
                var updated = existing
                for pattern in patterns {
                    updated.addPattern(pattern)
                }
                updated.lastSeen = Date()
                try await storageManager.saveProject(&updated)
            }
            return existing.id
        }

        // Try to match by patterns
        for project in existingProjects {
            if project.matches(projectName: name, appName: nil, windowTitle: nil) {
                var updated = project
                updated.lastSeen = Date()
                try await storageManager.saveProject(&updated)
                return project.id
            }
        }

        // Create a new project
        let roles = try await storageManager.fetchAllRoles()
        let roleId = roles.first(where: { $0.name.lowercased() == roleName.lowercased() })?.id

        var newProject = Project(
            name: name,
            roleId: roleId,
            patterns: patterns,
            isAISuggested: true,
            isUserConfirmed: false,
            confidence: 0.8,
            lastSeen: Date()
        )

        try await storageManager.saveProject(&newProject)
        return newProject.id
    }

    // MARK: - Suggestion Queue

    private func queueSuggestionsForReview(
        _ categorization: AICategorization,
        sessionId: Int64
    ) async throws {
        // Queue project suggestion
        var projectSuggestion = AISuggestion(
            sessionId: sessionId,
            suggestionType: .project,
            suggestedValue: categorization.projectName,
            confidence: categorization.confidence,
            reasoning: categorization.reasoning,
            context: [
                "projectRole": categorization.projectRole,
                "patterns": categorization.suggestedPatterns.joined(separator: ", ")
            ]
        )
        try await storageManager.saveSuggestion(&projectSuggestion)

        // Queue category suggestion
        var categorySuggestion = AISuggestion(
            sessionId: sessionId,
            suggestionType: .category,
            suggestedValue: categorization.workCategory,
            confidence: categorization.confidence,
            reasoning: categorization.reasoning,
            context: [
                "summary": categorization.summary ?? ""
            ]
        )
        try await storageManager.saveSuggestion(&categorySuggestion)

        // Queue role suggestion
        var roleSuggestion = AISuggestion(
            sessionId: sessionId,
            suggestionType: .role,
            suggestedValue: categorization.projectRole,
            confidence: categorization.confidence,
            reasoning: categorization.reasoning
        )
        try await storageManager.saveSuggestion(&roleSuggestion)
    }

    // MARK: - Learning from User Corrections

    /// Apply a user correction and update learning patterns
    func applyUserCorrection(
        sessionId: Int64,
        correctedProjectId: Int64?,
        correctedCategoryId: Int64?,
        correctedRoleId: Int64?
    ) async throws {
        // Fetch the session
        guard var session = try await storageManager.fetchSession(byId: sessionId) else {
            return
        }

        // Apply corrections
        if let projectId = correctedProjectId {
            session.projectId = projectId
        }
        if let categoryId = correctedCategoryId {
            session.workCategoryId = categoryId
        }

        session.isAICategorized = true  // Still AI-assisted, but corrected
        try await storageManager.saveSession(&session)

        // Update project patterns with learned context
        if let projectId = correctedProjectId,
           var project = try await storageManager.fetchProject(byId: projectId) {
            // Add window title as a pattern if it's specific enough
            if let windowTitle = session.windowTitle,
               windowTitle.count > 5,
               !project.patternsArray.contains(windowTitle.lowercased()) {
                project.addPattern(windowTitle.lowercased())
            }

            // Update role if corrected
            if let roleId = correctedRoleId {
                project.roleId = roleId
            }

            project.isUserConfirmed = true
            project.confidence = 1.0
            try await storageManager.saveProject(&project)
        }
    }

    // MARK: - Batch Processing

    /// Re-categorize sessions that don't have AI categorization
    func categorizeUncategorizedSessions() async throws {
        // This would be called for batch processing of historical data
        // Implementation would iterate through sessions and call categorize()
    }

    /// Recalculate category/project assignments based on updated patterns
    func recalculateAssignments() async throws {
        let projects = try await storageManager.fetchAllProjects()
        let sessions = try await storageManager.fetchRecentSessions(limit: 500)

        for var session in sessions where !session.isAICategorized {
            // Try to match against known projects
            for project in projects {
                if project.matches(
                    projectName: session.projectName,
                    appName: session.appName,
                    windowTitle: session.windowTitle
                ) {
                    session.projectId = project.id
                    session.workCategoryId = project.defaultCategoryId
                    try await storageManager.saveSession(&session)
                    break
                }
            }
        }
    }
}

// MARK: - Categorization Stats

extension AICategorizer {
    struct CategorizationStats {
        let totalSessions: Int
        let categorizedSessions: Int
        let pendingSuggestions: Int
        let averageConfidence: Double
    }

    func getStats() async throws -> CategorizationStats {
        let sessions = try await storageManager.fetchRecentSessions(limit: 1000)
        let categorized = sessions.filter { $0.isAICategorized }
        let pending = try await storageManager.pendingSuggestionsCount()

        let avgConfidence = categorized.isEmpty ? 0.0 :
            categorized.compactMap { $0.aiConfidence }.reduce(0, +) / Double(categorized.count)

        return CategorizationStats(
            totalSessions: sessions.count,
            categorizedSessions: categorized.count,
            pendingSuggestions: pending,
            averageConfidence: avgConfidence
        )
    }
}
