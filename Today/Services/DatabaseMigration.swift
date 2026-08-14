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
    private let derivedFieldsBackfillKey = "hasCompletedDerivedArticleFieldsBackfill_v1"
    private let redditRSSMigrationKey = "hasRunRedditJSONToRSSMigration_v1"

    /// Rows per batch. Bounded so a large store is worked through incrementally rather than
    /// in one long transaction, and large enough that a big store does not produce hundreds
    /// of saves — each save invalidates the article `@Query` observers.
    private let derivedFieldsBatchSize = 1_000

    private init() {}

    // MARK: - Derived article fields

    /// Fill in `plainTextDescription` and `isMinimalContentCached` for articles written
    /// before those fields existed.
    ///
    /// Runs on a background `ModelContext` — this used to live in `TodayView.task`, where it
    /// ran on the main actor on every appearance of the view and re-scanned the whole table
    /// even when there was nothing to do. A view is the wrong owner for a data migration.
    ///
    /// Idempotent and resumable: the completion flag is only set after a full pass, so an
    /// interrupted run simply starts over next launch and skips rows already filled in.
    ///
    /// One accepted imprecision: the cursor advances by `publishedDate`, so articles sharing
    /// the exact timestamp of a batch's last row can be skipped. That is harmless — a skipped
    /// article just keeps computing `hasMinimalContent` on demand via the accessor's
    /// fallback, which is correct, only slower for that one row.
    nonisolated func backfillDerivedArticleFields(container: ModelContainer) async {
        guard !userDefaults.bool(forKey: derivedFieldsBackfillKey) else { return }

        let interval = Perf.begin(.plainTextBackfill)
        defer { Perf.end(interval) }

        let context = ModelContext(container)
        var updated = 0
        var scanned = 0

        // Keyset pagination over publishedDate, which U2 indexed.
        //
        // The obvious approach — filter on "field IS NULL" and fetch a batch at a time —
        // is O(n²): every batch re-scans the rows already filled in, on an unindexed
        // column. Measured at roughly 240 rows/second on a 40k store, i.e. minutes of
        // background work with a @Query invalidation after each batch.
        //
        // Walking the indexed date column with a cursor instead makes each batch an index
        // seek, so the whole backfill is a single ordered pass.
        var cursor = Date.distantFuture

        while true {
            if Task.isCancelled {
                Perf.log("↩️ [Backfill] Cancelled after \(updated) updates; will resume")
                return
            }

            let upperBound = cursor
            var descriptor = FetchDescriptor<Article>(
                predicate: #Predicate { $0.publishedDate < upperBound },
                sortBy: [SortDescriptor(\Article.publishedDate, order: .reverse)]
            )
            descriptor.fetchLimit = derivedFieldsBatchSize

            let batch = (try? context.fetch(descriptor)) ?? []
            guard !batch.isEmpty else { break }

            var batchUpdated = 0
            for article in batch {
                if article.plainTextDescription == nil, let description = article.articleDescription {
                    article.plainTextDescription = description.htmlToPlainText
                    batchUpdated += 1
                }
                if article.isMinimalContentCached == nil {
                    article.isMinimalContentCached = Article.computeIsMinimalContent(
                        contentEncoded: article.contentEncoded,
                        content: article.content,
                        articleDescription: article.articleDescription
                    )
                    batchUpdated += 1
                }
            }

            if batchUpdated > 0 {
                do {
                    try context.save()
                } catch {
                    Perf.logError("❌ [Backfill] Save failed: \(error.localizedDescription)")
                    return // flag stays unset, so the next launch retries
                }
                updated += batchUpdated
            }

            scanned += batch.count
            cursor = batch[batch.count - 1].publishedDate

            if batch.count < derivedFieldsBatchSize { break }

            // Yield between batches so a long backfill does not monopolise a core or fire
            // @Query invalidations back to back while the user is reading.
            await Task.yield()
        }

        userDefaults.set(true, forKey: derivedFieldsBackfillKey)
        if updated > 0 {
            Perf.log("✅ [Backfill] Filled \(updated) derived fields across \(scanned) articles")
        }
    }

    /// Run all pending migrations
    func runMigrations(modelContext: ModelContext) async {
        await texturizExistingArticles(modelContext: modelContext)
        await titleCaseFeedCategories(modelContext: modelContext)
        await deduplicateFeeds(modelContext: modelContext)
        await migrateRedditFeedsToRSS(modelContext: modelContext)
    }

    /// Point stored Reddit feeds at `.rss` instead of `.json`.
    ///
    /// Reddit answers unauthenticated `.json` with 403 and an HTML block page, and has stated
    /// the shutdown is deliberate. Feeds already in the store still hold the `.json` URL, so
    /// changing `FeedURLNormalizer` alone would leave every existing subscriber broken —
    /// silently, since the failure looks like an empty feed.
    ///
    /// Only rewrites when the `.rss` form is not already subscribed, so a user who has both
    /// does not end up with a duplicate pair. Unlike the other migrations here, the completion
    /// flag is set only after a successful save, so a failed run retries next launch rather
    /// than marking itself done.
    private func migrateRedditFeedsToRSS(modelContext: ModelContext) async {
        guard !userDefaults.bool(forKey: redditRSSMigrationKey) else { return }

        await MainActor.run {
            let descriptor = FetchDescriptor<Feed>()
            guard let feeds = try? modelContext.fetch(descriptor) else {
                print("Reddit RSS migration: could not fetch feeds; will retry next launch")
                return
            }

            let existingURLs = Set(feeds.map(\.url))
            var rewritten = 0

            for feed in feeds where feed.url.contains("reddit.com/r/") && feed.url.hasSuffix(".json") {
                let rssURL = FeedURLNormalizer.convertRedditURLToRSS(feed.url)
                guard rssURL != feed.url else { continue }
                guard !existingURLs.contains(rssURL) else {
                    print("Reddit RSS migration: \(rssURL) already subscribed; leaving \(feed.url) alone")
                    continue
                }

                feed.url = rssURL
                // The cached validators describe the old endpoint's 403; keep them and the next
                // sync sends a conditional request the new endpoint never issued an ETag for.
                feed.httpEtag = nil
                feed.httpLastModified = nil
                feed.lastSyncError = nil
                feed.consecutiveSyncFailureCount = 0
                rewritten += 1
            }

            guard rewritten > 0 else {
                userDefaults.set(true, forKey: redditRSSMigrationKey)
                return
            }

            do {
                try modelContext.save()
                userDefaults.set(true, forKey: redditRSSMigrationKey)
                print("Reddit RSS migration: repointed \(rewritten) feed(s) from .json to .rss")
            } catch {
                print("Reddit RSS migration failed, will retry next launch: \(error.localizedDescription)")
            }
        }
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
