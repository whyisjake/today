//
//  FeedManager.swift
//  Today
//
//  Service for managing RSS feed subscriptions and syncing
//

import Foundation
import SwiftData
import Combine

@MainActor
class FeedManager: ObservableObject {
    private let modelContext: ModelContext

    // UserDefaults key for persistent last sync tracking
    private static let lastGlobalSyncKey = "com.today.lastGlobalSyncDate"

    @Published var isSyncing = false
    @Published var lastSyncDate: Date?
    @Published var syncError: String?

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        // Load last sync date from persistent storage
        self.lastSyncDate = UserDefaults.standard.object(forKey: Self.lastGlobalSyncKey) as? Date
    }

    /// Check if content needs syncing (hasn't been synced in the last 2 hours)
    static func needsSync() -> Bool {
        guard let lastSync = UserDefaults.standard.object(forKey: lastGlobalSyncKey) as? Date else {
            return true // Never synced, needs sync
        }

        let twoHoursAgo = Date().addingTimeInterval(-2 * 60 * 60)
        return lastSync < twoHoursAgo
    }

    /// Get last sync date from persistent storage
    static func getLastSyncDate() -> Date? {
        return UserDefaults.standard.object(forKey: lastGlobalSyncKey) as? Date
    }

    /// Add a new RSS feed subscription
    func addFeed(url: String, category: String = "general") async throws -> Feed {
        // Convert Reddit URLs to JSON format
        let feedURL = convertRedditURLToJSON(url)

        // Fetch the feed to validate and get metadata
        let (feedTitle, feedDescription, _) = try await fetchFeed(url: feedURL)

        let feed = Feed(
            title: feedTitle.isEmpty ? feedURL : feedTitle,
            url: feedURL,
            feedDescription: feedDescription.isEmpty ? nil : feedDescription,
            category: category
        )

        modelContext.insert(feed)
        try modelContext.save()

        // Fetch initial articles
        try await syncFeed(feed)

        return feed
    }

    /// Convert Reddit URLs to JSON format
    /// Handles: reddit.com/r/subreddit.rss -> reddit.com/r/subreddit.json
    /// Also: reddit.com/r/subreddit -> reddit.com/r/subreddit.json
    private func convertRedditURLToJSON(_ url: String) -> String {
        var urlString = url

        // Convert .rss to .json
        if urlString.contains("reddit.com/r/") && urlString.hasSuffix(".rss") {
            urlString = urlString.replacingOccurrences(of: ".rss", with: ".json")
        }
        // Add .json if it's a subreddit URL without extension
        else if urlString.contains("reddit.com/r/") && !urlString.hasSuffix(".json") {
            // Remove trailing slash if present
            if urlString.hasSuffix("/") {
                urlString = String(urlString.dropLast())
            }
            urlString += ".json"
        }

        return urlString
    }

    /// Fetch feed using appropriate parser (RSS or Reddit JSON)
    private func fetchFeed(url: String) async throws -> (feedTitle: String, feedDescription: String, articles: [RSSParser.ParsedArticle]) {
        if isRedditJSON(url) {
            // Use Reddit JSON parser
            guard let feedURL = URL(string: url) else {
                throw FeedError.invalidURL
            }

            var request = URLRequest(url: feedURL)
            request.setValue("ios:com.today.app:v1.0 (by /u/TodayApp)", forHTTPHeaderField: "User-Agent")

            let (data, _) = try await URLSession.shared.data(for: request)

            let parser = RedditJSONParser()
            let (feedTitle, feedDescription, redditPosts) = try parser.parseSubredditFeed(data: data)

            // Convert Reddit posts to ParsedArticle format
            let articles = redditPosts.map { $0.toArticle() }

            return (feedTitle, feedDescription, articles)
        } else {
            // Use RSS parser
            return try await RSSFeedService.shared.fetchFeed(url: url)
        }
    }

    /// Check if URL is a Reddit JSON feed
    private func isRedditJSON(_ url: String) -> Bool {
        return url.contains("reddit.com") && url.hasSuffix(".json")
    }

    /// Sync a specific feed
    func syncFeed(_ feed: Feed) async throws {
        let (_, _, parsedArticles) = try await fetchFeed(url: feed.url)

        // Get existing article GUIDs to avoid duplicates
        let existingGUIDs = Set(feed.articles?.map { $0.guid } ?? [])

        // Add new articles
        for parsedArticle in parsedArticles {
            if !existingGUIDs.contains(parsedArticle.guid) {
                let article = Article(
                    title: parsedArticle.title,
                    link: parsedArticle.link,
                    articleDescription: parsedArticle.description,
                    content: parsedArticle.content,
                    contentEncoded: parsedArticle.contentEncoded,
                    imageUrl: parsedArticle.imageUrl,
                    publishedDate: parsedArticle.publishedDate ?? Date(),
                    author: parsedArticle.author,
                    guid: parsedArticle.guid,
                    feed: feed,
                    redditSubreddit: parsedArticle.redditSubreddit,
                    redditCommentsUrl: parsedArticle.redditCommentsUrl,
                    redditPostId: parsedArticle.redditPostId
                )

                modelContext.insert(article)
            }
        }

        feed.lastFetched = Date()
        try modelContext.save()
    }

    enum FeedError: LocalizedError {
        case invalidURL

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "Invalid feed URL"
            }
        }
    }

    /// Sync all active feeds
    func syncAllFeeds() async {
        isSyncing = true
        syncError = nil

        let syncStartTime = Date()
        print("📡 Starting feed sync at \(syncStartTime.formatted(date: .omitted, time: .standard))")

        defer {
            isSyncing = false
            let duration = Date().timeIntervalSince(syncStartTime)
            print("✅ Feed sync completed in \(String(format: "%.1f", duration))s")
        }

        do {
            let descriptor = FetchDescriptor<Feed>(
                predicate: #Predicate<Feed> { $0.isActive }
            )
            let feeds = try modelContext.fetch(descriptor)
            print("📋 Syncing \(feeds.count) active feeds")

            var successCount = 0
            var failureCount = 0

            for feed in feeds {
                do {
                    try await syncFeed(feed)
                    successCount += 1
                } catch {
                    failureCount += 1
                    print("❌ Error syncing feed \(feed.title): \(error.localizedDescription)")
                    // Continue with other feeds even if one fails
                }
            }

            print("📊 Sync results: \(successCount) succeeded, \(failureCount) failed")
            
            // Only update lastSyncDate if at least one feed synced successfully
            if successCount > 0 {
                lastSyncDate = syncStartTime
                UserDefaults.standard.set(syncStartTime, forKey: Self.lastGlobalSyncKey)
                print("✅ Updated last sync date (synced \(successCount)/\(feeds.count) feeds)")
            } else {
                print("⚠️ Not updating last sync date - all feeds failed to sync")
            }
        } catch {
            syncError = error.localizedDescription
            print("❌ Sync error: \(error.localizedDescription)")
        }
    }

    /// Delete a feed and all its articles
    func deleteFeed(_ feed: Feed) throws {
        modelContext.delete(feed)
        try modelContext.save()
    }
}
