//
//  CategoryManagerTests.swift
//  TodayTests
//
//  Tests for CategoryManager service
//  Verifies custom category persistence, duplicate prevention, and standard category filtering
//

import XCTest
@testable import Today

@MainActor
final class CategoryManagerTests: XCTestCase {

    private let testKey = "com.today.customCategories"

    override func setUp() {
        super.setUp()
        // Clear any existing custom categories before each test
        UserDefaults.standard.removeObject(forKey: testKey)
    }

    override func tearDown() {
        // Clean up after each test
        UserDefaults.standard.removeObject(forKey: testKey)
        super.tearDown()
    }

    // MARK: - Helper to create fresh manager instance

    /// Creates a fresh CategoryManager for testing
    /// Note: Since CategoryManager.shared is a singleton, we test via UserDefaults directly
    /// and verify the manager's behavior through its public interface

    // MARK: - Add Custom Category Tests

    func testAddCustomCategorySuccess() {
        let manager = CategoryManager.shared
        // Clear existing categories
        UserDefaults.standard.removeObject(forKey: testKey)

        let result = manager.addCustomCategory("MyCustomCategory")

        XCTAssertTrue(result, "Should successfully add a new custom category")
        XCTAssertTrue(manager.customCategories.contains("MyCustomCategory"), "Custom categories should contain the added category")
    }

    func testAddCustomCategoryTrimsWhitespace() {
        let manager = CategoryManager.shared
        UserDefaults.standard.removeObject(forKey: testKey)

        let result = manager.addCustomCategory("  Trimmed Category  ")

        XCTAssertTrue(result, "Should successfully add category after trimming")
        XCTAssertTrue(manager.customCategories.contains("Trimmed Category"), "Should store trimmed category name")
        XCTAssertFalse(manager.customCategories.contains("  Trimmed Category  "), "Should not store untrimmed name")
    }

    func testAddEmptyCategoryFails() {
        let manager = CategoryManager.shared
        UserDefaults.standard.removeObject(forKey: testKey)

        let result = manager.addCustomCategory("")

        XCTAssertFalse(result, "Should reject empty category")
    }

    func testAddWhitespaceOnlyCategoryFails() {
        let manager = CategoryManager.shared
        UserDefaults.standard.removeObject(forKey: testKey)

        let result = manager.addCustomCategory("   ")

        XCTAssertFalse(result, "Should reject whitespace-only category")
    }

    // MARK: - Duplicate Prevention Tests

    func testDuplicateCategoryRejected() {
        let manager = CategoryManager.shared
        UserDefaults.standard.removeObject(forKey: testKey)

        _ = manager.addCustomCategory("Duplicate")
        let result = manager.addCustomCategory("Duplicate")

        XCTAssertFalse(result, "Should reject duplicate category")
        XCTAssertEqual(manager.customCategories.filter { $0 == "Duplicate" }.count, 1, "Should only have one instance")
    }

    func testDuplicateCategoryRejectedCaseInsensitive() {
        let manager = CategoryManager.shared
        UserDefaults.standard.removeObject(forKey: testKey)

        _ = manager.addCustomCategory("MyCategory")
        let result = manager.addCustomCategory("mycategory")

        XCTAssertFalse(result, "Should reject case-insensitive duplicate")
    }

    func testDuplicateCategoryRejectedMixedCase() {
        let manager = CategoryManager.shared
        UserDefaults.standard.removeObject(forKey: testKey)

        _ = manager.addCustomCategory("Gaming")
        let result = manager.addCustomCategory("GAMING")

        XCTAssertFalse(result, "Should reject GAMING when Gaming exists")
    }

    // MARK: - Standard Category Filtering Tests

    func testStandardCategoryRejectedGeneral() {
        let manager = CategoryManager.shared
        UserDefaults.standard.removeObject(forKey: testKey)

        let result = manager.addCustomCategory("General")

        XCTAssertFalse(result, "Should reject standard category 'General'")
    }

    func testStandardCategoryRejectedCaseInsensitive() {
        let manager = CategoryManager.shared
        UserDefaults.standard.removeObject(forKey: testKey)

        let result = manager.addCustomCategory("general")

        XCTAssertFalse(result, "Should reject 'general' (case-insensitive match to 'General')")
    }

    func testAllStandardCategoriesRejected() {
        let manager = CategoryManager.shared
        UserDefaults.standard.removeObject(forKey: testKey)

        // Use the static property to ensure test stays in sync
        let standardCategories = CategoryManager.allStandardCategories

        for category in standardCategories {
            let result = manager.addCustomCategory(category)
            XCTAssertFalse(result, "Should reject standard category '\(category)'")
        }

        // Also test lowercase variants
        for category in standardCategories {
            let result = manager.addCustomCategory(category.lowercased())
            XCTAssertFalse(result, "Should reject lowercase standard category '\(category.lowercased())'")
        }
    }

