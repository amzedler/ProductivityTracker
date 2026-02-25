import Foundation

/// InsightFeedbackService analyzes sessions and generates actionable insights
/// that users can apply to improve categorization over time.
@MainActor
final class InsightFeedbackService {
    private let storage: StorageManager
    private let claudeAPI: ClaudeAPIClient

    init(storage: StorageManager? = nil, claudeAPI: ClaudeAPIClient? = nil) {
        self.storage = storage ?? StorageManager.shared
        self.claudeAPI = claudeAPI ?? ClaudeAPIClient.shared
    }

    // MARK: - Insight Generation

    /// Analyze recent sessions and generate actionable insights
    func generateInsights(forDays days: Int = 7) async throws -> InsightAnalysisResult {
        let startDate = Calendar.current.date(byAdding: .day, value: -days, to: Date())!
        let sessions = try await storage.fetchSessions(from: startDate, to: Date())

        guard !sessions.isEmpty else {
            return .empty
        }

        var insights: [ActionableInsight] = []

        // Generate different types of insights
        async let categoryInsights = generateCategoryInsights(sessions: sessions)
        async let projectInsights = generateProjectInsights(sessions: sessions)
        async let patternInsights = generatePatternInsights(sessions: sessions)
        async let roleInsights = generateRoleInsights(sessions: sessions)

        let allInsights = await [categoryInsights, projectInsights, patternInsights, roleInsights]
        insights = allInsights.flatMap { $0 }

        // Sort by confidence (highest first)
        insights.sort { $0.confidence > $1.confidence }

        let coverage = Double(sessions.filter { $0.projectId != nil }.count) / Double(sessions.count)

        return InsightAnalysisResult(
            insights: insights,
            summary: generateSummary(insights: insights, sessions: sessions),
            totalSessionsAnalyzed: sessions.count,
            coveragePercentage: coverage,
            generatedAt: Date()
        )
    }

    // MARK: - Category Insights

    private func generateCategoryInsights(sessions: [ActivitySession]) async -> [ActionableInsight] {
        var insights: [ActionableInsight] = []
        let categories = try? await storage.fetchAllCategories()

        // Find sessions with mismatched categories
        let uncategorizedSessions = sessions.filter { $0.workCategoryId == nil }
        if !uncategorizedSessions.isEmpty {
            // Group by app name to find patterns
            let appGroups = Dictionary(grouping: uncategorizedSessions) { $0.appName ?? "Unknown" }

            for (appName, appSessions) in appGroups where appSessions.count >= 3 {
                // Suggest category based on common patterns
                let suggestedCategory = inferCategoryForApp(appName: appName, sessions: appSessions)

                if let category = suggestedCategory, let categories = categories {
                    let matchingCategory = categories.first { $0.slug == category }

                    insights.append(ActionableInsight(
                        type: .categorySuggestion,
                        title: "Categorize \(appName) sessions",
                        description: "\(appSessions.count) sessions from \(appName) are uncategorized. They appear to be \(matchingCategory?.name ?? category) work.",
                        confidence: min(0.9, 0.5 + Double(appSessions.count) * 0.05),
                        suggestedActions: [
                            ActionableInsight.SuggestedAction(
                                label: "Apply '\(matchingCategory?.name ?? category)'",
                                description: "Set category for all \(appSessions.count) sessions",
                                targetType: .category,
                                targetId: matchingCategory?.id,
                                targetName: matchingCategory?.name,
                                changes: [
                                    "action": "bulk_categorize",
                                    "sessionIds": appSessions.compactMap { $0.id },
                                    "categorySlug": category
                                ],
                                impact: .medium
                            )
                        ],
                        relatedSessions: appSessions.compactMap { $0.id },
                        metadata: ["appName": appName, "suggestedCategory": category]
                    ))
                }
            }
        }

        return insights
    }

    // MARK: - Project Insights

