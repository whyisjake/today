//
//  BackgroundSyncActor.swift
//  Today
//
//  Background feed syncing that parses feeds off main thread,
//  then inserts articles on main thread in small chunks to avoid UI hangs
//

import Foundation
import SwiftData

/// Parsed feed data ready for insertion
struct ParsedFeedData: Sendable {
    let feedID: PersistentIdentifier
    let articles: [RSSParser.ParsedArticle]
    let wasModified: Bool
    let newLastModified: String?
    let newEtag: String?
    let finalURL: URL?  // Non-nil if there was a 301 permanent redirect
}

/// Service for background feed syncing
/// Parses feeds off the main thread, then inserts on main thread in chunks
enum BackgroundFeedSync {

    /// Sync all active feeds
    /// - Parsing happens on background threads
    /// - Database inserts happen on main thread in small chunks to avoid UI hangs
    @MainActor
    static func syncAllFeeds(modelContext: ModelContext) async {
        let syncStartTime = Date()
        print("📡 [Sync] Starting feed sync at \(syncStartTime.formatted(date: .omitted, time: .standard))")

        do {
            // Fetch all active feeds
            let descriptor = FetchDescriptor<Feed>(
                predicate: #Predicate<Feed> { $0.isActive }
            )
            let feeds = try modelContext.fetch(descriptor)
            let totalFeeds = feeds.count
            print("📋 [Sync] Syncing \(totalFeeds) active feeds")

            guard totalFeeds > 0 else {
                print("ℹ️ [Sync] No active feeds to sync")
                return
            }

            // Collect feed URLs, IDs, and cache headers for background parsing
            let feedInfos: [(id: PersistentIdentifier, url: String, lastModified: String?, etag: String?)] =
                feeds.map { ($0.persistentModelID, $0.url, $0.httpLastModified, $0.httpEtag) }

            // PHASE 1: Parse all feeds in background (no SwiftData access)
            print("🔄 [Sync] Phase 1: Parsing feeds in background...")
            let parsedResults = await parseAllFeedsInBackground(feedInfos: feedInfos)

            let notModifiedCount = parsedResults.filter { !$0.wasModified }.count
            let successCount = parsedResults.filter { $0.wasModified && !$0.articles.isEmpty }.count
            let failureCount = totalFeeds - parsedResults.count
            print("📊 [Sync] Parsing complete: \(successCount) fetched, \(notModifiedCount) not modified (304), \(failureCount) failed")

            // PHASE 2: Insert articles on main thread in small chunks
            print("💾 [Sync] Phase 2: Inserting articles in chunks...")
            await insertArticlesInChunks(parsedResults: parsedResults, modelContext: modelContext)

            // Save once at the end
            try? modelContext.save()

            // Update last sync date
            UserDefaults.standard.set(syncStartTime, forKey: "com.today.lastGlobalSyncDate")

            let duration = Date().timeIntervalSince(syncStartTime)
            print("✅ [Sync] Feed sync completed in \(String(format: "%.1f", duration))s")

        } catch {
            print("❌ [Sync] Error: \(error.localizedDescription)")
        }
    }

    /// Parse all feeds in background without any SwiftData access
    /// Limits concurrency to avoid overwhelming the system with many simultaneous requests
    private static func parseAllFeedsInBackground(
        feedInfos: [(id: PersistentIdentifier, url: String, lastModified: String?, etag: String?)]
    ) async -> [ParsedFeedData] {
        // Limit concurrent network requests to avoid overwhelming the system
        let maxConcurrentRequests = 5
        var results: [ParsedFeedData] = []
        
        // Process feeds in chunks to limit concurrency
        // Each chunk is processed concurrently, but we wait for a chunk to complete before starting the next
        // This ensures we never have more than maxConcurrentRequests active at once
        for chunk in feedInfos.chunked(into: maxConcurrentRequests) {
            let chunkResults = await withTaskGroup(of: ParsedFeedData?.self) { group in
                for (feedID, feedURL, lastModified, etag) in chunk {
                    group.addTask {
                        do {
                            let result = try await fetchAndParseFeed(
                                url: feedURL,
                                lastModified: lastModified,
                                etag: etag
                            )
                            return ParsedFeedData(
                                feedID: feedID,
                                articles: result.articles,
                                wasModified: result.wasModified,
                                newLastModified: result.lastModified,
                                newEtag: result.etag,
                                finalURL: result.finalURL
                            )
                        } catch {
                            print("❌ [Sync] Failed to parse \(feedURL): \(error.localizedDescription)")
                            return nil
                        }
                    }
                }
                
                var chunkResults: [ParsedFeedData] = []
                for await result in group {
                    if let data = result {
                        chunkResults.append(data)
                    }
                }
                return chunkResults
            }
            results.append(contentsOf: chunkResults)
        }
        return results
    }

