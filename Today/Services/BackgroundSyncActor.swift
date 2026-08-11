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

/// One feed's inputs for a fetch, as Sendable values.
///
/// A struct rather than a labelled tuple so it can be handed to a task group task without
/// destructuring it at every call site.
struct FeedFetchRequest: Sendable {
    let id: PersistentIdentifier
    let url: String
    let lastModified: String?
    let etag: String?
}

/// Service for background feed syncing
/// Both parsing and database insertion run off the main thread
enum BackgroundFeedSync {

    /// Sync all active feeds
    /// - Parsing and insertion both happen on background threads via a background ModelContext
    @concurrent nonisolated static func syncAllFeeds(container: ModelContainer) async {
        #if DEBUG
        // Guards the @concurrent annotations above. This module builds with
        // SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor and SWIFT_APPROACHABLE_CONCURRENCY = YES,
        // which together mean an unannotated — or merely `nonisolated` — async function runs
        // on the caller's executor, i.e. the main thread. Both were true here until measured:
        // parsing, article insertion and the SwiftData save were all main-thread work.
        // If someone drops @concurrent, this trips immediately instead of silently
        // reintroducing a main-thread stall during every sync.
        assert(!Thread.isMainThread, "syncAllFeeds must not run on the main thread")
        #endif
        let syncStartTime = Date()
        let syncInterval = Perf.begin(.syncTotal)
        defer { Perf.end(syncInterval) }

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
            let requests = feeds.map {
                FeedFetchRequest(
                    id: $0.persistentModelID,
                    url: $0.url,
                    lastModified: $0.httpLastModified,
                    etag: $0.httpEtag
                )
            }

            // PHASE 1: Parse all feeds in background (no SwiftData access)
            let parsedResults = await Perf.measureAsync(.syncFetchParse, "\(totalFeeds) feeds") {
                await parseAllFeedsInBackground(requests: requests)
            }

            let notModifiedCount = parsedResults.filter { !$0.wasModified }.count
            let successCount = parsedResults.filter { $0.wasModified && !$0.articles.isEmpty }.count
            let failureCount = totalFeeds - parsedResults.count
            Perf.log("📡 [Sync] \(successCount) fetched, \(notModifiedCount) not modified (304), \(failureCount) failed")

            // PHASE 2: Insert articles using a background ModelContext
            await Perf.measureAsync(.syncInsert) {
                await insertArticlesInChunks(parsedResults: parsedResults, container: container)
            }

            // Update last sync date
            UserDefaults.standard.set(syncStartTime, forKey: "com.today.lastGlobalSyncDate")

            let duration = Date().timeIntervalSince(syncStartTime)
            Perf.log("✅ [Sync] Completed in \(String(format: "%.1f", duration))s")

        } catch {
            Perf.logError("❌ [Sync] Error: \(error.localizedDescription)")
        }
    }

    /// Maximum feed requests in flight at once.
    static let maxConcurrentRequests = 5

    /// Fetch and parse every feed off the main thread, keeping a fixed number in flight.
    ///
    /// Previously this processed feeds in sequential chunks of five, which made the phase cost
    /// the *sum of each chunk's slowest feed* rather than the slowest feed overall — one
    /// unresponsive feed stalled every feed behind it. Measured on a 31-feed store: 4385ms for
    /// the phase against a 1650ms slowest feed, and later 16.3s when five dead feeds landed in
    /// one chunk and each burned the full 15s request timeout.
    ///
    /// This version starts a replacement task as each one finishes, so a hung feed occupies
    /// one slot and never blocks the others.
    ///
    /// - Parameter session: injected by tests; production uses the timeout-configured default.
    @concurrent nonisolated static func parseAllFeedsInBackground(
        requests: [FeedFetchRequest],
        session: URLSession = ConditionalHTTPClient.defaultSession
    ) async -> [ParsedFeedData] {
        guard !requests.isEmpty else { return [] }

        var results: [ParsedFeedData] = []
        results.reserveCapacity(requests.count)

        await withTaskGroup(of: ParsedFeedData?.self) { group in
            var next = 0

            // Prime the group.
            while next < min(Self.maxConcurrentRequests, requests.count) {
                let request = requests[next]
                group.addTask { await fetchOne(request, session: session) }
                next += 1
            }

            // Refill as each completes, so the slot count stays constant.
            while let result = await group.next() {
                if let data = result {
                    results.append(data)
                }

                // On cancellation stop scheduling new work, but keep draining what is already
                // in flight — feeds that already succeeded should not be thrown away.
                guard !Task.isCancelled, next < requests.count else { continue }

                let request = requests[next]
                group.addTask { await fetchOne(request, session: session) }
                next += 1
            }
        }

        return results
    }

    /// One feed's fetch and parse, with the failure boundary and cancellation checks.
    @concurrent nonisolated private static func fetchOne(
        _ request: FeedFetchRequest,
        session: URLSession
    ) async -> ParsedFeedData? {
        // Cheap early exit so a cancelled sync stops issuing requests promptly.
        if Task.isCancelled { return nil }

        let feedInterval = Perf.begin(.syncFeedFetch, request.url)
        defer { Perf.end(feedInterval) }

        do {
            let result = try await fetchAndParseFeed(
                url: request.url,
                lastModified: request.lastModified,
                etag: request.etag,
                session: session
            )
            return ParsedFeedData(
                feedID: request.id,
                articles: result.articles,
                wasModified: result.wasModified,
                newLastModified: result.lastModified,
                newEtag: result.etag,
                finalURL: result.finalURL
            )
        } catch {
            // Per-feed failure boundary: one bad feed must never abort the sync.
            return nil
        }
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
    @concurrent nonisolated private static func fetchAndParseFeed(
        url: String,
        lastModified: String?,
        etag: String?,
        session: URLSession
    ) async throws -> FetchParseResult {
        if url.contains("reddit.com") && url.hasSuffix(".json") {
            return try await fetchRedditFeed(url: url, lastModified: lastModified, etag: etag, session: session)
        } else if isJSONFeed(url) {
            return try await fetchJSONFeed(url: url, lastModified: lastModified, etag: etag, session: session)
        } else {
            return try await fetchWithFallback(url: url, lastModified: lastModified, etag: etag, session: session)
        }
    }

    nonisolated private static func isJSONFeed(_ url: String) -> Bool {
        if url.contains("reddit.com") { return false }
        let lowercased = url.lowercased()
        return lowercased.hasSuffix(".json") ||
               lowercased.hasSuffix(".jsonfeed") ||
               lowercased.contains("feed.json") ||
               lowercased.contains("/feeds/json")
    }

    @concurrent nonisolated private static func fetchRedditFeed(
        url: String,
        lastModified: String?,
        etag: String?,
        session: URLSession
    ) async throws -> FetchParseResult {
        guard let feedURL = URL(string: url) else { throw SyncError.invalidURL }

        let response = try await ConditionalHTTPClient.conditionalFetch(
            url: feedURL,
            lastModified: lastModified,
            etag: etag,
            additionalHeaders: ["User-Agent": "ios:com.today.app:v1.0 (by /u/TodayApp)"],
            session: session
        )
        try Task.checkCancellation()

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

    @concurrent nonisolated private static func fetchJSONFeed(
        url: String,
        lastModified: String?,
        etag: String?,
        session: URLSession
    ) async throws -> FetchParseResult {
        guard let feedURL = URL(string: url) else { throw SyncError.invalidURL }

        let response = try await ConditionalHTTPClient.conditionalFetch(
            url: feedURL,
            lastModified: lastModified,
            etag: etag,
            session: session
        )
        // Parsing is the expensive part; skip it if the sync was cancelled mid-flight.
        try Task.checkCancellation()

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

    @concurrent nonisolated private static func fetchWithFallback(
        url: String,
        lastModified: String?,
        etag: String?,
        session: URLSession
    ) async throws -> FetchParseResult {
        guard let feedURL = URL(string: url) else { throw SyncError.invalidURL }

        let response = try await ConditionalHTTPClient.conditionalFetch(
            url: feedURL,
            lastModified: lastModified,
            etag: etag,
            session: session
        )
        // Parsing is the expensive part; skip it if the sync was cancelled mid-flight.
        try Task.checkCancellation()

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
    @concurrent nonisolated private static func insertArticlesInChunks(parsedResults: [ParsedFeedData], container: ModelContainer) async {
        #if DEBUG
        assert(!Thread.isMainThread, "insertArticlesInChunks must not run on the main thread")
        #endif
        // Background context: all writes stay off the main thread.
        // SwiftData notifies @Query observers automatically on save.
        let context = ModelContext(container)

        for feedData in parsedResults {
            // Stop between feeds rather than mid-feed, so whatever was already mutated is
            // saved below and no feed is left half-updated.
            if Task.isCancelled {
                Perf.log("↩️ [Sync] Insertion cancelled; saving partial progress")
                break
            }
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

