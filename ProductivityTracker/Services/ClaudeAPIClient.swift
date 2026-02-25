import Foundation
import AppKit
import Combine

/// Response structure for AI categorization
struct AICategorization: Codable {
    let projectName: String
    let projectRole: String
    let workCategory: String
    let confidence: Double
    let reasoning: String
    let suggestedPatterns: [String]
    let keyInsights: [String]?
    let summary: String?
}

/// ClaudeAPIClient handles communication with the Claude API for screenshot analysis
/// and AI-first categorization of productivity data.
@MainActor
final class ClaudeAPIClient: ObservableObject {
    static let shared = ClaudeAPIClient()

    private let baseURL = "https://api.anthropic.com/v1/messages"
    private let modelId = "claude-sonnet-4-20250514"

    @Published var isProcessing = false
    @Published var lastError: Error?

    private var apiKey: String? {
        // Load from Keychain or environment
        ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"]
            ?? KeychainHelper.get(forKey: "anthropicAPIKey")
    }

    private init() {
        // Migrate API key from UserDefaults to Keychain
        if let oldKey = UserDefaults.standard.string(forKey: "anthropicAPIKey"),
           !oldKey.isEmpty,
           KeychainHelper.get(forKey: "anthropicAPIKey") == nil {
            KeychainHelper.save(oldKey, forKey: "anthropicAPIKey")
            UserDefaults.standard.removeObject(forKey: "anthropicAPIKey")
        }
    }

    // MARK: - Role-Aware Screenshot Summary

    /// Generate a role-aware analysis of a screenshot with AI categorization.
    /// This is the primary method for AI-first categorization at capture time.
    func generateRoleAwareScreenshotSummary(
        screenshot: NSImage,
        appName: String?,
        windowTitle: String?,
        availableRoles: [ProjectRole],
        availableCategories: [WorkCategory],
        existingProjects: [Project]
    ) async throws -> AICategorization {
        guard let apiKey = apiKey, !apiKey.isEmpty else {
            throw ClaudeAPIError.missingAPIKey
        }

        isProcessing = true
        defer { isProcessing = false }

        // Convert image to base64 PNG with multiple fallback strategies
        let pngData = try convertImageToPNG(screenshot)
        let base64Image = pngData.base64EncodedString()

        // Build the role-aware prompt
        let prompt = buildRoleAwarePrompt(
            appName: appName,
            windowTitle: windowTitle,
            availableRoles: availableRoles,
            availableCategories: availableCategories,
            existingProjects: existingProjects
        )

        // Build the API request
        let request = try buildRequest(prompt: prompt, base64Image: base64Image)

        // Log request details for debugging
        print("🔵 Making API request to: \(request.url?.absoluteString ?? "unknown")")
        print("🔵 Has API key: \(!apiKey.isEmpty)")
        print("🔵 Image size: \(base64Image.count) bytes")

        // Make the API call
        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                print("🔴 Invalid response type")
                throw ClaudeAPIError.invalidResponse
            }

            print("🔵 Response status code: \(httpResponse.statusCode)")

            guard httpResponse.statusCode == 200 else {
                let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
                print("🔴 API error (\(httpResponse.statusCode)): \(errorBody)")
                throw ClaudeAPIError.apiError(statusCode: httpResponse.statusCode, message: errorBody)
            }