    /// Result of fetching and parsing a feed with conditional GET support
    private struct FetchParseResult {
        let articles: [RSSParser.ParsedArticle]
        let wasModified: Bool
        let lastModified: String?
        let etag: String?
        let finalURL: URL?
    }

    /// Fetch and parse a single feed with conditional GET (runs on background thread)
    private static func fetchAndParseFeed(
        url: String,
        lastModified: String?,
        etag: String?
    ) async throws -> FetchParseResult {
        if url.contains("reddit.com") && url.hasSuffix(".json") {
            return try await fetchRedditFeed(url: url, lastModified: lastModified, etag: etag)
        } else if isJSONFeed(url) {
            return try await fetchJSONFeed(url: url, lastModified: lastModified, etag: etag)
        } else {
            return try await fetchWithFallback(url: url, lastModified: lastModified, etag: etag)
        }
    }

    private static func isJSONFeed(_ url: String) -> Bool {
        if url.contains("reddit.com") { return false }
        let lowercased = url.lowercased()
        return lowercased.hasSuffix(".json") ||
               lowercased.hasSuffix(".jsonfeed") ||
               lowercased.contains("feed.json") ||
               lowercased.contains("/feeds/json")
    }

    private static func fetchRedditFeed(
        url: String,
        lastModified: String?,
        etag: String?
    ) async throws -> FetchParseResult {
        guard let feedURL = URL(string: url) else { throw SyncError.invalidURL }

        let response = try await ConditionalHTTPClient.conditionalFetch(
            url: feedURL,
            lastModified: lastModified,
            etag: etag,
            additionalHeaders: ["User-Agent": "ios:com.today.app:v1.0 (by /u/TodayApp)"]
        )

        // Handle 304 Not Modified
        guard response.wasModified, let data = response.data else {
            return FetchParseResult(
                articles: [],
                wasModified: false,
                lastModified: lastModified,
                etag: etag,
                finalURL: response.hadPermanentRedirect ? response.finalURL : nil
            )
        }

        let parser = RedditJSONParser()
        let (_, _, redditPosts) = try parser.parseSubredditFeed(data: data)
        return FetchParseResult(
            articles: redditPosts.map { $0.toArticle() },
            wasModified: true,
            lastModified: response.lastModified,
            etag: response.etag,
            finalURL: response.hadPermanentRedirect ? response.finalURL : nil
        )
    }

    private static func fetchJSONFeed(
        url: String,
        lastModified: String?,
        etag: String?
    ) async throws -> FetchParseResult {
        guard let feedURL = URL(string: url) else { throw SyncError.invalidURL }

        let response = try await ConditionalHTTPClient.conditionalFetch(
            url: feedURL,
            lastModified: lastModified,
            etag: etag
        )

        // Handle 304 Not Modified
        guard response.wasModified, let data = response.data else {
            return FetchParseResult(
                articles: [],
                wasModified: false,
                lastModified: lastModified,
                etag: etag,
                finalURL: response.hadPermanentRedirect ? response.finalURL : nil
            )
        }

        let parser = JSONFeedParser()
        guard try parser.parse(data: data) else { throw SyncError.parsingFailed }

        return FetchParseResult(
            articles: parser.articles,
            wasModified: true,
            lastModified: response.lastModified,
            etag: response.etag,
            finalURL: response.hadPermanentRedirect ? response.finalURL : nil
        )
    }