    private func generateProjectInsights(sessions: [ActivitySession]) async -> [ActionableInsight] {
        var insights: [ActionableInsight] = []
        let projects = try? await storage.fetchAllProjects()

        // Find sessions without projects
        let unassignedSessions = sessions.filter { $0.projectId == nil && $0.projectName != nil }

        // Group by extracted project name
        let projectGroups = Dictionary(grouping: unassignedSessions) { $0.projectName ?? "" }

        for (projectName, projectSessions) in projectGroups where !projectName.isEmpty && projectSessions.count >= 2 {
            // Check if a project with similar name exists
            let matchingProject = projects?.first {
                $0.name.lowercased().contains(projectName.lowercased()) ||
                projectName.lowercased().contains($0.name.lowercased())
            }

            if let project = matchingProject {
                // Suggest linking sessions to existing project
                insights.append(ActionableInsight(
                    type: .projectSuggestion,
                    title: "Link sessions to '\(project.name)'",
                    description: "\(projectSessions.count) sessions reference '\(projectName)' which may belong to the '\(project.name)' project.",
                    confidence: 0.75,
                    suggestedActions: [
                        ActionableInsight.SuggestedAction(
                            label: "Link to '\(project.name)'",
                            description: "Assign all \(projectSessions.count) sessions to this project",
                            targetType: .project,
                            targetId: project.id,
                            targetName: project.name,
                            changes: [
                                "action": "bulk_assign_project",
                                "sessionIds": projectSessions.compactMap { $0.id },
                                "projectId": project.id as Any
                            ],
                            impact: .low
                        ),
                        ActionableInsight.SuggestedAction(
                            label: "Add '\(projectName)' as pattern",
                            description: "Add this name as a detection pattern for '\(project.name)'",
                            targetType: .project,
                            targetId: project.id,
                            targetName: project.name,
                            changes: [
                                "action": "add_pattern",
                                "projectId": project.id as Any,
                                "pattern": projectName
                            ],
                            impact: .low
                        )
                    ],
                    relatedSessions: projectSessions.compactMap { $0.id },
                    metadata: ["extractedName": projectName, "matchedProject": project.name]
                ))
            } else {
                // Suggest creating a new project
                insights.append(ActionableInsight(
                    type: .projectSuggestion,
                    title: "Create project '\(projectName)'",
                    description: "\(projectSessions.count) sessions reference '\(projectName)' but no matching project exists.",
                    confidence: 0.65,
                    suggestedActions: [
                        ActionableInsight.SuggestedAction(
                            label: "Create Project",
                            description: "Create '\(projectName)' and assign these sessions",
                            targetType: .project,
                            targetId: nil,
                            targetName: projectName,
                            changes: [
                                "action": "create_project",
                                "projectName": projectName,
                                "sessionIds": projectSessions.compactMap { $0.id }
                            ],
                            impact: .medium
                        )
                    ],
                    relatedSessions: projectSessions.compactMap { $0.id },
                    metadata: ["projectName": projectName]
                ))
            }
        }

        return insights
    }

    // MARK: - Pattern Insights

    private func generatePatternInsights(sessions: [ActivitySession]) async -> [ActionableInsight] {
        var insights: [ActionableInsight] = []
        let projects = try? await storage.fetchAllProjects()

        guard let projects = projects else { return [] }

        // Analyze window titles for consistent patterns
        let titlesWithProjects = sessions.filter { $0.projectId != nil && $0.windowTitle != nil }
        let projectTitles = Dictionary(grouping: titlesWithProjects) { $0.projectId! }

        for (projectId, projectSessions) in projectTitles {
            guard let project = projects.first(where: { $0.id == projectId }) else { continue }

            // Extract common patterns from window titles
            let titles = projectSessions.compactMap { $0.windowTitle }
            let patterns = extractCommonPatterns(from: titles)

            // Filter out patterns that are already in the project
            let existingPatterns = project.patternsArray
            let newPatterns = patterns.filter { pattern in
                !existingPatterns.contains { existing in
                    existing.lowercased() == pattern.lowercased()
                }
            }

            for pattern in newPatterns.prefix(2) {
                insights.append(ActionableInsight(
                    type: .workPattern,
                    title: "Add pattern to '\(project.name)'",
                    description: "The pattern '\(pattern)' appears frequently in \(project.name) sessions and could improve auto-detection.",
                    confidence: 0.7,
                    suggestedActions: [
                        ActionableInsight.SuggestedAction(
                            label: "Add Pattern",
                            description: "Add '\(pattern)' to \(project.name)'s detection patterns",
                            targetType: .project,
                            targetId: project.id,
                            targetName: project.name,
                            changes: [
                                "action": "add_pattern",
                                "projectId": project.id as Any,
                                "pattern": pattern
                            ],
                            impact: .low
                        )
                    ],
                    relatedSessions: projectSessions.prefix(5).compactMap { $0.id },
                    metadata: ["pattern": pattern, "projectName": project.name]
                ))
            }
        }

        return insights
    }