            // Parse the response
            return try parseCategorizationResponse(data)
        } catch let error as URLError {
            print("🔴 URLError: \(error)")
            print("🔴 Error code: \(error.code.rawValue)")
            print("🔴 Error description: \(error.localizedDescription)")
            if let url = error.failingURL {
                print("🔴 Failing URL: \(url)")
            }
            throw error
        } catch {
            print("🔴 Unexpected error: \(error)")
            throw error
        }
    }

    // MARK: - Simple Screenshot Summary (Legacy)

    /// Simple screenshot summary without structured categorization
    func generateScreenshotSummary(screenshot: NSImage) async throws -> String {
        guard let apiKey = apiKey, !apiKey.isEmpty else {
            throw ClaudeAPIError.missingAPIKey
        }

        isProcessing = true
        defer { isProcessing = false }

        // Convert image to base64 PNG with multiple fallback strategies
        let pngData = try convertImageToPNG(screenshot)
        let base64Image = pngData.base64EncodedString()

        let prompt = """
        Analyze this screenshot and provide a brief summary of what the user is working on.
        Focus on the main activity, application, and any visible project or task context.
        Keep the summary concise (2-3 sentences).
        """

        let request = try buildRequest(prompt: prompt, base64Image: base64Image)
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw ClaudeAPIError.invalidResponse
        }

        return try parseSimpleResponse(data)
    }

    // MARK: - Private Helpers

    private func buildRoleAwarePrompt(
        appName: String?,
        windowTitle: String?,
        availableRoles: [ProjectRole],
        availableCategories: [WorkCategory],
        existingProjects: [Project]
    ) -> String {
        let rolesList = availableRoles.map { $0.name }.joined(separator: ", ")
        let categoriesList = availableCategories.map { "- \($0.slug): \($0.description)" }.joined(separator: "\n")
        let projectsList = existingProjects.prefix(20).map { "- \($0.name)" }.joined(separator: "\n")

        return """
        Analyze this screenshot for a Product Lead at Cash App (Disputes & Scams).

        CURRENT CONTEXT:
        - Application: \(appName ?? "Unknown")
        - Window Title: \(windowTitle ?? "Unknown")

        WORK ROLES (choose one): \(rolesList)

        WORK CATEGORIES (choose one):
        \(categoriesList)

        EXISTING PROJECTS (match if applicable, or suggest new):
        \(projectsList.isEmpty ? "No existing projects yet" : projectsList)

        DETECTION HINTS:
        - Linear tickets: DISP-* = Disputes team, SCAM-* = Scams team
        - Meeting titles often indicate project context
        - Slack channels indicate team (#disputes, #scams, #platform)
        - GitHub repos may indicate project ownership
        - Figma files often have project names

        RESPOND WITH VALID JSON ONLY (no markdown, no extra text):
        {
          "projectName": "string - name of the project being worked on (be specific, e.g., 'Dispute Resolution Flow' not just 'Work')",
          "projectRole": "string - one of: \(rolesList)",
          "workCategory": "string - one of: \(availableCategories.map { $0.slug }.joined(separator: ", "))",
          "confidence": 0.0-1.0,
          "reasoning": "string - brief explanation of why you chose this categorization",
          "suggestedPatterns": ["array of strings - detection patterns for future matching"],
          "keyInsights": ["array of strings - key observations about the activity"],
          "summary": "string - 2-3 sentence summary of what the user is doing"
        }

        Important:
        - Be specific with project names, don't use generic terms like "Work" or "Project"
        - If unsure, set confidence lower and explain in reasoning
        - suggestedPatterns should include identifiable strings like ticket IDs, channel names, repo names
        - For personal/non-work activities, use projectRole "Personal" and workCategory "personal"
        """
    }

    private func buildRequest(prompt: String, base64Image: String) throws -> URLRequest {
        guard let apiKey = apiKey else {
            throw ClaudeAPIError.missingAPIKey
        }

        var request = URLRequest(url: URL(string: baseURL)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let body: [String: Any] = [
            "model": modelId,
            "max_tokens": 1024,
            "messages": [
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "image",
                            "source": [
                                "type": "base64",
                                "media_type": "image/png",
                                "data": base64Image
                            ]
                        ],
                        [
                            "type": "text",
                            "text": prompt
                        ]
                    ]
                ]
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    private func parseCategorizationResponse(_ data: Data) throws -> AICategorization {
        // Parse Claude API response structure
        struct ClaudeResponse: Codable {
            struct Content: Codable {
                let type: String
                let text: String?
            }
            let content: [Content]
        }

        let response = try JSONDecoder().decode(ClaudeResponse.self, from: data)

        guard let textContent = response.content.first(where: { $0.type == "text" }),
              let text = textContent.text else {
            throw ClaudeAPIError.noTextInResponse
        }

        // Extract JSON from the response (handle potential markdown wrapping)
        let jsonString = extractJSON(from: text)

        guard let jsonData = jsonString.data(using: .utf8) else {
            throw ClaudeAPIError.invalidJSON
        }

        return try JSONDecoder().decode(AICategorization.self, from: jsonData)
    }

    private func parseSimpleResponse(_ data: Data) throws -> String {
        struct ClaudeResponse: Codable {
            struct Content: Codable {
                let type: String
                let text: String?
            }
            let content: [Content]
        }

        let response = try JSONDecoder().decode(ClaudeResponse.self, from: data)

        guard let textContent = response.content.first(where: { $0.type == "text" }),
              let text = textContent.text else {
            throw ClaudeAPIError.noTextInResponse
        }

        return text
    }

    private func extractJSON(from text: String) -> String {
        // Remove markdown code blocks if present
        var cleaned = text
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Find JSON object boundaries
        if let start = cleaned.firstIndex(of: "{"),
           let end = cleaned.lastIndex(of: "}") {
            cleaned = String(cleaned[start...end])
        }

        return cleaned
    }

    // MARK: - Comprehensive Analysis

    /// Generate comprehensive analysis of productivity data
    func generateComprehensiveAnalysis(
        sessions: [ActivitySession],
        period: TimePeriod,
        previousFeedback: [InsightFeedback]?
    ) async throws -> ComprehensiveAnalysisResponse {
        guard let apiKey = apiKey, !apiKey.isEmpty else {
            throw ClaudeAPIError.missingAPIKey
        }

        isProcessing = true
        defer { isProcessing = false }

        // Build the comprehensive analysis prompt
        let prompt = buildComprehensiveAnalysisPrompt(
            sessions: sessions,
            period: period,
            previousFeedback: previousFeedback
        )

        // Build request (text-only, no image)
        let request = try buildTextRequest(prompt: prompt, maxTokens: 4096)

        // Make the API call
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClaudeAPIError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw ClaudeAPIError.apiError(statusCode: httpResponse.statusCode, message: errorBody)
        }

        // Parse the response
        return try parseComprehensiveAnalysisResponse(data)
    }

    /// Answer a follow-up question about an analysis
    func answerFollowUpQuestion(
        question: String,
        analysis: ComprehensiveAnalysis,
        sessions: [ActivitySession],
        previousExchanges: [AnalysisExchange]
    ) async throws -> String {
        guard let apiKey = apiKey, !apiKey.isEmpty else {
            throw ClaudeAPIError.missingAPIKey
        }

        isProcessing = true
        defer { isProcessing = false }

        // Build follow-up question prompt
        let prompt = buildFollowUpQuestionPrompt(
            question: question,
            analysis: analysis,
            sessions: sessions,
            previousExchanges: previousExchanges
        )

        let request = try buildTextRequest(prompt: prompt, maxTokens: 2048)
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw ClaudeAPIError.invalidResponse
        }

        return try parseSimpleResponse(data)
    }

    /// Process feedback for analysis improvement
    func processFeedbackForAnalysis(
        feedback: String,
        analysis: ComprehensiveAnalysis
    ) async throws -> InsightFeedback {
        guard let apiKey = apiKey, !apiKey.isEmpty else {
            throw ClaudeAPIError.missingAPIKey
        }

        isProcessing = true
        defer { isProcessing = false }

        // For now, create a simple feedback record
        // In the future, we could use Claude to extract actionable insights from the feedback
        return InsightFeedback(
            insightType: .workPattern,
            insightContent: feedback,
            feedbackAction: .applied,
            targetType: .global,
            appliedChanges: ["analysisId": analysis.id ?? 0],
            confidence: 1.0
        )
    }

    // MARK: - Private Helpers - Comprehensive Analysis

    private func buildComprehensiveAnalysisPrompt(
        sessions: [ActivitySession],
        period: TimePeriod,
        previousFeedback: [InsightFeedback]?
    ) -> String {
        let totalTime = sessions.reduce(0) { $0 + $1.duration }
        let sessionCount = sessions.count

        // Format session data
        let sessionData = sessions.prefix(100).map { session -> String in
            var parts: [String] = []

            if let app = session.appName {
                parts.append("App: \(app)")
            }
            if let window = session.windowTitle {
                parts.append("Window: \(window)")
            }
            parts.append("Duration: \(session.formattedDuration)")

            if let summary = session.summary {
                parts.append("Summary: \(summary)")
            }
            if let projectId = session.projectId {
                parts.append("ProjectId: \(projectId)")
            }
            if let categoryId = session.workCategoryId {
                parts.append("CategoryId: \(categoryId)")
            }

            return parts.joined(separator: " | ")
        }.joined(separator: "\n")

        // Format previous feedback if any
        let feedbackContext = previousFeedback?.prefix(5).map { fb in
            "- \(fb.insightContent) (\(fb.feedbackAction.displayName))"
        }.joined(separator: "\n") ?? "No previous feedback"

        return """
        Analyze this productivity data and provide structured insights:

        PERIOD: \(period.displayName)
        TOTAL TIME: \(formatDuration(totalTime))
        SESSION COUNT: \(sessionCount)

        DETAILED SESSION DATA:
        \(sessionData)

        PREVIOUS USER FEEDBACK:
        \(feedbackContext)

        YOUR TASK:
        1. SEGMENT THE WORK: Identify 3-8 natural work segments. Don't use predefined
           categories - discover what segments make sense based on the actual work patterns.

           For each segment provide:
           - A clear name (e.g., "Deep Focus: iOS App Development" not just "Coding")
           - Brief description of what work was done
           - Duration and focus quality assessment (excellent/good/fragmented)
           - Session IDs that belong to this segment

        2. CREATE TIMELINE: Build a visual timeline of activities by breaking sessions into
           activity blocks. For each block provide:
           - Activity type (e.g., "Coding", "Meeting", "Research", "Email")
           - Start and end times (as ISO 8601 strings)
           - A hex color code for visualization (use consistent colors per activity type)
           - App name if relevant

        3. CONTEXT SWITCHING ANALYSIS: Identify meaningful context switches
           (not just app switches). How fragmented was the work? What patterns emerge?

        4. KEY INSIGHTS: 3-5 specific observations about work patterns,
           productivity, or focus quality. Be concrete and actionable.

        5. RECOMMENDATIONS: 2-4 actionable suggestions to improve focus or productivity.
           Base these on the actual data patterns you observe.

        Return your response as structured JSON with this exact format:
        {
          "overview": "2-3 sentence high-level summary",
          "workSegments": [
            {
              "name": "segment name",
              "description": "what was accomplished",
              "duration": <seconds as number>,
              "focusQuality": "excellent|good|fragmented",
              "sessionIds": [<session IDs as numbers>]
            }
          ],
          "timelineSegments": [
            {
              "startTime": "2026-02-25T09:00:00Z",
              "endTime": "2026-02-25T10:30:00Z",
              "activityType": "Coding",
              "categoryColor": "#4A90E2",
              "appName": "Xcode"
            }
          ],
          "contextAnalysis": "Analysis of context switching patterns",
          "keyInsights": ["insight 1", "insight 2", "insight 3"],
          "recommendations": ["recommendation 1", "recommendation 2"]
        }

        IMPORTANT:
        - Return ONLY valid JSON, no markdown code blocks, no extra text
        - Be specific and concrete, avoid generic statements
        - Base all insights on actual observed patterns in the data
        - Consider previous user feedback when forming insights
        """
    }

    private func buildFollowUpQuestionPrompt(
        question: String,
        analysis: ComprehensiveAnalysis,
        sessions: [ActivitySession],
        previousExchanges: [AnalysisExchange]
    ) -> String {
        // Format previous conversation
        let conversationContext = previousExchanges.map { exchange in
            "Q: \(exchange.question)\nA: \(exchange.answer)"
        }.joined(separator: "\n\n")

        // Format work segments
        let segmentsContext = analysis.workSegments.map { segment in
            "- \(segment.name): \(segment.formattedDuration), Focus: \(segment.focusQuality ?? "unknown")"
        }.joined(separator: "\n")

        return """
        You are helping analyze productivity data. Answer the user's follow-up question based on the analysis.

        ORIGINAL ANALYSIS:
        Overview: \(analysis.overview)

        Work Segments:
        \(segmentsContext)

        Key Insights:
        \(analysis.keyInsights.map { "- \($0)" }.joined(separator: "\n"))

        Total Time: \(analysis.formattedTotalTime)
        Sessions: \(analysis.sessionCount)

        PREVIOUS CONVERSATION:
        \(conversationContext.isEmpty ? "No previous questions" : conversationContext)

        USER QUESTION:
        \(question)

        Provide a clear, specific answer based on the analysis data. Reference specific segments, times, and insights when relevant.
        Keep your response concise but informative (2-4 sentences).
        """
    }

    private func buildTextRequest(prompt: String, maxTokens: Int) throws -> URLRequest {
        guard let apiKey = apiKey else {
            throw ClaudeAPIError.missingAPIKey
        }

        var request = URLRequest(url: URL(string: baseURL)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let body: [String: Any] = [
            "model": modelId,
            "max_tokens": maxTokens,
            "messages": [
                [
                    "role": "user",
                    "content": prompt
                ]
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    private func parseComprehensiveAnalysisResponse(_ data: Data) throws -> ComprehensiveAnalysisResponse {
        // Parse Claude API response structure
        struct ClaudeResponse: Codable {
            struct Content: Codable {
                let type: String
                let text: String?
            }
            let content: [Content]
        }

        let response = try JSONDecoder().decode(ClaudeResponse.self, from: data)

        guard let textContent = response.content.first(where: { $0.type == "text" }),
              let text = textContent.text else {
            throw ClaudeAPIError.noTextInResponse
        }

        // Extract JSON from the response
        let jsonString = extractJSON(from: text)

        guard let jsonData = jsonString.data(using: .utf8) else {
            throw ClaudeAPIError.invalidJSON
        }

        return try JSONDecoder().decode(ComprehensiveAnalysisResponse.self, from: jsonData)
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60

        if hours > 0 {
            return String(format: "%dh %dm", hours, minutes)
        } else {
            return String(format: "%dm", minutes)
        }
    }

    // MARK: - API Key Management

    func setAPIKey(_ key: String) {
        KeychainHelper.save(key, forKey: "anthropicAPIKey")
    }

    var hasAPIKey: Bool {
        guard let key = apiKey else { return false }
        return !key.isEmpty
    }

    // MARK: - Image Conversion Helper

    /// Convert NSImage to PNG Data with multiple fallback strategies
    /// Handles images from ScreenCaptureKit and other sources
    private func convertImageToPNG(_ image: NSImage) throws -> Data {
        let size = image.size

        // Strategy 1: Try to get existing bitmap representation
        if let tiffData = image.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiffData),
           let pngData = bitmap.representation(using: .png, properties: [:]) {
            return pngData
        }

        // Strategy 2: Try direct CGImage conversion
        if let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            let bitmap = NSBitmapImageRep(cgImage: cgImage)
            bitmap.size = size
            if let pngData = bitmap.representation(using: .png, properties: [:]) {
                return pngData
            }
        }

        // Strategy 3: Draw into a new bitmap context (most reliable for ScreenCaptureKit)
        let width = Int(size.width)
        let height = Int(size.height)
        let bitmapRep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: width * 4,
            bitsPerPixel: 32
        )

        guard let bitmap = bitmapRep else {
            throw ClaudeAPIError.imageConversionFailed
        }

        // Draw the image into the bitmap
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        image.draw(in: NSRect(x: 0, y: 0, width: size.width, height: size.height))
        NSGraphicsContext.restoreGraphicsState()

        guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
            throw ClaudeAPIError.imageConversionFailed
        }

        return pngData
    }
}

// MARK: - Errors

enum ClaudeAPIError: LocalizedError {
    case missingAPIKey
    case imageConversionFailed
    case invalidResponse
    case apiError(statusCode: Int, message: String)
    case noTextInResponse
    case invalidJSON

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "API key not configured. Please add your Anthropic API key in Settings."
        case .imageConversionFailed:
            return "Failed to convert screenshot to PNG format."
        case .invalidResponse:
            return "Received invalid response from API."
        case .apiError(let code, let message):
            return "API error (\(code)): \(message)"
        case .noTextInResponse:
            return "No text content in API response."
        case .invalidJSON:
            return "Failed to parse AI response as JSON."
        }
    }
}
