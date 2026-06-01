//
//  BackgroundSyncActor.swift
//  Today
//
//  Background feed syncing that parses feeds off main thread,
//  then inserts articles using a background ModelContext to avoid blocking the UI
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
/// Both parsing and database insertion run off the main thread
enum BackgroundFeedSync {

    /// Sync all active feeds
    /// - Parsing and insertion both happen on background threads via a background ModelContext
    static func syncAllFeeds(container: ModelContainer) async {
        let syncStartTime = Date()

        do {
            // Fetch active feeds using a background context
            let context = ModelContext(container)
            let descriptor = FetchDescriptor<Feed>(
                predicate: #Predicate<Feed> { $0.isActive }
            )
            let feeds = try context.fetch(descriptor)
            let totalFeeds = feeds.count

            guard totalFeeds > 0 else {
                return
            }

            // Extract only Sendable values before leaving this context's scope
            let feedInfos: [(id: PersistentIdentifier, url: String, lastModified: String?, etag: String?)] =
                feeds.map { ($0.persistentModelID, $0.url, $0.httpLastModified, $0.httpEtag) }

            // PHASE 1: Parse all feeds in background (no SwiftData access)
            let parsedResults = await parseAllFeedsInBackground(feedInfos: feedInfos)

            let notModifiedCount = parsedResults.filter { !$0.wasModified }.count
            let successCount = parsedResults.filter { $0.wasModified && !$0.articles.isEmpty }.count
            let failureCount = totalFeeds - parsedResults.count
            print("📡 [Sync] \(successCount) fetched, \(notModifiedCount) not modified (304), \(failureCount) failed")

            // PHASE 2: Insert articles using a background ModelContext
            await insertArticlesInChunks(parsedResults: parsedResults, container: container)

            // Update last sync date
            UserDefaults.standard.set(syncStartTime, forKey: "com.today.lastGlobalSyncDate")

            let duration = Date().timeIntervalSince(syncStartTime)
            print("✅ [Sync] Completed in \(String(format: "%.1f", duration))s")

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
        let chunks = feedInfos.chunked(into: maxConcurrentRequests)

        for chunk in chunks {
            let chunkResults = await withTaskGroup(of: ParsedFeedData?.self) { group in
                for feedInfo in chunk {
                    let feedID = feedInfo.id
                    let feedURL = feedInfo.url
                    let lastModified = feedInfo.lastModified
                    let etag = feedInfo.etag

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

    /// Insert articles using a background ModelContext — does not touch the main actor
    private static func insertArticlesInChunks(parsedResults: [ParsedFeedData], container: ModelContainer) async {
        // Background context: all writes stay off the main thread.
        // SwiftData notifies @Query observers automatically on save.
        let context = ModelContext(container)

        for feedData in parsedResults {
            guard let feed = context.model(for: feedData.feedID) as? Feed else { continue }

            // Update cache headers regardless of modification status
            feed.httpLastModified = feedData.newLastModified
            feed.httpEtag = feedData.newEtag

            // Update URL if there was a 301 permanent redirect
            if let newURL = feedData.finalURL {
                feed.url = newURL.absoluteString
            }

            // If feed wasn't modified, just update lastFetched and move on
            if !feedData.wasModified {
                feed.lastFetched = Date()
                continue
            }

            // Get existing article GUIDs — validate relationship fault is populated
            let existingGUIDs = Set((feed.articles ?? []).map { $0.guid })

            // Filter to only new articles
            let newArticles = feedData.articles.filter { !existingGUIDs.contains($0.guid) }

            for parsedArticle in newArticles {
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
                context.insert(article)
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
        }

        // Single save for all feeds — background context notifies @Query observers on completion
        try? context.save()
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
