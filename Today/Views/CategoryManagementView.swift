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

    @State private var feedCategories: [String] = []

    init(modelContext: ModelContext) {
        _feedManager = StateObject(wrappedValue: FeedManager(modelContext: modelContext))
    }

    /// Categories that exist on feeds but don't exactly match any standard or custom category
    /// e.g. "politics" when "Politics" is standard — case mismatches that should be merged
    private var unmanagedCategories: [String] {
        let known = Set(CategoryManager.allStandardCategories + categoryManager.customCategories)
        return feedCategories
            .filter { !known.contains($0) }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            List {
                if !unmanagedCategories.isEmpty {
                    Section {
                        ForEach(unmanagedCategories, id: \.self) { category in
                            categoryRow(category)
                        }
                    } header: {
                        Text("Needs Attention")
                    } footer: {
                        Text("These categories exist on feeds but don't match a standard category. Consider merging them.")
                    }
                }

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
            .task {
                loadFeedCategories()
            }
            .navigationTitle("Manage Categories")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
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
                        #if os(iOS)
                        .autocapitalization(.words)
                        #endif
                } header: {
                    Text("New Name")
                } footer: {
                    if let category = selectedCategory {
                        Text("Rename '\(category)' to a new name")
                    }
                }
            }
            .navigationTitle("Rename Category")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
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
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
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
        let all = Set(categoryManager.allCategories + feedCategories)
        return all.filter { $0 != selected }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
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
            loadFeedCategories()
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
            loadFeedCategories()
            selectedCategory = nil
        } catch {
            errorMessage = "Failed to move feeds: \(error.localizedDescription)"
        }
    }

    private func loadFeedCategories() {
        let descriptor = FetchDescriptor<Feed>()
        if let feeds = try? modelContext.fetch(descriptor) {
            feedCategories = Array(Set(feeds.map(\.category)))
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
            loadFeedCategories()
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
