import SwiftUI

/// View for managing work categories
@available(macOS 14.0, *)
struct WorkCategoriesView: View {
    @EnvironmentObject var appState: AppState
    @State private var categories: [WorkCategory] = []
    @State private var editingCategory: WorkCategory?
    @State private var showingAddSheet = false
    @State private var isLoading = true

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Work Categories")
                    .font(.headline)

                Spacer()

                Button(action: { showingAddSheet = true }) {
                    Label("Add Category", systemImage: "plus")
                }
                .buttonStyle(.bordered)
            }
            .padding()

            Divider()

            // Categories list
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(categories) { category in
                        CategoryRow(category: category)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if !category.isBuiltIn {
                                    editingCategory = category
                                }
                            }
                            .contextMenu {
                                if !category.isBuiltIn {
                                    Button("Edit") {
                                        editingCategory = category
                                    }
                                    Button("Delete", role: .destructive) {
                                        Task { await deleteCategory(category) }
                                    }
                                }
                            }
                    }
                    .onMove { from, to in
                        moveCategory(from: from, to: to)
                    }
                }
                .listStyle(.inset)
            }
        }
        .sheet(item: $editingCategory) { category in
            CategoryEditSheet(category: category) { updated in
                Task { await saveCategory(updated) }
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            CategoryEditSheet(category: nil) { newCategory in
                Task { await saveCategory(newCategory) }
            }
        }
        .task {
            await loadCategories()
        }
    }

    // MARK: - Data Operations

    private func loadCategories() async {
        isLoading = true
        do {
            categories = try await appState.storageManager.fetchAllCategories()
        } catch {
            print("Failed to load categories: \(error)")
        }
        isLoading = false
    }

    private func saveCategory(_ category: WorkCategory) async {
        var mutableCategory = category
        do {
            try await appState.storageManager.saveCategory(&mutableCategory)
            await loadCategories()
        } catch {
            print("Failed to save category: \(error)")
        }
    }

    private func deleteCategory(_ category: WorkCategory) async {
        do {
            try await appState.storageManager.deleteCategory(category)
            await loadCategories()
        } catch {
            print("Failed to delete category: \(error)")
        }
    }

    private func moveCategory(from source: IndexSet, to destination: Int) {
        categories.move(fromOffsets: source, toOffset: destination)

        // Update sort orders
        Task {
            for (index, var category) in categories.enumerated() {
                category.sortOrder = index
                try? await appState.storageManager.saveCategory(&category)
            }
        }
    }
}

// MARK: - Category Row

@available(macOS 14.0, *)
struct CategoryRow: View {
    let category: WorkCategory

    var body: some View {
        HStack(spacing: 12) {
            // Icon
            Image(systemName: category.icon)
                .font(.title3)
                .foregroundColor(Color(hex: category.color))
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(category.name)
                        .fontWeight(.medium)

                    if category.isBuiltIn {
                        Text("Built-in")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.gray.opacity(0.2))
                            .cornerRadius(4)
                    }
                }

                Text(category.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text(category.slug)
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(4)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Category Edit Sheet

@available(macOS 14.0, *)
struct CategoryEditSheet: View {
    let category: WorkCategory?
    let onSave: (WorkCategory) -> Void

    @Environment(\.dismiss) var dismiss

    @State private var name: String = ""
    @State private var slug: String = ""
    @State private var icon: String = "tag.fill"
    @State private var color: String = "#6B7280"
    @State private var description: String = ""

    private let iconOptions = [
        "tag.fill", "person.fill", "magnifyingglass", "envelope.fill",
        "pencil.and.outline", "video.fill", "calendar.badge.clock",
        "person.3.fill", "doc.text.fill", "chart.bar.fill",
        "lightbulb.fill", "hammer.fill", "paintbrush.fill"
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

                Text(category == nil ? "New Category" : "Edit Category")
                    .fontWeight(.semibold)

                Spacer()

                Button("Save") {
                    save()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.isEmpty || slug.isEmpty)
            }
            .padding()

            Divider()

            Form {
                Section("Basic Info") {
                    TextField("Name", text: $name)
                        .onChange(of: name) { oldValue, newValue in
                            if category == nil {
                                // Auto-generate slug for new categories
                                slug = newValue.lowercased()
                                    .replacingOccurrences(of: " ", with: "_")
                                    .filter { $0.isLetter || $0.isNumber || $0 == "_" }
                            }
                        }

                    TextField("Slug (identifier)", text: $slug)
                        .textFieldStyle(.roundedBorder)
                        .disabled(category?.isBuiltIn == true)

                    TextField("Description", text: $description, axis: .vertical)
                        .lineLimit(2...4)
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
                    CategoryRow(category: WorkCategory(
                        name: name.isEmpty ? "Category Name" : name,
                        slug: slug.isEmpty ? "slug" : slug,
                        icon: icon,
                        color: color,
                        description: description.isEmpty ? "Category description" : description
                    ))
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: 450, height: 500)
        .onAppear {
            if let category = category {
                name = category.name
                slug = category.slug
                icon = category.icon
                color = category.color
                description = category.description
            }
        }
    }

    private func save() {
        var updatedCategory = category ?? WorkCategory(
            name: name,
            slug: slug,
            icon: icon,
            color: color,
            description: description
        )

        updatedCategory.name = name
        updatedCategory.slug = slug
        updatedCategory.icon = icon
        updatedCategory.color = color
        updatedCategory.description = description

        onSave(updatedCategory)
        dismiss()
    }
}

@available(macOS 14.0, *)
#Preview {
    WorkCategoriesView()
        .environmentObject(AppState.shared)
}