    // MARK: - Role Insights

    private func generateRoleInsights(sessions: [ActivitySession]) async -> [ActionableInsight] {
        var insights: [ActionableInsight] = []
        let projects = try? await storage.fetchAllProjects()
        let roles = try? await storage.fetchAllRoles()

        guard let projects = projects, let roles = roles else { return [] }

        // Find projects that might be miscategorized by role
        for project in projects where project.roleId != nil {
            guard let currentRole = roles.first(where: { $0.id == project.roleId }) else { continue }

            // Get sessions for this project
            let projectSessions = sessions.filter { $0.projectId == project.id }
            guard projectSessions.count >= 5 else { continue }

            // Analyze session content to infer role
            let inferredRole = inferRoleFromSessions(projectSessions, availableRoles: roles)

            if let inferred = inferredRole, inferred.id != currentRole.id {
                insights.append(ActionableInsight(
                    type: .roleSuggestion,
                    title: "Review role for '\(project.name)'",
                    description: "Based on recent activity, '\(project.name)' might belong to '\(inferred.name)' instead of '\(currentRole.name)'.",
                    confidence: 0.6,
                    suggestedActions: [
                        ActionableInsight.SuggestedAction(
                            label: "Change to '\(inferred.name)'",
                            description: "Update project role",
                            targetType: .role,
                            targetId: inferred.id,
                            targetName: inferred.name,
                            changes: [
                                "action": "change_role",
                                "projectId": project.id as Any,
                                "newRoleId": inferred.id as Any
                            ],
                            impact: .medium
                        ),
                        ActionableInsight.SuggestedAction(
                            label: "Keep '\(currentRole.name)'",
                            description: "Dismiss this suggestion",
                            targetType: .role,
                            targetId: currentRole.id,
                            targetName: currentRole.name,
                            changes: [
                                "action": "dismiss"
                            ],
                            impact: .low
                        )
                    ],
                    relatedSessions: projectSessions.prefix(5).compactMap { $0.id },
                    metadata: ["currentRole": currentRole.name, "suggestedRole": inferred.name]
                ))
            }
        }

        return insights
    }

    // MARK: - Apply Feedback

    /// Apply a suggested action from an insight
    func applyAction(_ action: ActionableInsight.SuggestedAction, from insight: ActionableInsight) async throws {
        let changes = action.changes
        guard let actionType = changes["action"] as? String else {
            throw InsightError.invalidAction
        }

        switch actionType {
        case "bulk_categorize":
            try await applyBulkCategorize(changes: changes)

        case "bulk_assign_project":
            try await applyBulkAssignProject(changes: changes)

        case "add_pattern":
            try await applyAddPattern(changes: changes)

        case "create_project":
            try await applyCreateProject(changes: changes)

        case "change_role":
            try await applyChangeRole(changes: changes)

        case "change_category":
            try await applyChangeCategory(changes: changes)

        case "dismiss":
            // Just record the dismissal, no actual changes
            break

        default:
            throw InsightError.unknownAction(actionType)
        }

        // Record the feedback
        var feedback = InsightFeedback(
            insightType: insight.type,
            insightContent: insight.description,
            feedbackAction: actionType == "dismiss" ? .dismissed : .applied,
            targetType: action.targetType,
            targetId: action.targetId,
            targetName: action.targetName,
            appliedChanges: changes,
            confidence: insight.confidence,
            appliedAt: Date()
        )

        try await storage.saveInsightFeedback(&feedback)
    }

