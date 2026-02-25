import SwiftUI

/// Main view for Claude-powered dynamic analysis
@available(macOS 14.0, *)
struct AIAnalysisView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var analyzer = ComprehensiveAnalyzer.shared
    @State private var sessions: [ActivitySession] = []
    @State private var selectedPeriod: TimePeriod = .today
    @State private var selectedDate: Date = Date()
    @State private var isAnalyzing = false
    @State private var showFeedbackSheet = false
    @State private var feedbackText = ""
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            // Header with period selector
            headerSection
                .padding()

            Divider()

            // Main content
            ScrollView {
                if let error = errorMessage {
                    errorView(error)
                        .padding()
                } else if isAnalyzing {
                    loadingView
                        .padding()
                } else if let analysis = analyzer.currentAnalysis {
                    analysisContent(analysis)
                        .padding()
                } else {
                    emptyStateView
                        .padding()
                }
            }
        }
        .frame(minWidth: 1000, minHeight: 700)
        .task {
            await loadSessionsAndAnalyze()
        }
        .onChange(of: selectedPeriod) { _, _ in
            Task { await loadSessionsAndAnalyze() }
        }
        .onChange(of: selectedDate) { _, _ in
            Task { await loadSessionsAndAnalyze() }
        }
        .sheet(isPresented: $showFeedbackSheet) {
            feedbackSheet
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("AI Analysis")
                    .font(.title2)
                    .fontWeight(.bold)
                Text("Claude-powered insights")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Period selector
            Picker("Period", selection: $selectedPeriod) {
                Text("Today").tag(TimePeriod.today)
                Text("Yesterday").tag(TimePeriod.yesterday)
                Text("Last 7 Days").tag(TimePeriod.last7Days)
                Text("Last 30 Days").tag(TimePeriod.last30Days)
            }
            .pickerStyle(.segmented)
            .frame(width: 400)

            if analyzer.currentAnalysis != nil {
                Button(action: { Task { await regenerateAnalysis() } }) {
                    Label("Regenerate", systemImage: "arrow.clockwise")
                }
                .disabled(isAnalyzing)
            }
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "brain.head.profile")
                .font(.system(size: 72))
                .foregroundColor(.blue)

            VStack(spacing: 8) {
                Text("AI-Powered Analysis")
                    .font(.title)
                    .fontWeight(.bold)

                Text("Let Claude analyze your productivity data and discover meaningful patterns")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 500)
            }

            Button(action: { Task { await analyzeData() } }) {
                Label("Analyze My Day", systemImage: "wand.and.stars")
                    .font(.headline)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .disabled(sessions.isEmpty)

            if sessions.isEmpty {
                Text("No productivity data available for this period")
                    .font(.caption)
                    .foregroundColor(.orange)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: 16) {
            Spacer()

            ProgressView()
                .scaleEffect(1.5)

            Text("Claude is analyzing your productivity data...")
                .font(.headline)

            Text("This may take a minute")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Error View

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundColor(.red)

            Text("Analysis Failed")
                .font(.title2)
                .fontWeight(.bold)

            Text(message)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button("Try Again") {
                Task { await analyzeData() }
            }
            .buttonStyle(.bordered)
        }
        .padding()
    }

    // MARK: - Analysis Content

    private func analysisContent(_ analysis: ComprehensiveAnalysis) -> some View {
        VStack(spacing: 20) {
            // Overview card
            AnalysisOverviewCard(analysis: analysis)

            // Work segments
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "chart.bar.xaxis")
                    Text("Work Segments")
                        .font(.headline)
                }

                ForEach(analysis.workSegments) { segment in
                    WorkSegmentCard(segment: segment, sessions: sessions)
                }
            }

            // Context analysis
            if !analysis.contextAnalysis.isEmpty {
                AnalysisTextCard(
                    title: "Context Switching Analysis",
                    icon: "arrow.triangle.branch",
                    content: analysis.contextAnalysis
                )
            }

            // Key insights
            if !analysis.keyInsights.isEmpty {
                InsightsList(insights: analysis.keyInsights)
            }

            // Recommendations
            if !analysis.recommendations.isEmpty {
                RecommendationsList(recommendations: analysis.recommendations)
            }

            // Question input
            QuestionInput(
                onSubmit: { question in
                    await askQuestion(question)
                }
            )

            // Conversation history
            if !analyzer.conversationHistory.isEmpty {
                ConversationHistory(exchanges: analyzer.conversationHistory)
            }

            // Feedback button
            Button(action: { showFeedbackSheet = true }) {
                Label("Give Feedback", systemImage: "bubble.left.and.bubble.right")
            }
            .buttonStyle(.bordered)
        }
    }

    // MARK: - Feedback Sheet

    private var feedbackSheet: some View {
        VStack(spacing: 16) {
            Text("Provide Feedback")
                .font(.headline)

            Text("What could be better about this analysis?")
                .font(.subheadline)
                .foregroundColor(.secondary)

            TextEditor(text: $feedbackText)
                .frame(height: 150)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                )

            HStack {
                Button("Cancel") {
                    showFeedbackSheet = false
                    feedbackText = ""
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("Submit") {
                    Task {
                        await submitFeedback()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(feedbackText.isEmpty)
            }
        }
        .padding()
        .frame(width: 500, height: 300)
    }

    // MARK: - Actions

    private func loadSessionsAndAnalyze() async {
        await loadSessions()

        guard !sessions.isEmpty else {
            analyzer.clearCurrentAnalysis()
            return
        }

        // Try to load cached analysis first
        if let cached = try? analyzer.loadCachedAnalysis(for: selectedDate, period: selectedPeriod) {
            return
        }

        // Auto-analyze if appropriate
        if analyzer.shouldAutoAnalyze(for: selectedDate, period: selectedPeriod) {
            await analyzeData()
        }
    }

    private func loadSessions() async {
        let range = getDateRange()
        do {
            sessions = try await StorageManager.shared.fetchSessions(
                from: range.start,
                to: range.end
            )
        } catch {
            print("Error loading sessions: \(error)")
            sessions = []
        }
    }

    private func analyzeData() async {
        guard !sessions.isEmpty else {
            errorMessage = "No data available for the selected period"
            return
        }

        isAnalyzing = true
        errorMessage = nil

        do {
            _ = try await analyzer.analyzeData(
                sessions: sessions,
                period: selectedPeriod,
                date: selectedDate
            )
        } catch {
            errorMessage = error.localizedDescription
        }

        isAnalyzing = false
    }

    private func regenerateAnalysis() async {
        isAnalyzing = true
        errorMessage = nil

        do {
            _ = try await analyzer.regenerateAnalysis(
                sessions: sessions,
                period: selectedPeriod,
                date: selectedDate
            )
        } catch {
            errorMessage = error.localizedDescription
        }

        isAnalyzing = false
    }

    private func askQuestion(_ question: String) async {
        guard let analysis = analyzer.currentAnalysis else { return }

        isAnalyzing = true
        defer { isAnalyzing = false }

        do {
            _ = try await analyzer.askQuestion(
                question,
                context: analysis,
                sessions: sessions
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func submitFeedback() async {
        guard let analysis = analyzer.currentAnalysis else { return }

        do {
            try await analyzer.provideFeedback(feedbackText, analysis: analysis)
            showFeedbackSheet = false
            feedbackText = ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func getDateRange() -> (start: Date, end: Date) {
        let calendar = Calendar.current
        let now = Date()

        switch selectedPeriod {
        case .today:
            return (calendar.startOfDay(for: now), now)
        case .yesterday:
            let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!
            return (calendar.startOfDay(for: yesterday), calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: yesterday))!)
        case .last7Days:
            let weekAgo = calendar.date(byAdding: .day, value: -7, to: now)!
            return (calendar.startOfDay(for: weekAgo), now)
        case .last30Days:
            let monthAgo = calendar.date(byAdding: .day, value: -30, to: now)!
            return (calendar.startOfDay(for: monthAgo), now)
        case .custom:
            return (calendar.startOfDay(for: selectedDate), now)
        }
    }
}

// MARK: - Supporting Views

struct AnalysisTextCard: View {
    let title: String
    let icon: String
    let content: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                Text(title)
                    .font(.headline)
            }

            Text(content)
                .font(.body)
                .foregroundColor(.primary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }
}

struct QuestionInput: View {
    @State private var questionText = ""
    @State private var isSubmitting = false
    let onSubmit: (String) async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "bubble.left.and.bubble.right")
                Text("Ask a Question")
                    .font(.headline)
            }

            HStack {
                TextField("What would you like to know?", text: $questionText)
                    .textFieldStyle(.roundedBorder)

                Button(action: {
                    Task {
                        isSubmitting = true
                        await onSubmit(questionText)
                        questionText = ""
                        isSubmitting = false
                    }
                }) {
                    Text("Ask Claude")
                }
                .buttonStyle(.borderedProminent)
                .disabled(questionText.isEmpty || isSubmitting)
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }
}

struct ConversationHistory: View {
    let exchanges: [AnalysisExchange]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "clock.arrow.circlepath")
                Text("Conversation History")
                    .font(.headline)
            }

            ForEach(exchanges) { exchange in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "person.fill")
                            .foregroundColor(.blue)
                        Text(exchange.question)
                            .font(.body)
                            .fontWeight(.medium)
                    }

                    HStack(alignment: .top) {
                        Image(systemName: "brain.head.profile")
                            .foregroundColor(.purple)
                        Text(exchange.answer)
                            .font(.body)
                            .foregroundColor(.secondary)
                    }

                    Text(exchange.timestamp, style: .time)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                .cornerRadius(8)
            }
        }
    }
}