    // MARK: - Remove Category Tests

    func testRemoveCustomCategory() {
        let manager = CategoryManager.shared
        UserDefaults.standard.removeObject(forKey: testKey)

        _ = manager.addCustomCategory("ToBeRemoved")
        XCTAssertTrue(manager.customCategories.contains("ToBeRemoved"), "Category should exist before removal")

        manager.removeCustomCategory("ToBeRemoved")

        XCTAssertFalse(manager.customCategories.contains("ToBeRemoved"), "Category should be removed")
    }

    func testRemoveCustomCategoryCaseInsensitive() {
        let manager = CategoryManager.shared
        UserDefaults.standard.removeObject(forKey: testKey)

        _ = manager.addCustomCategory("MixedCase")
        manager.removeCustomCategory("mixedcase")

        XCTAssertFalse(manager.customCategories.contains("MixedCase"), "Should remove via case-insensitive match")
    }

    func testRemoveNonexistentCategoryNoOp() {
        let manager = CategoryManager.shared
        UserDefaults.standard.removeObject(forKey: testKey)

        _ = manager.addCustomCategory("Existing")
        let countBefore = manager.customCategories.count

        manager.removeCustomCategory("Nonexistent")

        XCTAssertEqual(manager.customCategories.count, countBefore, "Should not affect count when removing nonexistent category")
    }

    // MARK: - allCategories Property Tests

    func testAllCategoriesIncludesStandardCategories() {
        let manager = CategoryManager.shared
        UserDefaults.standard.removeObject(forKey: testKey)

        let allCategories = manager.allCategories

        XCTAssertTrue(allCategories.contains("General"), "Should include General")
        XCTAssertTrue(allCategories.contains("Work"), "Should include Work")
        XCTAssertTrue(allCategories.contains("Social"), "Should include Social")
        XCTAssertTrue(allCategories.contains("Tech"), "Should include Tech")
        XCTAssertTrue(allCategories.contains("News"), "Should include News")
        XCTAssertTrue(allCategories.contains("Politics"), "Should include Politics")
    }

    func testAllCategoriesExcludesLegacyCategories() {
        let manager = CategoryManager.shared
        UserDefaults.standard.removeObject(forKey: testKey)

        let allCategories = manager.allCategories

        // Legacy categories should not appear in picker
        XCTAssertFalse(allCategories.contains("Personal"), "Should not include legacy category Personal")
        XCTAssertFalse(allCategories.contains("Comics"), "Should not include legacy category Comics")
        XCTAssertFalse(allCategories.contains("Technology"), "Should not include legacy category Technology")
    }

    func testAllCategoriesIncludesCustomCategories() {
        let manager = CategoryManager.shared
        UserDefaults.standard.removeObject(forKey: testKey)

        _ = manager.addCustomCategory("Gaming")
        _ = manager.addCustomCategory("Finance")

        let allCategories = manager.allCategories

        XCTAssertTrue(allCategories.contains("Gaming"), "Should include custom category Gaming")
        XCTAssertTrue(allCategories.contains("Finance"), "Should include custom category Finance")
    }

    func testAllCategoriesCustomCategoriesSorted() {
        let manager = CategoryManager.shared
        UserDefaults.standard.removeObject(forKey: testKey)

        _ = manager.addCustomCategory("Zebra")
        _ = manager.addCustomCategory("Apple")
        _ = manager.addCustomCategory("Mango")

        let allCategories = manager.allCategories

        // Find indices of custom categories
        if let appleIndex = allCategories.firstIndex(of: "Apple"),
           let mangoIndex = allCategories.firstIndex(of: "Mango"),
           let zebraIndex = allCategories.firstIndex(of: "Zebra") {
            XCTAssertLessThan(appleIndex, mangoIndex, "Apple should come before Mango")
            XCTAssertLessThan(mangoIndex, zebraIndex, "Mango should come before Zebra")
        } else {
            XCTFail("Custom categories not found in allCategories")
        }
    }

    func testAllCategoriesStandardCategoriesFirst() {
        let manager = CategoryManager.shared
        UserDefaults.standard.removeObject(forKey: testKey)

        _ = manager.addCustomCategory("AAA") // Would sort first alphabetically

        let allCategories = manager.allCategories

        // Standard categories should come before custom ones
        if let generalIndex = allCategories.firstIndex(of: "General"),
           let aaaIndex = allCategories.firstIndex(of: "AAA") {
            XCTAssertLessThan(generalIndex, aaaIndex, "Standard category General should come before custom AAA")
        } else {
            XCTFail("Categories not found")
        }
    }