    /// Record a modification to an insight's suggested action
    func recordModifiedAction(
        insight: ActionableInsight,
        originalAction: ActionableInsight.SuggestedAction,
        modifiedChanges: [String: Any]
    ) async throws {
        var feedback = InsightFeedback(
            insightType: insight.type,
            insightContent: insight.description,
            feedbackAction: .modified,
            targetType: originalAction.targetType,
            targetId: originalAction.targetId,
            targetName: originalAction.targetName,
            appliedChanges: modifiedChanges,
            confidence: insight.confidence,
            appliedAt: Date()
        )

        try await storage.saveInsightFeedback(&feedback)
    }

    /// Defer an insight for later review
    func deferInsight(_ insight: ActionableInsight) async throws {
        var feedback = InsightFeedback(
            insightType: insight.type,
            insightContent: insight.description,
            feedbackAction: .deferred,
            targetType: .global,
            targetId: nil,
            targetName: nil,
            confidence: insight.confidence
        )

        try await storage.saveInsightFeedback(&feedback)
    }

    // MARK: - Action Implementations

    private func applyBulkCategorize(changes: [String: Any]) async throws {
        guard let sessionIds = changes["sessionIds"] as? [Int64],
              let categorySlug = changes["categorySlug"] as? String else {
            throw InsightError.missingParameters
        }

        let categories = try await storage.fetchAllCategories()
        guard let category = categories.first(where: { $0.slug == categorySlug }) else {
            throw InsightError.categoryNotFound(categorySlug)
        }

        guard let categoryId = category.id else {
            throw InsightError.invalidCategoryId
        }

        try await storage.bulkUpdateSessionCategory(sessionIds: sessionIds, categoryId: categoryId)
    }

    private func applyBulkAssignProject(changes: [String: Any]) async throws {
        guard let sessionIds = changes["sessionIds"] as? [Int64],
              let projectId = changes["projectId"] as? Int64 else {
            throw InsightError.missingParameters
        }

        try await storage.bulkUpdateSessionProject(sessionIds: sessionIds, projectId: projectId)
    }

    private func applyAddPattern(changes: [String: Any]) async throws {
        guard let projectId = changes["projectId"] as? Int64,
              let pattern = changes["pattern"] as? String else {
            throw InsightError.missingParameters
        }

        try await storage.addPatternToProject(projectId: projectId, pattern: pattern)
    }

    private func applyCreateProject(changes: [String: Any]) async throws {
        guard let projectName = changes["projectName"] as? String else {
            throw InsightError.missingParameters
        }

        let sessionIds = changes["sessionIds"] as? [Int64] ?? []

        // Create the project
        var project = Project(name: projectName)
        try await storage.saveProject(&project)

        // Assign sessions if any
        if let projectId = project.id, !sessionIds.isEmpty {
            try await storage.bulkUpdateSessionProject(sessionIds: sessionIds, projectId: projectId)
        }
    }

    private func applyChangeRole(changes: [String: Any]) async throws {
        guard let projectId = changes["projectId"] as? Int64,
              let newRoleId = changes["newRoleId"] as? Int64 else {
            throw InsightError.missingParameters
        }

        try await storage.updateProjectRole(projectId: projectId, roleId: newRoleId)
    }

    private func applyChangeCategory(changes: [String: Any]) async throws {
        guard let projectId = changes["projectId"] as? Int64,
              let newCategoryId = changes["newCategoryId"] as? Int64 else {
            throw InsightError.missingParameters
        }

        try await storage.updateProjectDefaultCategory(projectId: projectId, categoryId: newCategoryId)
    }

    // MARK: - Helpers

