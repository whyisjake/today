//
//  DatabaseMigration.swift
//  Today
//
//  Database migration utilities for updating existing data
//

import Foundation
import SwiftData

class DatabaseMigration {
    static let shared = DatabaseMigration()

    private let userDefaults = UserDefaults.standard
    private let texturizerMigrationKey = "hasRunTexturizerMigration_v1"
    private let categoryMigrationKey = "hasRunCategoryMigration_v1"

    private init() {}

    /// Run all pending migrations
    func runMigrations(modelContext: ModelContext) async {
        await texturizExistingArticles(modelContext: modelContext)
        await titleCaseFeedCategories(modelContext: modelContext)
    }

    /// Migrate existing articles to apply texturization
    private func texturizExistingArticles(modelContext: ModelContext) async {
        // Check if migration already ran
        guard !userDefaults.bool(forKey: texturizerMigrationKey) else {
            print("Texturizer migration already completed, skipping")
            return
        }

        print("Starting texturizer migration for existing articles...")

        await MainActor.run {
            let fetchDescriptor = FetchDescriptor<Article>()

            guard let articles = try? modelContext.fetch(fetchDescriptor) else {
                print("Failed to fetch articles for migration")
                return
            }

            print("Migrating \(articles.count) articles...")

            var migratedCount = 0
            for article in articles {
                // Texturize title
                article.title = article.title.texturize()

                // Texturize description if present
                if let description = article.articleDescription {
                    article.articleDescription = description.texturize()
                }

                // Texturize content if present
                if let content = article.content {
                    article.content = content.texturize()
                }

                // Texturize contentEncoded if present
                if let contentEncoded = article.contentEncoded {
                    article.contentEncoded = contentEncoded.texturize()
                }

                migratedCount += 1

                // Save in batches to avoid memory issues
                if migratedCount % 100 == 0 {
                    try? modelContext.save()
                    print("Migrated \(migratedCount) articles...")
                }
            }

            // Final save
            try? modelContext.save()

            // Mark migration as complete
            userDefaults.set(true, forKey: texturizerMigrationKey)

            print("Texturizer migration completed: \(migratedCount) articles updated")
        }
    }

    /// Migrate existing feed categories from lowercase to title case
    private func titleCaseFeedCategories(modelContext: ModelContext) async {
        // Check if migration already ran
        guard !userDefaults.bool(forKey: categoryMigrationKey) else {
            print("Category migration already completed, skipping")
            return
        }

        print("Starting category migration for existing feeds...")

        await MainActor.run {
            let fetchDescriptor = FetchDescriptor<Feed>()

            guard let feeds = try? modelContext.fetch(fetchDescriptor) else {
                print("Failed to fetch feeds for migration")
                return
            }

            print("Migrating \(feeds.count) feeds...")

            // Map of lowercase to title case for predefined categories
            let categoryMap: [String: String] = [
                "general": "General",
                "work": "Work",
                "social": "Social",
                "tech": "Tech",
                "news": "News",
                "politics": "Politics"
            ]

            var migratedCount = 0
            for feed in feeds {
                // Only update if it matches a predefined lowercase category
                if let titleCasedCategory = categoryMap[feed.category] {
                    feed.category = titleCasedCategory
                    migratedCount += 1
                }
                // Leave custom categories unchanged
            }

            // Save changes
            try? modelContext.save()

            // Mark migration as complete
            userDefaults.set(true, forKey: categoryMigrationKey)

            print("Category migration completed: \(migratedCount) feeds updated")
        }
    }
}
