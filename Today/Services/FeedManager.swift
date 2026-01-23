//
//  FeedManager.swift
//  Today
//
//  Service for managing RSS feed subscriptions and syncing
//

import Foundation
import SwiftData
import Combine

/// Result of a conditional feed fetch
enum FeedFetchResult {
    /// Feed was fetched and has new content
    case fetched(
        feedTitle: String,
        feedDescription: String,
        articles: [RSSParser.ParsedArticle],
        lastModified: String?,
        etag: String?,
        finalURL: URL?
    )

    /// Feed was not modified (304 response)
    /// Includes redirect information in case URL was permanently redirected before 304
    case notModified(
        lastModified: String?,
        etag: String?,
        finalURL: URL?
    )
}

@MainActor
class FeedManager: ObservableObject {
    private let modelContext: ModelContext

    // UserDefaults key for persistent last sync tracking
    private static let lastGlobalSyncKey = "com.today.lastGlobalSyncDate"
    
    // Global sync state to prevent concurrent syncs across multiple FeedManager instances
    // MainActor-isolated to ensure thread-safe access
    @MainActor private static var globalSyncInProgress = false

    @Published var isSyncing = false
    @Published var lastSyncDate: Date?
    @Published var syncError: String?
    @Published var syncProgress: String?

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
    
    /// Check if a sync is currently in progress (across all FeedManager instances)
    @MainActor static func isSyncInProgress() -> Bool {
        return globalSyncInProgress
    }

