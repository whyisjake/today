//
//  CategoryManagementView.swift
//  Today
//
//  View for managing feed categories (rename, delete, merge)
//

import SwiftUI
import SwiftData

struct CategoryManagementView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @StateObject private var categoryManager = CategoryManager.shared
    @StateObject private var feedManager: FeedManager

    @State private var selectedCategory: String?
    @State private var showRenameSheet = false
    @State private var showMergeSheet = false
    @State private var showDeleteAlert = false
    @State private var newCategoryName = ""
    @State private var mergeTargetCategory = ""
    @State private var errorMessage: String?

    init(modelContext: ModelContext) {
        _feedManager = StateObject(wrappedValue: FeedManager(modelContext: modelContext))
    }

    var body: some View {
        NavigationStack {
            List {
                if !categoryManager.customCategories.isEmpty {
                    Section {
                        ForEach(categoryManager.customCategories, id: \.self) { category in
                            categoryRow(category)
                        }
                    } header: {
                        Text("Custom Categories")
                    }
                }

                Section {
                    ForEach(CategoryManager.pickerCategories, id: \.self) { category in
                        categoryRow(category)
                    }
                } header: {
                    Text("Standard Categories")
                }
            }
            .navigationTitle("Manage Categories")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .alert("Error", isPresented: .constant(errorMessage != nil)) {
                Button("OK") {
                    errorMessage = nil
                }
            } message: {
                if let error = errorMessage {
                    Text(error)
                }
            }
            .sheet(isPresented: $showRenameSheet) {
                renameSheet
            }
            .sheet(isPresented: $showMergeSheet) {
                mergeSheet
            }
            .alert("Delete Category", isPresented: $showDeleteAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    deleteCategory()
                }
            } message: {
                if let category = selectedCategory {
                    Text("Delete '\(category)'? All feeds in this category will be moved to 'General'.")
                }
            }
        }
    }

    @ViewBuilder
    private func categoryRow(_ category: String) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(category)
                    .font(.body)

                if let count = try? feedManager.getFeedCount(forCategory: category) {
                    Text("\(count) feed\(count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Menu {
                Button {
                    selectedCategory = category
                    newCategoryName = category
                    showRenameSheet = true
                } label: {
                    Label("Rename", systemImage: "pencil")
                }

                Button {
                    selectedCategory = category
                    mergeTargetCategory = ""
                    showMergeSheet = true
                } label: {
                    Label("Merge", systemImage: "arrow.triangle.merge")
                }

                if categoryManager.customCategories.contains(category) {
                    Divider()

                    Button(role: .destructive) {
                        selectedCategory = category
                        showDeleteAlert = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var renameSheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Category Name", text: $newCategoryName)
                        .autocapitalization(.words)
                } header: {
                    Text("New Name")
                } footer: {
                    if let category = selectedCategory {
                        Text("Rename '\(category)' to a new name")
                    }
                }
            }
            .navigationTitle("Rename Category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showRenameSheet = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Rename") {
                        renameCategory()
                    }
                    .disabled(newCategoryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private var mergeSheet: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Target Category", selection: $mergeTargetCategory) {
                        Text("Select Category").tag("")
                        ForEach(availableMergeTargets, id: \.self) { category in
                            Text(category).tag(category)
                        }
                    }
                } header: {
                    Text("Merge Into")
                } footer: {
                    if let category = selectedCategory {
                        Text("All feeds in '\(category)' will be moved to the selected category")
                    }
                }
            }
            .navigationTitle("Merge Category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showMergeSheet = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Merge") {
                        mergeCategory()
                    }
                    .disabled(mergeTargetCategory.isEmpty)
                }
            }
        }
    }

    private var availableMergeTargets: [String] {
        guard let selected = selectedCategory else { return [] }
        return categoryManager.allCategories.filter { $0.lowercased() != selected.lowercased() }
    }

    private func renameCategory() {
        guard let oldName = selectedCategory else { return }

        let trimmedNewName = newCategoryName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedNewName.isEmpty else {
            errorMessage = "Category name cannot be empty"
            showRenameSheet = false
            return
        }

        // Attempt to rename in CategoryManager
        guard let newName = categoryManager.renameCategory(from: oldName, to: trimmedNewName) else {
            errorMessage = "Cannot rename to '\(trimmedNewName)'. It may already exist or be a standard category."
            showRenameSheet = false
            return
        }

        // Update all feeds with this category
        do {
            try feedManager.updateFeedsCategory(from: oldName, to: newName)
            showRenameSheet = false
            selectedCategory = nil
        } catch {
            errorMessage = "Failed to update feeds: \(error.localizedDescription)"
            showRenameSheet = false
        }
    }

    private func deleteCategory() {
        guard let category = selectedCategory else { return }

        let defaultCategory = categoryManager.deleteCategory(category)

        // Move all feeds to default category
        do {
            try feedManager.updateFeedsCategory(from: category, to: defaultCategory)
            selectedCategory = nil
        } catch {
            errorMessage = "Failed to move feeds: \(error.localizedDescription)"
        }
    }

    private func mergeCategory() {
        guard let source = selectedCategory else { return }
        guard !mergeTargetCategory.isEmpty else { return }

        // Attempt to merge in CategoryManager
        guard categoryManager.mergeCategories(from: source, to: mergeTargetCategory) else {
            errorMessage = "Cannot merge '\(source)' into '\(mergeTargetCategory)'"
            showMergeSheet = false
            return
        }

        // Update all feeds with this category
        do {
            try feedManager.updateFeedsCategory(from: source, to: mergeTargetCategory)
            showMergeSheet = false
            selectedCategory = nil
        } catch {
            errorMessage = "Failed to update feeds: \(error.localizedDescription)"
            showMergeSheet = false
        }
    }
}

#if DEBUG
#Preview {
    CategoryManagementView(modelContext: ModelContext(try! ModelContainer(for: Feed.self, Article.self)))
}
#endif