    // MARK: - Persistence Tests

    func testCategoriesPersistToUserDefaults() {
        let manager = CategoryManager.shared
        UserDefaults.standard.removeObject(forKey: testKey)

        _ = manager.addCustomCategory("Persisted")

        // Verify directly in UserDefaults
        let stored = UserDefaults.standard.array(forKey: testKey) as? [String]
        XCTAssertNotNil(stored, "Should store categories in UserDefaults")
        XCTAssertTrue(stored?.contains("Persisted") ?? false, "UserDefaults should contain the category")
    }

    func testRemovalPersistsToUserDefaults() {
        let manager = CategoryManager.shared
        UserDefaults.standard.removeObject(forKey: testKey)

        _ = manager.addCustomCategory("WillBeRemoved")
        manager.removeCustomCategory("WillBeRemoved")

        let stored = UserDefaults.standard.array(forKey: testKey) as? [String]
        XCTAssertFalse(stored?.contains("WillBeRemoved") ?? true, "Removal should persist to UserDefaults")
    }

    // MARK: - Sync Categories Tests

    func testSyncCategoriesAddsCustomCategories() {
        let manager = CategoryManager.shared
        UserDefaults.standard.removeObject(forKey: testKey)

        let feedCategories = ["General", "a8c", "MyCustom", "Tech"]
        manager.syncCategories(from: feedCategories)

        XCTAssertTrue(manager.customCategories.contains("a8c"), "Should add custom category 'a8c'")
        XCTAssertTrue(manager.customCategories.contains("MyCustom"), "Should add custom category 'MyCustom'")
        XCTAssertFalse(manager.customCategories.contains("General"), "Should not add standard category 'General'")
        XCTAssertFalse(manager.customCategories.contains("Tech"), "Should not add standard category 'Tech'")
    }

    func testSyncCategoriesSkipsDuplicates() {
        let manager = CategoryManager.shared
        UserDefaults.standard.removeObject(forKey: testKey)

        _ = manager.addCustomCategory("Existing")
        manager.syncCategories(from: ["Existing", "existing", "EXISTING"])

        let count = manager.customCategories.filter { $0.lowercased() == "existing" }.count
        XCTAssertEqual(count, 1, "Should only have one instance of 'Existing'")
    }

    func testSyncCategoriesPersists() {
        let manager = CategoryManager.shared
        UserDefaults.standard.removeObject(forKey: testKey)

        manager.syncCategories(from: ["CustomFromFeed"])

        let stored = UserDefaults.standard.array(forKey: testKey) as? [String]
        XCTAssertTrue(stored?.contains("CustomFromFeed") ?? false, "Synced categories should persist to UserDefaults")
    }

    // MARK: - Rename Category Tests

    func testRenameCategorySuccess() {
        let manager = CategoryManager.shared
        UserDefaults.standard.removeObject(forKey: testKey)

        _ = manager.addCustomCategory("OldName")
        let result = manager.renameCategory(from: "OldName", to: "NewName")

        XCTAssertEqual(result, "NewName", "Should return new category name")
        XCTAssertFalse(manager.customCategories.contains("OldName"), "Old category should be removed")
        XCTAssertTrue(manager.customCategories.contains("NewName"), "New category should be added")
    }

    func testRenameCategoryTrimsWhitespace() {
        let manager = CategoryManager.shared
        UserDefaults.standard.removeObject(forKey: testKey)

        _ = manager.addCustomCategory("Original")
        let result = manager.renameCategory(from: "Original", to: "  Trimmed  ")

        XCTAssertEqual(result, "Trimmed", "Should return trimmed name")
        XCTAssertTrue(manager.customCategories.contains("Trimmed"), "Should store trimmed name")
    }

    func testRenameCategoryToEmptyFails() {
        let manager = CategoryManager.shared
        UserDefaults.standard.removeObject(forKey: testKey)

        _ = manager.addCustomCategory("Original")
        let result = manager.renameCategory(from: "Original", to: "")

        XCTAssertNil(result, "Should reject empty new name")
        XCTAssertTrue(manager.customCategories.contains("Original"), "Should keep original category")
    }