    /// Add a new RSS feed subscription
    func addFeed(url: String, category: String = "general") async throws -> Feed {
        // Convert Reddit URLs to JSON format
        let feedURL = convertRedditURLToJSON(url)

        // Fetch the feed to validate and get metadata (no cache headers for new feed)
        let result = try await fetchFeed(url: feedURL)

        // Extract feed info from result
        let feedTitle: String
        let feedDescription: String
        let initialLastModified: String?
        let initialEtag: String?
        let actualURL: String

        switch result {
        case .fetched(let title, let desc, _, let lastMod, let etag, let finalURL):
            feedTitle = title
            feedDescription = desc
            initialLastModified = lastMod
            initialEtag = etag
            // Use final URL if there was a permanent redirect
            actualURL = finalURL?.absoluteString ?? feedURL
        case .notModified(let lastModified, let etag, let finalURL):
            // Shouldn't happen for a new feed, but handle gracefully
            feedTitle = feedURL
            feedDescription = ""
            initialLastModified = lastModified
            initialEtag = etag
            actualURL = finalURL?.absoluteString ?? feedURL
        }

        let feed = Feed(
            title: feedTitle.isEmpty ? actualURL : feedTitle,
            url: actualURL,
            feedDescription: feedDescription.isEmpty ? nil : feedDescription,
            category: category
        )

        // Store initial cache headers
        feed.httpLastModified = initialLastModified
        feed.httpEtag = initialEtag

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

    /// Fetch feed using appropriate parser (RSS, JSON Feed, or Reddit JSON)
    /// Supports conditional GET with If-Modified-Since and If-None-Match headers
    private func fetchFeed(
        url: String,
        lastModified: String? = nil,
        etag: String? = nil
    ) async throws -> FeedFetchResult {
        if isRedditJSON(url) {
            // Use Reddit JSON parser
            guard let feedURL = URL(string: url) else {
                throw FeedError.invalidURL
            }

            let response = try await ConditionalHTTPClient.conditionalFetch(
                url: feedURL,
                lastModified: lastModified,
                etag: etag,
                additionalHeaders: ["User-Agent": "ios:com.today.app:v1.0 (by /u/TodayApp)"]
            )

            // Handle 304 Not Modified
            guard response.wasModified, let data = response.data else {
                return .notModified(
                    lastModified: lastModified,
                    etag: etag,
                    finalURL: response.hadPermanentRedirect ? response.finalURL : nil
                )
            }

            // Parse the Reddit JSON response
            let parser = RedditJSONParser()
            let (feedTitle, feedDescription, redditPosts) = try parser.parseSubredditFeed(data: data)

            // Convert Reddit posts to ParsedArticle format
            let articles = redditPosts.map { $0.toArticle() }

            return FeedFetchResult.fetched(
                feedTitle: feedTitle,
                feedDescription: feedDescription,
                articles: articles,
                lastModified: response.lastModified,
                etag: response.etag,
                finalURL: response.hadPermanentRedirect ? response.finalURL : nil
            )
        } else if isJSONFeed(url) {
            // Use JSON Feed parser for .json or .jsonfeed URLs
            return try await fetchJSONFeed(url: url, lastModified: lastModified, etag: etag)
        } else {
            // Try RSS parser first, fallback to JSON Feed if it fails
            return try await fetchWithFallback(url: url, lastModified: lastModified, etag: etag)
        }
    }

    /// Check if URL is a Reddit JSON feed
    private func isRedditJSON(_ url: String) -> Bool {
        return url.contains("reddit.com") && url.hasSuffix(".json")
    }
    
    /// Check if URL is likely a JSON Feed based on extension
    /// Excludes Reddit URLs which have their own parser
    private func isJSONFeed(_ url: String) -> Bool {
        // Don't treat Reddit URLs as JSON Feed - they have their own parser
        if url.contains("reddit.com") {
            return false
        }
        
        let lowercased = url.lowercased()
        // Match common JSON Feed URL patterns:
        // - Ends with .json (e.g., /feed.json)
        // - Ends with .jsonfeed (e.g., /newest.jsonfeed)
        // - Contains feed.json in path
        // - Contains /feeds/json (e.g., daringfireball.net/feeds/json)
        return lowercased.hasSuffix(".json") || 
               lowercased.hasSuffix(".jsonfeed") ||
               lowercased.contains("feed.json") ||
               lowercased.contains("/feeds/json")
    }
    
    /// Fetch a JSON Feed with conditional GET support
    private func fetchJSONFeed(
        url: String,
        lastModified: String? = nil,
        etag: String? = nil
    ) async throws -> FeedFetchResult {
        guard let feedURL = URL(string: url) else {
            throw FeedError.invalidURL
        }

        let response = try await ConditionalHTTPClient.conditionalFetch(
            url: feedURL,
            lastModified: lastModified,
            etag: etag
        )

        // Handle 304 Not Modified
        guard response.wasModified, let data = response.data else {
            return .notModified(
                lastModified: lastModified,
                etag: etag,
                finalURL: response.hadPermanentRedirect ? response.finalURL : nil
            )
        }

        // Parse the JSON Feed response
        let parser = JSONFeedParser()
        guard try parser.parse(data: data) else {
            throw FeedError.parsingFailed
        }

        return FeedFetchResult.fetched(
            feedTitle: parser.feedTitle,
            feedDescription: parser.feedDescription,
            articles: parser.articles,
            lastModified: response.lastModified,
            etag: response.etag,
            finalURL: response.hadPermanentRedirect ? response.finalURL : nil
        )
    }
    
    /// Fetch feed trying RSS first, then JSON Feed as fallback
    private func fetchWithFallback(
        url: String,
        lastModified: String? = nil,
        etag: String? = nil
    ) async throws -> FeedFetchResult {
        guard let feedURL = URL(string: url) else {
            throw FeedError.invalidURL
        }

        let response = try await ConditionalHTTPClient.conditionalFetch(
            url: feedURL,
            lastModified: lastModified,
            etag: etag
        )

        // Handle 304 Not Modified
        guard response.wasModified, let data = response.data else {
            return .notModified(
                lastModified: lastModified,
                etag: etag,
                finalURL: response.hadPermanentRedirect ? response.finalURL : nil
            )
        }

        // Try RSS parser first
        let rssParser = RSSParser()
        if rssParser.parse(data: data) && !rssParser.articles.isEmpty {
            return FeedFetchResult.fetched(
                feedTitle: rssParser.feedTitle,
                feedDescription: rssParser.feedDescription,
                articles: rssParser.articles,
                lastModified: response.lastModified,
                etag: response.etag,
                finalURL: response.hadPermanentRedirect ? response.finalURL : nil
            )
        }

        // Fallback to JSON Feed parser
        let jsonParser = JSONFeedParser()
        if let parsed = try? jsonParser.parse(data: data), parsed {
            return FeedFetchResult.fetched(
                feedTitle: jsonParser.feedTitle,
                feedDescription: jsonParser.feedDescription,
                articles: jsonParser.articles,
                lastModified: response.lastModified,
                etag: response.etag,
                finalURL: response.hadPermanentRedirect ? response.finalURL : nil
            )
        }

        // If both fail, throw parsing error
        throw FeedError.parsingFailed
    }

    /// Sync a specific feed
    func syncFeed(_ feed: Feed) async throws {
        let result = try await fetchFeed(
            url: feed.url,
            lastModified: feed.httpLastModified,
            etag: feed.httpEtag
        )

        switch result {
        case .fetched(_, _, let parsedArticles, let lastModified, let etag, let finalURL):
            updateFeedWithArticles(feed, parsedArticles: parsedArticles)
            feed.httpLastModified = lastModified
            feed.httpEtag = etag
            // Update URL if there was a permanent redirect
            if let newURL = finalURL {
                print("📋 Updating feed URL from \(feed.url) to \(newURL.absoluteString) (301 redirect)")
                feed.url = newURL.absoluteString
            }
        case .notModified(let lastModified, let etag, let finalURL):
            // Feed hasn't changed, just update lastFetched and cache headers
            feed.lastFetched = Date()
            feed.httpLastModified = lastModified
            feed.httpEtag = etag
            // Update URL if there was a permanent redirect
            if let newURL = finalURL {
                print("📋 Updating feed URL from \(feed.url) to \(newURL.absoluteString) (301 redirect before 304)")
                feed.url = newURL.absoluteString
            }
            print("📋 Feed \(feed.title) not modified (304)")
        }
    }

    /// Sync a feed by its persistent ID (Swift 6 safe - avoids passing Feed across actor boundaries)
    func syncFeedByID(_ feedID: PersistentIdentifier) async throws {
        // Get the feed info (we're on MainActor since FeedManager is @MainActor)
        guard let feed = modelContext.model(for: feedID) as? Feed else {
            throw FeedError.invalidURL
        }
        let feedURL = feed.url
        let cachedLastModified = feed.httpLastModified
        let cachedEtag = feed.httpEtag

        // Perform network fetch with conditional headers (async - may hop off MainActor for network IO)
        let result = try await fetchFeed(url: feedURL, lastModified: cachedLastModified, etag: cachedEtag)

        // Update the model (we're back on MainActor after await)
        // Re-fetch the feed in case it was modified during the network call
        guard let updatedFeed = modelContext.model(for: feedID) as? Feed else {
            return
        }

        switch result {
        case .fetched(_, _, let parsedArticles, let lastModified, let etag, let finalURL):
            updateFeedWithArticles(updatedFeed, parsedArticles: parsedArticles)
            updatedFeed.httpLastModified = lastModified
            updatedFeed.httpEtag = etag
            // Update URL if there was a permanent redirect
            if let newURL = finalURL {
                print("📋 Updating feed URL from \(updatedFeed.url) to \(newURL.absoluteString) (301 redirect)")
                updatedFeed.url = newURL.absoluteString
            }
        case .notModified(let lastModified, let etag, let finalURL):
            // Feed hasn't changed, just update lastFetched and cache headers
            updatedFeed.lastFetched = Date()
            updatedFeed.httpLastModified = lastModified
            updatedFeed.httpEtag = etag
            // Update URL if there was a permanent redirect
            if let newURL = finalURL {
                print("📋 Updating feed URL from \(updatedFeed.url) to \(newURL.absoluteString) (301 redirect before 304)")
                updatedFeed.url = newURL.absoluteString
            }
            print("📋 Feed \(updatedFeed.title) not modified (304)")
        }
    }

    /// Update a feed with parsed articles (must be called on MainActor)
    private func updateFeedWithArticles(_ feed: Feed, parsedArticles: [RSSParser.ParsedArticle]) {
        // Get existing articles
        let feedArticles = feed.articles ?? []

        // Get existing article GUIDs to check for duplicates
        let existingGUIDs = Set(feedArticles.map { $0.guid })

        // Update existing articles with missing audio data
        for existingArticle in feedArticles {
            if existingArticle.audioUrl == nil {
                // Find matching parsed article
                if let parsedArticle = parsedArticles.first(where: { $0.guid == existingArticle.guid }),
                   let audioUrl = parsedArticle.audioUrl {
                    existingArticle.audioUrl = audioUrl
                    existingArticle.audioDuration = parsedArticle.audioDuration
                    existingArticle.audioType = parsedArticle.audioType
                }
            }
        }

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
                    redditPostId: parsedArticle.redditPostId,
                    audioUrl: parsedArticle.audioUrl,
                    audioDuration: parsedArticle.audioDuration,
                    audioType: parsedArticle.audioType
                )

                modelContext.insert(article)
            }
        }

        feed.lastFetched = Date()
        // Note: Don't save here - syncAllFeeds batches saves to reduce UI jank
    }

    /// Save pending changes to reduce UI update frequency
    private func saveChanges() {
        try? modelContext.save()
    }

    enum FeedError: LocalizedError {
        case invalidURL
        case parsingFailed

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "Invalid feed URL"
            case .parsingFailed:
                return "Failed to parse feed"
            }
        }
    }

    /// Sync all active feeds with batched concurrent processing
    func syncAllFeeds() async {
        // Check if a sync is already in progress globally
        guard !Self.globalSyncInProgress else {
            print("⚠️ Sync already in progress, skipping concurrent sync request")
            return
        }

        Self.globalSyncInProgress = true
        isSyncing = true
        syncError = nil
        syncProgress = nil

        let syncStartTime = Date()
        print("📡 Starting feed sync at \(syncStartTime.formatted(date: .omitted, time: .standard))")

        defer {
            Self.globalSyncInProgress = false
            isSyncing = false
            syncProgress = nil
            let duration = Date().timeIntervalSince(syncStartTime)
            print("✅ Feed sync completed in \(String(format: "%.1f", duration))s")
        }

        do {
            let descriptor = FetchDescriptor<Feed>(
                predicate: #Predicate<Feed> { $0.isActive }
            )
            let feeds = try modelContext.fetch(descriptor)
            let totalFeeds = feeds.count
            print("📋 Syncing \(totalFeeds) active feeds")

            guard totalFeeds > 0 else {
                print("ℹ️ No active feeds to sync")
                return
            }

            var successCount = 0
            var failureCount = 0

            // Batch configuration
            let batchSize = 20
            let concurrentRequestsPerBatch = 5

            // Split feeds into batches
            let batches = stride(from: 0, to: totalFeeds, by: batchSize).map {
                Array(feeds[$0..<min($0 + batchSize, totalFeeds)])
            }

            print("📦 Processing \(batches.count) batches of up to \(batchSize) feeds")

            // Process each batch
            for (batchIndex, batch) in batches.enumerated() {
                let batchStart = batchIndex * batchSize
                print("📦 Processing batch \(batchIndex + 1)/\(batches.count) (\(batch.count) feeds)")

                // Use TaskGroup for concurrent fetching within batch
                await withTaskGroup(of: (String, Result<Void, Error>).self) { group in
                    var activeTasks = 0
                    var feedIterator = batch.makeIterator()

                    // Start initial tasks up to concurrency limit
                    while activeTasks < concurrentRequestsPerBatch, let feed = feedIterator.next() {
                        let feedIndex = batchStart + batch.firstIndex(where: { $0.id == feed.id })!
                        let feedTitle = feed.title
                        let feedID = feed.persistentModelID

                        group.addTask {
                            do {
                                // Use syncFeedByID to avoid passing Feed across actor boundaries
                                try await self.syncFeedByID(feedID)
                                return (feedTitle, .success(()))
                            } catch {
                                return (feedTitle, .failure(error))
                            }
                        }
                        activeTasks += 1

                        // Update progress
                        self.syncProgress = "Syncing \(feedIndex + 1) of \(totalFeeds)"
                    }

                    // Process results and start new tasks as old ones complete
                    for await (feedTitle, result) in group {
                        activeTasks -= 1

                        switch result {
                        case .success:
                            successCount += 1
                        case .failure(let error):
                            failureCount += 1
                            print("❌ Error syncing feed \(feedTitle): \(error.localizedDescription)")
                        }

                        // Start next task if available
                        if let nextFeed = feedIterator.next() {
                            let feedIndex = batchStart + batch.firstIndex(where: { $0.id == nextFeed.id })!
                            let nextFeedTitle = nextFeed.title
                            let nextFeedID = nextFeed.persistentModelID

                            group.addTask {
                                do {
                                    // Use syncFeedByID to avoid passing Feed across actor boundaries
                                    try await self.syncFeedByID(nextFeedID)
                                    return (nextFeedTitle, .success(()))
                                } catch {
                                    return (nextFeedTitle, .failure(error))
                                }
                            }
                            activeTasks += 1

                            // Update progress
                            self.syncProgress = "Syncing \(feedIndex + 1) of \(totalFeeds)"
                        }
                    }
                }

                // Save changes after each batch to persist data while reducing save frequency
                saveChanges()
                print("✅ Batch \(batchIndex + 1) complete")
            }

            print("📊 Sync results: \(successCount) succeeded, \(failureCount) failed")

            // Only update lastSyncDate if at least one feed synced successfully
            if successCount > 0 {
                lastSyncDate = syncStartTime
                UserDefaults.standard.set(syncStartTime, forKey: Self.lastGlobalSyncKey)
                print("✅ Updated last sync date (synced \(successCount)/\(totalFeeds) feeds)")
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