    private static func fetchWithFallback(
        url: String,
        lastModified: String?,
        etag: String?
    ) async throws -> FetchParseResult {
        guard let feedURL = URL(string: url) else { throw SyncError.invalidURL }

        let response = try await ConditionalHTTPClient.conditionalFetch(
            url: feedURL,
            lastModified: lastModified,
            etag: etag
        )

        // Handle 304 Not Modified
        guard response.wasModified, let data = response.data else {
            return FetchParseResult(
                articles: [],
                wasModified: false,
                lastModified: lastModified,
                etag: etag,
                finalURL: response.hadPermanentRedirect ? response.finalURL : nil
            )
        }

        // Try RSS parser first
        let rssParser = RSSParser()
        if rssParser.parse(data: data) && !rssParser.articles.isEmpty {
            return FetchParseResult(
                articles: rssParser.articles,
                wasModified: true,
                lastModified: response.lastModified,
                etag: response.etag,
                finalURL: response.hadPermanentRedirect ? response.finalURL : nil
            )
        }

        // Fallback to JSON Feed parser
        let jsonParser = JSONFeedParser()
        if let parsed = try? jsonParser.parse(data: data), parsed {
            return FetchParseResult(
                articles: jsonParser.articles,
                wasModified: true,
                lastModified: response.lastModified,
                etag: response.etag,
                finalURL: response.hadPermanentRedirect ? response.finalURL : nil
            )
        }

        throw SyncError.parsingFailed
    }

    /// Insert articles on main thread in small chunks with yields between them
    @MainActor
    private static func insertArticlesInChunks(parsedResults: [ParsedFeedData], modelContext: ModelContext) async {
        let chunkSize = 20 // Insert 20 articles at a time, then yield

        for feedData in parsedResults {
            guard let feed = modelContext.model(for: feedData.feedID) as? Feed else { continue }

            // Update cache headers regardless of modification status
            feed.httpLastModified = feedData.newLastModified
            feed.httpEtag = feedData.newEtag

            // Update URL if there was a 301 permanent redirect
            if let newURL = feedData.finalURL {
                print("📋 [Sync] Updating feed URL from \(feed.url) to \(newURL.absoluteString) (301 redirect)")
                feed.url = newURL.absoluteString
            }

            // If feed wasn't modified, just update lastFetched and move on
            if !feedData.wasModified {
                feed.lastFetched = Date()
                print("📋 [Sync] Feed \(feed.title) not modified (304)")
                continue
            }

            // Get existing article GUIDs
            let existingGUIDs = Set((feed.articles ?? []).map { $0.guid })

            // Filter to only new articles
            let newArticles = feedData.articles.filter { !existingGUIDs.contains($0.guid) }

            // Insert in chunks
            for chunk in newArticles.chunked(into: chunkSize) {
                for parsedArticle in chunk {
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

                // Yield to let UI breathe between chunks
                await Task.yield()
            }

            // Update audio data for existing articles
            for existingArticle in feed.articles ?? [] {
                if existingArticle.audioUrl == nil,
                   let parsedArticle = feedData.articles.first(where: { $0.guid == existingArticle.guid }),
                   let audioUrl = parsedArticle.audioUrl {
                    existingArticle.audioUrl = audioUrl
                    existingArticle.audioDuration = parsedArticle.audioDuration
                    existingArticle.audioType = parsedArticle.audioType
                }
            }

            feed.lastFetched = Date()

            // Yield after each feed
            await Task.yield()
        }
    }

    enum SyncError: LocalizedError {
        case invalidURL
        case parsingFailed

        var errorDescription: String? {
            switch self {
            case .invalidURL: return "Invalid feed URL"
            case .parsingFailed: return "Failed to parse feed"
            }
        }
    }
}

// MARK: - Array Extension for Chunking

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
