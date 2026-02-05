//
//  CategoryManager.swift
//  Today
//
//  Service for managing custom feed categories
//  Persists user-created categories to UserDefaults
//

import Foundation
import Combine

@MainActor
class CategoryManager: ObservableObject {
    static let shared = CategoryManager()

    /// Standard categories shown in pickers (matches FeedCategory.pickerCategories + Alt)
    static let pickerCategories = ["General", "Work", "Social", "Tech", "News", "Politics", "Alt"]

    /// All standard categories including legacy ones (matches FeedCategory.allCases + Alt)
    /// Used to prevent users from creating custom categories that conflict with standard ones
    static let allStandardCategories = ["General", "Work", "Social", "Tech", "News", "Politics", "Personal", "Comics", "Technology", "Alt"]

    @Published private(set) var customCategories: [String] = []

    private let customCategoriesKey = "com.today.customCategories"

    private init() {
        loadCustomCategories()
    }

    /// Load custom categories from UserDefaults
    private func loadCustomCategories() {
        if let stored = UserDefaults.standard.array(forKey: customCategoriesKey) as? [String] {
            customCategories = stored.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            print("📂 CategoryManager: Loaded \(customCategories.count) custom categories")
        } else {
            customCategories = []
        }
    }

    /// Save custom categories to UserDefaults
    private func saveCustomCategories() {
        UserDefaults.standard.set(customCategories, forKey: customCategoriesKey)
        print("💾 CategoryManager: Saved \(customCategories.count) custom categories")
    }

    /// Add a new custom category
    /// Returns true if added, false if it already exists or is a standard category
    func addCustomCategory(_ category: String) -> Bool {
        let trimmed = category.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            print("⚠️ CategoryManager: Cannot add empty category")
            return false
        }

        // Check if it's a standard category (case-insensitive)
        if Self.allStandardCategories.contains(where: { $0.lowercased() == trimmed.lowercased() }) {
            print("ℹ️ CategoryManager: '\(trimmed)' is a standard category, not adding to custom")
            return false
        }

        // Check if already exists (case-insensitive)
        if customCategories.contains(where: { $0.lowercased() == trimmed.lowercased() }) {
            print("ℹ️ CategoryManager: '\(trimmed)' already exists in custom categories")
            return false
        }

        customCategories.append(trimmed)
        customCategories.sort { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        saveCustomCategories()
        print("✅ CategoryManager: Added custom category '\(trimmed)'")
        return true
    }

    /// Remove a custom category
    func removeCustomCategory(_ category: String) {
        customCategories.removeAll { $0.lowercased() == category.lowercased() }
        saveCustomCategories()
        print("🗑️ CategoryManager: Removed custom category '\(category)'")
    }

    /// Get all categories (standard + custom) for display in pickers, sorted alphabetically
    var allCategories: [String] {
        (Self.pickerCategories + customCategories).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// Sync custom categories from existing feed categories
    /// Call this on app launch to ensure all existing custom categories are registered
    func syncCategories(from feedCategories: [String]) {
        var addedCount = 0
        for category in feedCategories {
            // Skip standard categories
            if Self.allStandardCategories.contains(where: { $0.lowercased() == category.lowercased() }) {
                continue
            }
            // Add if not already in custom categories
            if !customCategories.contains(where: { $0.lowercased() == category.lowercased() }) {
                customCategories.append(category)
                addedCount += 1
            }
        }
        if addedCount > 0 {
            customCategories.sort { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            saveCustomCategories()
            print("📂 CategoryManager: Synced \(addedCount) custom categories from existing feeds")
        }
    }
}
