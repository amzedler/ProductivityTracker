import SwiftUI

/// Main view for managing projects
@available(macOS 14.0, *)
struct ProjectsSettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var projects: [Project] = []
    @State private var roles: [ProjectRole] = []
    @State private var selectedRoleId: Int64? = nil
    @State private var searchText = ""
    @State private var showingAddSheet = false
    @State private var editingProject: Project?
    @State private var isLoading = true

    var filteredProjects: [Project] {
        var filtered = projects

        // Filter by role
        if let roleId = selectedRoleId {
            filtered = filtered.filter { $0.roleId == roleId }
        }

        // Filter by search text
        if !searchText.isEmpty {
            filtered = filtered.filter {
                $0.name.localizedCaseInsensitiveContains(searchText)
            }
        }

        return filtered
    }

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            toolbar

            Divider()

            // Content
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredProjects.isEmpty {
                emptyState
            } else {
                projectList
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            ProjectEditSheet(project: nil, roles: roles) { newProject in
                Task { await saveProject(newProject) }
            }
        }
        .sheet(item: $editingProject) { project in
            ProjectEditSheet(project: project, roles: roles) { updatedProject in
                Task { await saveProject(updatedProject) }
            }
        }
        .task {
            await loadData()
        }
    }

    // MARK: - Subviews

    private var toolbar: some View {
        HStack {
            // Role filter
            Picker("Role", selection: $selectedRoleId) {
                Text("All Roles").tag(nil as Int64?)
                ForEach(roles) { role in
                    Label(role.name, systemImage: role.icon)
                        .tag(role.id)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 150)

            Spacer()

            // Search
            TextField("Search projects...", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 200)

            // Add button
            Button(action: { showingAddSheet = true }) {
                Image(systemName: "plus")
            }
        }
        .padding()
    }

    private var projectList: some View {
        List {
            ForEach(filteredProjects) { project in
                ProjectRow(
                    project: project,
                    role: roles.first { $0.id == project.roleId }
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    editingProject = project
                }
                .contextMenu {
                    Button("Edit") {
                        editingProject = project
                    }
                    Button("Archive", role: .destructive) {
                        Task { await archiveProject(project) }
                    }
                }
            }
        }
        .listStyle(.inset)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "folder.badge.questionmark")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text("No Projects")
                .font(.headline)

            Text("Projects are automatically created when AI categorizes your work.\nYou can also add projects manually.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button("Add Project") {
                showingAddSheet = true
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - Data Operations

    private func loadData() async {
        isLoading = true
        do {
            projects = try await appState.storageManager.fetchAllProjects()
            roles = try await appState.storageManager.fetchAllRoles()
        } catch {
            print("Failed to load projects: \(error)")
        }
        isLoading = false
    }

    private func saveProject(_ project: Project) async {
        var mutableProject = project
        do {
            try await appState.storageManager.saveProject(&mutableProject)
            await loadData()
        } catch {
            print("Failed to save project: \(error)")
        }
    }

    private func archiveProject(_ project: Project) async {
        var mutableProject = project
        mutableProject.isActive = false
        await saveProject(mutableProject)
    }
}

// MARK: - Project Row

@available(macOS 14.0, *)
struct ProjectRow: View {
    let project: Project
    let role: ProjectRole?

    var body: some View {
        HStack(spacing: 12) {
            // Role indicator
            Circle()
                .fill(Color(hex: role?.color ?? "#6B7280"))
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(project.name)
                        .fontWeight(.medium)

                    if project.isAISuggested && !project.isUserConfirmed {
                        Image(systemName: "sparkles")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }

                HStack(spacing: 8) {
                    if let role = role {
                        Text(role.name)
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(hex: role.color).opacity(0.2))
                            .cornerRadius(4)
                    }

                    Text(formatDuration(project.totalDuration))
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if let lastSeen = project.lastSeen {
                        Text("Last: \(lastSeen, style: .relative)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Spacer()

            // Patterns count
            if !project.patternsArray.isEmpty {
                Text("\(project.patternsArray.count) patterns")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        return String(format: "%dh %dm", hours, minutes)
    }
}

// MARK: - Project Edit Sheet

@available(macOS 14.0, *)
struct ProjectEditSheet: View {
    let project: Project?
    let roles: [ProjectRole]
    let onSave: (Project) -> Void

    @Environment(\.dismiss) var dismiss

    @State private var name: String = ""
    @State private var selectedRoleId: Int64? = nil
    @State private var patterns: String = ""
    @State private var notes: String = ""
    @State private var isConfirmed = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button("Cancel") {
                    dismiss()
                }

                Spacer()

                Text(project == nil ? "New Project" : "Edit Project")
                    .fontWeight(.semibold)

                Spacer()

                Button("Save") {
                    save()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.isEmpty)
            }
            .padding()

            Divider()

            // Form
            Form {
                Section("Basic Info") {
                    TextField("Project Name", text: $name)

                    Picker("Role", selection: $selectedRoleId) {
                        Text("None").tag(nil as Int64?)
                        ForEach(roles) { role in
                            Label(role.name, systemImage: role.icon)
                                .tag(role.id)
                        }
                    }

                    Toggle("Confirmed by User", isOn: $isConfirmed)
                }

                Section("Detection Patterns") {
                    TextField("Patterns (one per line)", text: $patterns, axis: .vertical)
                        .lineLimit(5...10)
                        .font(.system(.body, design: .monospaced))

                    Text("Enter patterns that identify this project (e.g., DISP-123, #disputes)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Section("Notes") {
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: 450, height: 500)
        .onAppear {
            if let project = project {
                name = project.name
                selectedRoleId = project.roleId
                patterns = project.patternsArray.joined(separator: "\n")
                notes = project.notes ?? ""
                isConfirmed = project.isUserConfirmed
            }
        }
    }

    private func save() {
        let patternsArray = patterns
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        var updatedProject = project ?? Project(name: name)
        updatedProject.name = name
        updatedProject.roleId = selectedRoleId
        updatedProject.setPatterns(patternsArray)
        updatedProject.notes = notes.isEmpty ? nil : notes
        updatedProject.isUserConfirmed = isConfirmed

        onSave(updatedProject)
        dismiss()
    }
}

@available(macOS 14.0, *)
#Preview {
    ProjectsSettingsView()
        .environmentObject(AppState.shared)
}
