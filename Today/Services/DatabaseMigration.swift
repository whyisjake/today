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
    private let deduplicateFeedsMigrationKey = "hasRunDeduplicateFeedsMigration_v2"

    private init() {}

    /// Run all pending migrations
    func runMigrations(modelContext: ModelContext) async {
        await texturizExistingArticles(modelContext: modelContext)
        await titleCaseFeedCategories(modelContext: modelContext)
        await deduplicateFeeds(modelContext: modelContext)
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

    /// Remove duplicate feeds created by OPML sync bug.
    /// Keeps the oldest feed (most articles/history) and deletes newer duplicates.
    private func deduplicateFeeds(modelContext: ModelContext) async {
        guard !userDefaults.bool(forKey: deduplicateFeedsMigrationKey) else {
            print("Deduplicate feeds migration already completed, skipping")
            return
        }

        print("Starting feed deduplication migration...")

        await MainActor.run {
            let fetchDescriptor = FetchDescriptor<Feed>()

            guard let feeds = try? modelContext.fetch(fetchDescriptor) else {
                print("Failed to fetch feeds for deduplication")
                return
            }

            // Group feeds by URL
            var feedsByURL: [String: [Feed]] = [:]
            for feed in feeds {
                feedsByURL[feed.url, default: []].append(feed)
            }

            var deletedCount = 0
            for (url, duplicates) in feedsByURL where duplicates.count > 1 {
                // Keep the feed with the most articles (or first if tied)
                let sorted = duplicates.sorted { ($0.articles?.count ?? 0) > ($1.articles?.count ?? 0) }
                let keeper = sorted[0]
                let toDelete = sorted.dropFirst()

                for duplicate in toDelete {
                    print("Removing duplicate feed: \(duplicate.title) (\(url))")
                    modelContext.delete(duplicate)
                    deletedCount += 1
                }

                // Ensure keeper is active
                keeper.isActive = true
            }

            try? modelContext.save()

            userDefaults.set(true, forKey: deduplicateFeedsMigrationKey)

            print("Feed deduplication completed: removed \(deletedCount) duplicate feeds")
        }
    }
}
