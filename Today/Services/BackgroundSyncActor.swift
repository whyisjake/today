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

/// A feed whose fetch or parse failed. `Error` so it can ride in a `Result`.
struct FeedFailure: Sendable, Error {
    let id: PersistentIdentifier
    let message: String
}

/// Everything the fetch phase learned. Failures are carried rather than dropped so the sync
/// can tell "nothing changed" apart from "nothing worked".
struct FetchPhaseResults: Sendable {
    var parsed: [ParsedFeedData] = []
    var failures: [FeedFailure] = []

    /// At least one feed responded — a 304 counts, since the server confirmed freshness.
    var hadAnySuccess: Bool { !parsed.isEmpty }
}

/// Service for background feed syncing
/// Both parsing and database insertion run off the main thread
enum BackgroundFeedSync {

    /// Sync all active feeds
    /// - Parsing and insertion both happen on background threads via a background ModelContext
    /// - Parameter session: injected by tests; production uses the timeout-configured default.
    @concurrent nonisolated static func syncAllFeeds(
        container: ModelContainer,
        session: URLSession = ConditionalHTTPClient.defaultSession
    ) async {
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
                await parseAllFeedsInBackground(requests: requests, session: session)
            }

            let notModifiedCount = parsedResults.parsed.filter { !$0.wasModified }.count
            let successCount = parsedResults.parsed.filter { $0.wasModified && !$0.articles.isEmpty }.count
            Perf.log("📡 [Sync] \(successCount) fetched, \(notModifiedCount) not modified (304), \(parsedResults.failures.count) failed")

            // PHASE 2: Insert articles using a background ModelContext
            await Perf.measureAsync(.syncInsert) {
                await insertArticlesInChunks(parsedResults: parsedResults.parsed, container: container)
            }

            // Record per-feed health so a persistently broken feed is diagnosable rather than
            // just missing from the results.
            await recordFeedHealth(results: parsedResults, container: container)