    func testRenameCategoryToWhitespaceFails() {
        let manager = CategoryManager.shared
        UserDefaults.standard.removeObject(forKey: testKey)

        _ = manager.addCustomCategory("Original")
        let result = manager.renameCategory(from: "Original", to: "   ")

        XCTAssertNil(result, "Should reject whitespace-only new name")
        XCTAssertTrue(manager.customCategories.contains("Original"), "Should keep original category")
    }

    func testRenameCategoryToExistingCustomFails() {
        let manager = CategoryManager.shared
        UserDefaults.standard.removeObject(forKey: testKey)

        _ = manager.addCustomCategory("Category1")
        _ = manager.addCustomCategory("Category2")
        let result = manager.renameCategory(from: "Category1", to: "Category2")

        XCTAssertNil(result, "Should reject rename to existing custom category")
        XCTAssertTrue(manager.customCategories.contains("Category1"), "Should keep original category")
        XCTAssertTrue(manager.customCategories.contains("Category2"), "Should keep conflicting category")
    }

    func testRenameCategoryToStandardFails() {
        let manager = CategoryManager.shared
        UserDefaults.standard.removeObject(forKey: testKey)

        _ = manager.addCustomCategory("MyCategory")
        let result = manager.renameCategory(from: "MyCategory", to: "General")

        XCTAssertNil(result, "Should reject rename to standard category")
        XCTAssertTrue(manager.customCategories.contains("MyCategory"), "Should keep original category")
    }

    func testRenameCategoryStandardCategory() {
        let manager = CategoryManager.shared
        UserDefaults.standard.removeObject(forKey: testKey)

        // Standard categories can be "renamed" by caller updating feeds, but manager doesn't track them
        let result = manager.renameCategory(from: "General", to: "MyGeneral")

        XCTAssertEqual(result, "MyGeneral", "Should return new name for standard category")
        // Standard category rename doesn't affect customCategories
        XCTAssertFalse(manager.customCategories.contains("General"), "Standard category not in custom list")
    }

    func testRenameCategoryCaseChange() {
        let manager = CategoryManager.shared
        UserDefaults.standard.removeObject(forKey: testKey)

        _ = manager.addCustomCategory("gaming")
        let result = manager.renameCategory(from: "gaming", to: "Gaming")

        XCTAssertEqual(result, "Gaming", "Should allow case change")
        XCTAssertTrue(manager.customCategories.contains("Gaming"), "Should have new case")
        XCTAssertFalse(manager.customCategories.contains("gaming"), "Should not have old case")
    }

    func testRenameCategoryPersists() {
        let manager = CategoryManager.shared
        UserDefaults.standard.removeObject(forKey: testKey)

        _ = manager.addCustomCategory("Before")
        _ = manager.renameCategory(from: "Before", to: "After")

        let stored = UserDefaults.standard.array(forKey: testKey) as? [String]
        XCTAssertTrue(stored?.contains("After") ?? false, "Renamed category should persist")
        XCTAssertFalse(stored?.contains("Before") ?? true, "Old name should not persist")
    }

    // MARK: - Delete Category Tests

    func testDeleteCategoryReturnsDefaultCategory() {
        let manager = CategoryManager.shared
        UserDefaults.standard.removeObject(forKey: testKey)

        _ = manager.addCustomCategory("ToDelete")
        let result = manager.deleteCategory("ToDelete")

        XCTAssertEqual(result, "General", "Should return default category 'General'")
    }

    func testDeleteCategoryRemovesFromCustom() {
        let manager = CategoryManager.shared
        UserDefaults.standard.removeObject(forKey: testKey)

        _ = manager.addCustomCategory("ToDelete")
        _ = manager.deleteCategory("ToDelete")

        XCTAssertFalse(manager.customCategories.contains("ToDelete"), "Category should be removed from custom list")
    }

    func testDeleteCategoryCustomDefaultCategory() {
        let manager = CategoryManager.shared
        UserDefaults.standard.removeObject(forKey: testKey)

        _ = manager.addCustomCategory("ToDelete")
        let result = manager.deleteCategory("ToDelete", defaultCategory: "Work")

        XCTAssertEqual(result, "Work", "Should return custom default category")
    }

    func testDeleteStandardCategory() {
        let manager = CategoryManager.shared
        UserDefaults.standard.removeObject(forKey: testKey)

        // Deleting a standard category doesn't affect customCategories, just returns default
        let result = manager.deleteCategory("Tech")

        XCTAssertEqual(result, "General", "Should return default category")
        XCTAssertTrue(manager.customCategories.isEmpty, "Should not affect custom categories")
    }

