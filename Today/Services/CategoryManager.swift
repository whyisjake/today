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

    /// Standard categories shown in pickers (matches FeedCategory.pickerCategories)
    static let pickerCategories = ["General", "Work", "Social", "Tech", "News", "Politics"]

    /// All standard categories including legacy ones (matches FeedCategory.allCases)
    /// Used to prevent users from creating custom categories that conflict with standard ones
    static let allStandardCategories = ["General", "Work", "Social", "Tech", "News", "Politics", "Personal", "Comics", "Technology"]

    @Published private(set) var customCategories: [String] = []

    private let customCategoriesKey = "com.today.customCategories"

    private init() {
        loadCustomCategories()
    }

    /// Load custom categories from UserDefaults
    private func loadCustomCategories() {
        if let stored = UserDefaults.standard.array(forKey: customCategoriesKey) as? [String] {
            customCategories = stored.sorted()
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
        customCategories.sort()
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

    /// Get all categories (standard + custom) for display in pickers
    var allCategories: [String] {
        Self.pickerCategories + customCategories.sorted()
    }
}
