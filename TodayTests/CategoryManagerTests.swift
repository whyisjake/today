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
}