    func testDeleteCategoryPersists() {
        let manager = CategoryManager.shared
        UserDefaults.standard.removeObject(forKey: testKey)

        _ = manager.addCustomCategory("ToDelete")
        _ = manager.deleteCategory("ToDelete")

        let stored = UserDefaults.standard.array(forKey: testKey) as? [String]
        XCTAssertFalse(stored?.contains("ToDelete") ?? true, "Deleted category should not persist")
    }

    // MARK: - Merge Categories Tests

    func testMergeCategoriesSuccess() {
        let manager = CategoryManager.shared
        UserDefaults.standard.removeObject(forKey: testKey)

        _ = manager.addCustomCategory("Source")
        _ = manager.addCustomCategory("Target")
        let result = manager.mergeCategories(from: "Source", to: "Target")

        XCTAssertTrue(result, "Merge should succeed")
        XCTAssertFalse(manager.customCategories.contains("Source"), "Source category should be removed")
        XCTAssertTrue(manager.customCategories.contains("Target"), "Target category should remain")
    }

    func testMergeCategoriesCreatesTargetIfNeeded() {
        let manager = CategoryManager.shared
        UserDefaults.standard.removeObject(forKey: testKey)

        _ = manager.addCustomCategory("Source")
        let result = manager.mergeCategories(from: "Source", to: "NewTarget")

        XCTAssertTrue(result, "Merge should succeed")
        XCTAssertFalse(manager.customCategories.contains("Source"), "Source should be removed")
        XCTAssertTrue(manager.customCategories.contains("NewTarget"), "Target should be created")
    }

    func testMergeCategoriesIntoStandard() {
        let manager = CategoryManager.shared
        UserDefaults.standard.removeObject(forKey: testKey)

        _ = manager.addCustomCategory("Source")
        let result = manager.mergeCategories(from: "Source", to: "General")

        XCTAssertTrue(result, "Merge into standard category should succeed")
        XCTAssertFalse(manager.customCategories.contains("Source"), "Source should be removed")
        XCTAssertFalse(manager.customCategories.contains("General"), "General should not be in custom categories")
    }

    func testMergeCategoriesTrimsWhitespace() {
        let manager = CategoryManager.shared
        UserDefaults.standard.removeObject(forKey: testKey)

        _ = manager.addCustomCategory("Source")
        let result = manager.mergeCategories(from: "  Source  ", to: "  Target  ")

        XCTAssertTrue(result, "Merge should succeed with trimmed names")
        XCTAssertTrue(manager.customCategories.contains("Target"), "Target should be added (trimmed)")
    }

    func testMergeCategoriesEmptySourceFails() {
        let manager = CategoryManager.shared
        UserDefaults.standard.removeObject(forKey: testKey)

        let result = manager.mergeCategories(from: "", to: "Target")

        XCTAssertFalse(result, "Should reject empty source")
    }

    func testMergeCategoriesEmptyTargetFails() {
        let manager = CategoryManager.shared
        UserDefaults.standard.removeObject(forKey: testKey)

        _ = manager.addCustomCategory("Source")
        let result = manager.mergeCategories(from: "Source", to: "")

        XCTAssertFalse(result, "Should reject empty target")
        XCTAssertTrue(manager.customCategories.contains("Source"), "Source should remain")
    }

    func testMergeCategoriesIntoItselfFails() {
        let manager = CategoryManager.shared
        UserDefaults.standard.removeObject(forKey: testKey)

        _ = manager.addCustomCategory("Same")
        let result = manager.mergeCategories(from: "Same", to: "Same")

        XCTAssertFalse(result, "Should reject merge into itself")
        XCTAssertTrue(manager.customCategories.contains("Same"), "Category should remain")
    }

    func testMergeCategoriesIntoItselfCaseInsensitiveFails() {
        let manager = CategoryManager.shared
        UserDefaults.standard.removeObject(forKey: testKey)

        _ = manager.addCustomCategory("Gaming")
        let result = manager.mergeCategories(from: "Gaming", to: "gaming")

        XCTAssertFalse(result, "Should reject case-insensitive merge into itself")
        XCTAssertTrue(manager.customCategories.contains("Gaming"), "Category should remain")
    }

    func testMergeCategoriesPersists() {
        let manager = CategoryManager.shared
        UserDefaults.standard.removeObject(forKey: testKey)

        _ = manager.addCustomCategory("Source")
        _ = manager.addCustomCategory("Target")
        _ = manager.mergeCategories(from: "Source", to: "Target")

        let stored = UserDefaults.standard.array(forKey: testKey) as? [String]
        XCTAssertFalse(stored?.contains("Source") ?? true, "Source should not persist")
        XCTAssertTrue(stored?.contains("Target") ?? false, "Target should persist")
    }
}