    private func inferCategoryForApp(appName: String, sessions: [ActivitySession]) -> String? {
        let appLower = appName.lowercased()

        // Communication apps
        if appLower.contains("slack") || appLower.contains("mail") || appLower.contains("outlook") ||
           appLower.contains("messages") || appLower.contains("teams") {
            return "responding"
        }

        // Meeting apps
        if appLower.contains("zoom") || appLower.contains("meet") || appLower.contains("facetime") ||
           appLower.contains("webex") || appLower.contains("calendar") {
            return "meetings"
        }

        // Development/Creating
        if appLower.contains("xcode") || appLower.contains("code") || appLower.contains("sublime") ||
           appLower.contains("terminal") || appLower.contains("figma") || appLower.contains("sketch") {
            return "creating"
        }

        // Research/Discovery
        if appLower.contains("safari") || appLower.contains("chrome") || appLower.contains("firefox") ||
           appLower.contains("notion") || appLower.contains("confluence") {
            return "discovery"
        }

        // Planning
        if appLower.contains("linear") || appLower.contains("jira") || appLower.contains("asana") ||
           appLower.contains("trello") || appLower.contains("miro") {
            return "planning"
        }

        // Entertainment
        if appLower.contains("spotify") || appLower.contains("music") || appLower.contains("netflix") ||
           appLower.contains("youtube") || appLower.contains("twitter") || appLower.contains("reddit") {
            return "personal"
        }

        return nil
    }

    private func extractCommonPatterns(from titles: [String]) -> [String] {
        // Find common substrings or keywords
        var patterns: [String: Int] = [:]

        for title in titles {
            // Extract potential patterns (ticket numbers, project codes, etc.)
            let ticketPattern = #"[A-Z]+-\d+"#
            if let regex = try? NSRegularExpression(pattern: ticketPattern),
               let match = regex.firstMatch(in: title, range: NSRange(title.startIndex..., in: title)),
               let range = Range(match.range, in: title) {
                let ticket = String(title[range])
                let prefix = ticket.components(separatedBy: "-").first ?? ""
                patterns[prefix, default: 0] += 1
            }

            // Extract bracketed content
            let bracketPattern = #"\[([^\]]+)\]"#
            if let regex = try? NSRegularExpression(pattern: bracketPattern),
               let match = regex.firstMatch(in: title, range: NSRange(title.startIndex..., in: title)),
               let range = Range(match.range(at: 1), in: title) {
                let content = String(title[range])
                patterns[content, default: 0] += 1
            }
        }

        // Return patterns that appear in at least 30% of titles
        let threshold = max(2, titles.count / 3)
        return patterns.filter { $0.value >= threshold }.map { $0.key }
    }

    private func inferRoleFromSessions(_ sessions: [ActivitySession], availableRoles: [ProjectRole]) -> ProjectRole? {
        var roleScores: [Int64: Int] = [:]

        for session in sessions {
            guard let windowTitle = session.windowTitle else { continue }

            for role in availableRoles {
                // Get detection patterns for this role from the static dictionary
                if let patterns = ProjectRole.detectionPatterns[role.name] {
                    for pattern in patterns {
                        if windowTitle.lowercased().contains(pattern.lowercased()) {
                            roleScores[role.id!, default: 0] += 1
                        }
                    }
                }
            }
        }

        guard let topRole = roleScores.max(by: { $0.value < $1.value }),
              topRole.value >= sessions.count / 3 else {
            return nil
        }

        return availableRoles.first { $0.id == topRole.key }
    }

    private func generateSummary(insights: [ActionableInsight], sessions: [ActivitySession]) -> String {
        let categorized = sessions.filter { $0.projectId != nil }.count
        let coverage = Int(Double(categorized) / Double(sessions.count) * 100)

        if insights.isEmpty {
            return "All sessions are well-categorized. No suggestions at this time."
        }

        let highConfidence = insights.filter { $0.confidence >= 0.8 }.count
        let actionable = insights.filter { !$0.suggestedActions.isEmpty }.count

        return "\(insights.count) insights generated from \(sessions.count) sessions (\(coverage)% coverage). \(highConfidence) high-confidence suggestions ready to apply."
    }
}

// MARK: - Errors

enum InsightError: LocalizedError {
    case invalidAction
    case unknownAction(String)
    case missingParameters
    case categoryNotFound(String)
    case invalidCategoryId
    case projectNotFound

    var errorDescription: String? {
        switch self {
        case .invalidAction:
            return "Invalid action specified"
        case .unknownAction(let action):
            return "Unknown action type: \(action)"
        case .missingParameters:
            return "Missing required parameters for action"
        case .categoryNotFound(let slug):
            return "Category not found: \(slug)"
        case .invalidCategoryId:
            return "Invalid category ID"
        case .projectNotFound:
            return "Project not found"
        }
    }
}
