import SwiftUI

/// View for managing project roles (Disputes, Scams, Cross-team, Personal)
@available(macOS 14.0, *)
struct ProjectRolesView: View {
    @EnvironmentObject var appState: AppState
    @State private var roles: [ProjectRole] = []
    @State private var editingRole: ProjectRole?
    @State private var showingAddSheet = false
    @State private var isLoading = true

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Work Roles")
                        .font(.headline)

                    Text("Roles segment projects by your work context")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button(action: { showingAddSheet = true }) {
                    Label("Add Role", systemImage: "plus")
                }
                .buttonStyle(.bordered)
            }
            .padding()

            Divider()

            // Roles list
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(roles) { role in
                        RoleRow(role: role)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                editingRole = role
                            }
                            .contextMenu {
                                Button("Edit") {
                                    editingRole = role
                                }
                                if role.isUserDefined {
                                    Button("Delete", role: .destructive) {
                                        Task { await deleteRole(role) }
                                    }
                                }
                            }
                    }
                    .onMove { from, to in
                        moveRole(from: from, to: to)
                    }
                }
                .listStyle(.inset)
            }
        }
        .sheet(item: $editingRole) { role in
            RoleEditSheet(role: role) { updated in
                Task { await saveRole(updated) }
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            RoleEditSheet(role: nil) { newRole in
                Task { await saveRole(newRole) }
            }
        }
        .task {
            await loadRoles()
        }
    }

    // MARK: - Data Operations

    private func loadRoles() async {
        isLoading = true
        do {
            roles = try await appState.storageManager.fetchAllRoles()
        } catch {
            print("Failed to load roles: \(error)")
        }
        isLoading = false
    }

    private func saveRole(_ role: ProjectRole) async {
        var mutableRole = role
        do {
            try await appState.storageManager.saveRole(&mutableRole)
            await loadRoles()
        } catch {
            print("Failed to save role: \(error)")
        }
    }

    private func deleteRole(_ role: ProjectRole) async {
        do {
            try await appState.storageManager.deleteRole(role)
            await loadRoles()
        } catch {
            print("Failed to delete role: \(error)")
        }
    }

    private func moveRole(from source: IndexSet, to destination: Int) {
        roles.move(fromOffsets: source, toOffset: destination)

        Task {
            for (index, var role) in roles.enumerated() {
                role.sortOrder = index
                try? await appState.storageManager.saveRole(&role)
            }
        }
    }
}

// MARK: - Role Row

@available(macOS 14.0, *)
struct RoleRow: View {
    let role: ProjectRole

    var body: some View {
        HStack(spacing: 12) {
            // Icon with color
            Image(systemName: role.icon)
                .font(.title3)
                .foregroundColor(Color(hex: role.color))
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(role.name)
                        .fontWeight(.medium)

                    if role.isDefault {
                        Text("Default")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.2))
                            .cornerRadius(4)
                    }

                    if !role.isUserDefined {
                        Text("System")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.gray.opacity(0.2))
                            .cornerRadius(4)
                    }
                }

                Text(role.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Role Edit Sheet

@available(macOS 14.0, *)
struct RoleEditSheet: View {
    let role: ProjectRole?
    let onSave: (ProjectRole) -> Void

    @Environment(\.dismiss) var dismiss

    @State private var name: String = ""
    @State private var description: String = ""
    @State private var icon: String = "folder.fill"
    @State private var color: String = "#6B7280"
    @State private var isDefault: Bool = false

    private let iconOptions = [
        "folder.fill", "exclamationmark.triangle.fill", "shield.lefthalf.filled",
        "arrow.triangle.branch", "person.fill", "building.2.fill",
        "chart.pie.fill", "gearshape.fill", "doc.fill", "flag.fill"
    ]

    private let colorOptions = [
        "#EF4444", "#F97316", "#F59E0B", "#10B981",
        "#14B8A6", "#3B82F6", "#8B5CF6", "#EC4899", "#6B7280"
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button("Cancel") {
                    dismiss()
                }

                Spacer()

                Text(role == nil ? "New Role" : "Edit Role")
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

            Form {
                Section("Basic Info") {
                    TextField("Name", text: $name)
                    TextField("Description", text: $description, axis: .vertical)
                        .lineLimit(2...4)
                    Toggle("Set as Default Role", isOn: $isDefault)
                }

                Section("Appearance") {
                    Picker("Icon", selection: $icon) {
                        ForEach(iconOptions, id: \.self) { iconName in
                            Image(systemName: iconName)
                                .tag(iconName)
                        }
                    }
                    .pickerStyle(.palette)

                    HStack {
                        Text("Color")
                        Spacer()
                        ForEach(colorOptions, id: \.self) { colorHex in
                            Circle()
                                .fill(Color(hex: colorHex))
                                .frame(width: 24, height: 24)
                                .overlay(
                                    Circle()
                                        .stroke(Color.primary, lineWidth: color == colorHex ? 2 : 0)
                                )
                                .onTapGesture {
                                    color = colorHex
                                }
                        }
                    }
                }

                Section("Preview") {
                    RoleRow(role: ProjectRole(
                        name: name.isEmpty ? "Role Name" : name,
                        description: description.isEmpty ? "Role description" : description,
                        color: color,
                        icon: icon,
                        isDefault: isDefault
                    ))
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: 450, height: 450)
        .onAppear {
            if let role = role {
                name = role.name
                description = role.description
                icon = role.icon
                color = role.color
                isDefault = role.isDefault
            }
        }
    }

    private func save() {
        var updatedRole = role ?? ProjectRole(
            name: name,
            description: description,
            color: color,
            icon: icon,
            isDefault: isDefault
        )

        updatedRole.name = name
        updatedRole.description = description
        updatedRole.icon = icon
        updatedRole.color = color
        updatedRole.isDefault = isDefault
        updatedRole.isUserDefined = true

        onSave(updatedRole)
        dismiss()
    }
}

@available(macOS 14.0, *)
#Preview {
    ProjectRolesView()
        .environmentObject(AppState.shared)
}
