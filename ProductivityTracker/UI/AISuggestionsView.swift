import SwiftUI

/// View for reviewing pending AI suggestions
@available(macOS 14.0, *)
struct AISuggestionsView: View {
    @EnvironmentObject var appState: AppState
    @State private var suggestions: [AISuggestion] = []
    @State private var isLoading = true
    @State private var selectedSuggestion: AISuggestion?
    @State private var showingModifySheet = false

    var groupedSuggestions: [Int64: [AISuggestion]] {
        Dictionary(grouping: suggestions) { $0.sessionId }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("AI Suggestions")
                        .font(.headline)

                    Text("\(suggestions.count) pending review")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if !suggestions.isEmpty {
                    Button("Accept All High Confidence") {
                        Task { await acceptHighConfidence() }
                    }
                    .buttonStyle(.bordered)

                    Button("Dismiss All") {
                        Task { await dismissAll() }
                    }
                    .buttonStyle(.bordered)
                    .foregroundColor(.red)
                }
            }
            .padding()

            Divider()

            // Suggestions list
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if suggestions.isEmpty {
                emptyState
            } else {
                suggestionsList
            }
        }
        .sheet(isPresented: $showingModifySheet) {
            if let suggestion = selectedSuggestion {
                ModifySuggestionSheet(suggestion: suggestion) { modified in
                    Task { await modifySuggestion(modified) }
                }
            }
        }
        .task {
            await loadSuggestions()
        }
    }

    // MARK: - Subviews

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text("No Pending Suggestions")
                .font(.headline)

            Text("AI suggestions with low confidence will appear here for your review.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var suggestionsList: some View {
        List {
            ForEach(Array(groupedSuggestions.keys.sorted()), id: \.self) { sessionId in
                Section {
                    ForEach(groupedSuggestions[sessionId] ?? []) { suggestion in
                        SuggestionRow(suggestion: suggestion) { action in
                            handleAction(action, for: suggestion)
                        }
                    }
                } header: {
                    Text("Session #\(sessionId)")
                        .font(.caption)
                }
            }
        }
        .listStyle(.inset)
    }

    // MARK: - Actions

    private func handleAction(_ action: SuggestionAction, for suggestion: AISuggestion) {
        Task {
            switch action {
            case .accept:
                await acceptSuggestion(suggestion)
            case .reject:
                await rejectSuggestion(suggestion)
            case .modify:
                selectedSuggestion = suggestion
                showingModifySheet = true
            }
        }
    }

    // MARK: - Data Operations

    private func loadSuggestions() async {
        isLoading = true
        do {
            suggestions = try await appState.storageManager.fetchPendingSuggestions()
        } catch {
            print("Failed to load suggestions: \(error)")
        }
        isLoading = false
    }

    private func acceptSuggestion(_ suggestion: AISuggestion) async {
        var mutableSuggestion = suggestion
        do {
            try await appState.storageManager.acceptSuggestion(&mutableSuggestion)
            await loadSuggestions()
            await appState.refreshPendingSuggestionsCount()
        } catch {
            print("Failed to accept suggestion: \(error)")
        }
    }

    private func rejectSuggestion(_ suggestion: AISuggestion) async {
        var mutableSuggestion = suggestion
        do {
            try await appState.storageManager.rejectSuggestion(&mutableSuggestion)
            await loadSuggestions()
            await appState.refreshPendingSuggestionsCount()
        } catch {
            print("Failed to reject suggestion: \(error)")
        }
    }

    private func modifySuggestion(_ suggestion: AISuggestion) async {
        var mutableSuggestion = suggestion
        do {
            try await appState.storageManager.saveSuggestion(&mutableSuggestion)
            await loadSuggestions()
            await appState.refreshPendingSuggestionsCount()
        } catch {
            print("Failed to modify suggestion: \(error)")
        }
    }

    private func acceptHighConfidence() async {
        let highConfidence = suggestions.filter { $0.confidence >= 0.7 }
        for suggestion in highConfidence {
            await acceptSuggestion(suggestion)
        }
    }

    private func dismissAll() async {
        for suggestion in suggestions {
            await rejectSuggestion(suggestion)
        }
    }
}

// MARK: - Suggestion Row

enum SuggestionAction {
    case accept
    case reject
    case modify
}

@available(macOS 14.0, *)
struct SuggestionRow: View {
    let suggestion: AISuggestion
    let onAction: (SuggestionAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Image(systemName: suggestion.suggestionType.icon)
                    .foregroundColor(.blue)

                Text(suggestion.suggestionType.displayName)
                    .font(.caption)
                    .fontWeight(.medium)

                Spacer()

                ConfidenceBadge(confidence: suggestion.confidence)
            }

            // Suggested value
            HStack {
                Text(suggestion.suggestedValue)
                    .fontWeight(.medium)

                Spacer()
            }

            // Reasoning
            Text(suggestion.reasoning)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(2)

            // Actions
            HStack(spacing: 8) {
                Button("Accept") {
                    onAction(.accept)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Button("Modify") {
                    onAction(.modify)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("Reject") {
                    onAction(.reject)
                }
                .buttonStyle(.bordered)
                .foregroundColor(.red)
                .controlSize(.small)

                Spacer()

                Text(suggestion.createdAt, style: .relative)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 8)
    }
}

@available(macOS 14.0, *)
struct ConfidenceBadge: View {
    let confidence: Double

    private var color: Color {
        switch confidence {
        case 0..<0.5: return .red
        case 0.5..<0.7: return .orange
        case 0.7..<0.9: return .green
        default: return .blue
        }
    }

    var body: some View {
        Text("\(Int(confidence * 100))%")
            .font(.caption2)
            .fontWeight(.semibold)
            .foregroundColor(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.2))
            .cornerRadius(4)
    }
}

// MARK: - Modify Suggestion Sheet

@available(macOS 14.0, *)
struct ModifySuggestionSheet: View {
    let suggestion: AISuggestion
    let onSave: (AISuggestion) -> Void

    @Environment(\.dismiss) var dismiss
    @State private var modifiedValue: String = ""

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button("Cancel") {
                    dismiss()
                }

                Spacer()

                Text("Modify Suggestion")
                    .fontWeight(.semibold)

                Spacer()

                Button("Save") {
                    save()
                }
                .buttonStyle(.borderedProminent)
                .disabled(modifiedValue.isEmpty)
            }
            .padding()

            Divider()

            Form {
                Section("Original Suggestion") {
                    LabeledContent("Type", value: suggestion.suggestionType.displayName)
                    LabeledContent("Value", value: suggestion.suggestedValue)
                    LabeledContent("Confidence", value: "\(Int(suggestion.confidence * 100))%")
                }

                Section("Reasoning") {
                    Text(suggestion.reasoning)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Section("Your Correction") {
                    TextField("Enter corrected value", text: $modifiedValue)
                        .textFieldStyle(.roundedBorder)

                    Text("This will update the session and improve future AI categorization.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: 400, height: 400)
        .onAppear {
            modifiedValue = suggestion.suggestedValue
        }
    }

    private func save() {
        var modified = suggestion
        modified.modify(newValue: modifiedValue)
        onSave(modified)
        dismiss()
    }
}

@available(macOS 14.0, *)
#Preview {
    AISuggestionsView()
        .environmentObject(AppState.shared)
}