            // Only claim a successful sync if at least one feed actually responded.
            //
            // needsSync() gates on this timestamp with a 2-hour window, so writing it after a
            // total failure meant the app refused to retry for two hours precisely when it
            // most needed to — offline at launch, or a DNS blip, and the feeds stay stale.
            if parsedResults.hadAnySuccess {
                UserDefaults.standard.set(syncStartTime, forKey: "com.today.lastGlobalSyncDate")
                let duration = Date().timeIntervalSince(syncStartTime)
                Perf.log("✅ [Sync] Completed in \(String(format: "%.1f", duration))s")
            } else {
                Perf.event(.syncTotal, "every feed failed — not recording a successful sync")
                Perf.logError("❌ [Sync] All \(totalFeeds) feeds failed; leaving last-sync date untouched so the next launch retries")
            }

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
    ) async -> FetchPhaseResults {
        guard !requests.isEmpty else { return FetchPhaseResults() }

        var results = FetchPhaseResults()
        results.parsed.reserveCapacity(requests.count)

        await withTaskGroup(of: Result<ParsedFeedData, FeedFailure>?.self) { group in
            var next = 0

            // Prime the group.
            while next < min(Self.maxConcurrentRequests, requests.count) {
                let request = requests[next]
                group.addTask { await fetchOne(request, session: session) }
                next += 1
            }

            // Refill as each completes, so the slot count stays constant.
            while let result = await group.next() {
                switch result {
                case .success(let data): results.parsed.append(data)
                case .failure(let failure): results.failures.append(failure)
                case nil: break // cancelled before issuing
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
    ) async -> Result<ParsedFeedData, FeedFailure>? {
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
            return .success(ParsedFeedData(
                feedID: request.id,
                articles: result.articles,
                wasModified: result.wasModified,
                newLastModified: result.lastModified,
                newEtag: result.etag,
                finalURL: result.finalURL
            ))
        } catch is CancellationError {
            // Not a feed problem — do not record it against the feed's health.
            return nil
        } catch {
            // Per-feed failure boundary: one bad feed must never abort the sync.
            return .failure(FeedFailure(id: request.id, message: error.localizedDescription))
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
        // Scheme allow-list: a stored feed URL predating the ingestion guard could still be
        // `file://`, and this is the point where it would be handed to URLSession.
        guard let feedURL = SafeURL.webOpenable(url) else { throw SyncError.invalidURL }

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
        // Scheme allow-list: a stored feed URL predating the ingestion guard could still be
        // `file://`, and this is the point where it would be handed to URLSession.
        guard let feedURL = SafeURL.webOpenable(url) else { throw SyncError.invalidURL }

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
        // Scheme allow-list: a stored feed URL predating the ingestion guard could still be
        // `file://`, and this is the point where it would be handed to URLSession.
        guard let feedURL = SafeURL.webOpenable(url) else { throw SyncError.invalidURL }

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
    /// Not private: SyncOutcomeTests drives this directly to exercise the deleted-feed path,
    /// which cannot be produced through the normal sync entry point.
    @concurrent nonisolated static func insertArticlesInChunks(parsedResults: [ParsedFeedData], container: ModelContainer) async {
        #if DEBUG
        assert(!Thread.isMainThread, "insertArticlesInChunks must not run on the main thread")
        #endif
        // Background context: all writes stay off the main thread.
        // SwiftData notifies @Query observers automatically on save.
        let context = ModelContext(container)

        for feedData in parsedResults {
            // Stop between feeds rather than mid-feed, so no feed is left half-updated.
            if Task.isCancelled {
                Perf.log("↩️ [Sync] Insertion cancelled; earlier feeds already saved")
                break
            }

            let feedID = feedData.feedID
            // Fetch rather than context.model(for:), which can hand back an unrealised stub
            // for an identifier that no longer exists — the `as? Feed` cast would then skip
            // the feed silently. A miss here means the feed was deleted mid-sync.
            let matches = (try? context.fetch(FetchDescriptor<Feed>(
                predicate: #Predicate<Feed> { $0.persistentModelID == feedID }
            ))) ?? []
            guard let feed = matches.first else {
                Perf.log("⚠️ [Sync] Feed deleted mid-sync; skipping its results")
                continue
            }

            // Update cache headers regardless of modification status
            feed.httpLastModified = feedData.newLastModified
            feed.httpEtag = feedData.newEtag

            // Update URL only if there was a permanent redirect. `finalURL` is nil for
            // 302/303/307 precisely so a temporary redirect cannot overwrite a subscription.
            if let newURL = feedData.finalURL {
                feed.url = newURL.absoluteString
            }

            // A response is a success even when unchanged, so clear any recorded failure.
            feed.lastSyncError = nil
            feed.consecutiveSyncFailureCount = 0

            // If feed wasn't modified, just update lastFetched and move on
            if !feedData.wasModified {
                feed.lastFetched = Date()
                Self.save(context, label: "304 for \(feed.url)")
                continue
            }

            // Look up only the articles this response could possibly collide with, instead of
            // faulting in the feed's entire history. The old code walked `feed.articles` twice
            // — once for GUID dedup and again for the audio backfill — so insertion cost grew
            // with everything the feed had ever published. U2 indexed `guid` for this.
            let parsedGUIDs = feedData.articles.map(\.guid)
            let colliding = (try? context.fetch(FetchDescriptor<Article>(
                predicate: #Predicate<Article> {
                    $0.feed?.persistentModelID == feedID && parsedGUIDs.contains($0.guid)
                }
            ))) ?? []
            let existingByGUID = Dictionary(
                colliding.map { ($0.guid, $0) },
                uniquingKeysWith: { first, _ in first }
            )

            // Filter to only new articles
            let newArticles = feedData.articles.filter { existingByGUID[$0.guid] == nil }

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

            // Backfill audio onto articles that already existed. One pass over the parsed
            // articles using the GUID map, rather than the old nested loop over every
            // existing article with a linear `first(where:)` inside it — that was
            // O(existing × parsed) and grew with the feed's whole history.
            for parsedArticle in feedData.articles {
                guard let audioUrl = parsedArticle.audioUrl,
                      let existing = existingByGUID[parsedArticle.guid],
                      existing.audioUrl == nil else { continue }
                existing.audioUrl = audioUrl
                existing.audioDuration = parsedArticle.audioDuration
                existing.audioType = parsedArticle.audioType
            }

            feed.lastFetched = Date()

            // Save per feed rather than once at the end. A single terminal save produced one
            // large @Query invalidation — the visible mid-sync stall — and meant a failure
            // part-way through discarded every feed's work.
            Self.save(context, label: feed.url)
        }
    }

    /// Save, logging rather than throwing: one feed's save failure must not abort the rest.
    private nonisolated static func save(_ context: ModelContext, label: String) {
        do {
            try context.save()
        } catch {
            Perf.logError("❌ [Sync] Save failed for \(label): \(error.localizedDescription)")
        }
    }

    /// Record per-feed sync health: clear it on success, accumulate it on failure.
    @concurrent nonisolated private static func recordFeedHealth(
        results: FetchPhaseResults,
        container: ModelContainer
    ) async {
        guard !results.failures.isEmpty else { return }
        let context = ModelContext(container)

        for failure in results.failures {
            let feedID = failure.id
            let matches = (try? context.fetch(FetchDescriptor<Feed>(
                predicate: #Predicate<Feed> { $0.persistentModelID == feedID }
            ))) ?? []
            guard let feed = matches.first else { continue }

            feed.lastSyncError = failure.message
            feed.consecutiveSyncFailureCount = (feed.consecutiveSyncFailureCount ?? 0) + 1
        }

        save(context, label: "feed health")
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

