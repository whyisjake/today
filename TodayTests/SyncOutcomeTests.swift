//
//  SyncOutcomeTests.swift
//  TodayTests
//
//  Tests for sync outcome integrity and insertion behaviour (U9).
//
//  The headline bug: the global sync timestamp was written even when every feed failed.
//  `needsSync()` gates on that timestamp with a 2-hour window, so a total failure — offline at
//  launch, a DNS blip — made the app refuse to retry for two hours, precisely when it most
//  needed to.
//

import XCTest
import SwiftData
@testable import Today

final class SyncOutcomeTests: XCTestCase {

    private var mockSession: URLSession!
    private var container: ModelContainer!
    private let syncDateKey = "com.today.lastGlobalSyncDate"

    override func setUpWithError() throws {
        try super.setUpWithError()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        mockSession = URLSession(configuration: config)

        let schema = Schema([Feed.self, Article.self, OPMLSubscription.self])
        container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        UserDefaults.standard.removeObject(forKey: syncDateKey)
    }

    override func tearDownWithError() throws {
        MockURLProtocol.mockResponses.removeAll()
        UserDefaults.standard.removeObject(forKey: syncDateKey)
        mockSession = nil
        container = nil
        try super.tearDownWithError()
    }

    private static let rssBody = """
    <?xml version="1.0"?>
    <rss version="2.0"><channel><title>T</title>
    <item><title>One</title><link>https://example.com/1</link><guid>g1</guid></item>
    <item><title>Two</title><link>https://example.com/2</link><guid>g2</guid></item>
    </channel></rss>
    """

    // MARK: - hadAnySuccess

    func testAllFailuresMeansNoSuccess() throws {
        let feed = try makeFeed()
        let results = FetchPhaseResults(
            parsed: [],
            failures: [FeedFailure(id: feed.persistentModelID, message: "boom")]
        )
        XCTAssertFalse(results.hadAnySuccess)
    }

    func testA304CountsAsSuccess() throws {
        let feed = try makeFeed()
        let results = FetchPhaseResults(
            parsed: [ParsedFeedData(
                feedID: feed.persistentModelID, articles: [], wasModified: false,
                newLastModified: nil, newEtag: nil, finalURL: nil
            )],
            failures: []
        )
        XCTAssertTrue(
            results.hadAnySuccess,
            "the server confirmed freshness, which is a successful sync"
        )
    }

    func testMixedOutcomeCountsAsSuccess() throws {
        let ok = try makeFeed(url: "https://ok.example.com/rss.xml")
        let bad = try makeFeed(url: "https://bad.example.com/rss.xml")
        let results = FetchPhaseResults(
            parsed: [ParsedFeedData(
                feedID: ok.persistentModelID, articles: [], wasModified: true,
                newLastModified: nil, newEtag: nil, finalURL: nil
            )],
            failures: [FeedFailure(id: bad.persistentModelID, message: "boom")]
        )
        XCTAssertTrue(results.hadAnySuccess)
    }

    // MARK: - Timestamp behaviour end to end

    /// Every feed fails, so the timestamp must be left alone and `needsSync()` must still
    /// report that a sync is needed.
    func testTotalFailureLeavesTheSyncDateUntouched() async throws {
        _ = try makeFeed(url: "https://unmapped-a.example.com/rss.xml")
        _ = try makeFeed(url: "https://unmapped-b.example.com/rss.xml")

        XCTAssertNil(UserDefaults.standard.object(forKey: syncDateKey))
        await BackgroundFeedSync.syncAllFeeds(container: container, session: mockSession)

        XCTAssertNil(
            UserDefaults.standard.object(forKey: syncDateKey),
            "a sync where nothing succeeded must not record itself as successful"
        )
        let needsSync = await MainActor.run { FeedManager.needsSync() }
        XCTAssertTrue(
            needsSync,
            "the next launch must retry rather than wait out the 2-hour window"
        )
    }

    func testPartialSuccessRecordsTheSyncDate() async throws {
        try registerFeed(url: "https://good.example.com/rss.xml", body: Self.rssBody)
        _ = try makeFeed(url: "https://unmapped.example.com/rss.xml")

        await BackgroundFeedSync.syncAllFeeds(container: container, session: mockSession)

        XCTAssertNotNil(
            UserDefaults.standard.object(forKey: syncDateKey),
            "one healthy feed is enough to call the sync successful"
        )
    }

    func testNoActiveFeedsDoesNotRecordASync() async throws {
        // Nothing attempted, so nothing to claim.
        await BackgroundFeedSync.syncAllFeeds(container: container, session: mockSession)
        XCTAssertNil(UserDefaults.standard.object(forKey: syncDateKey))
    }

    // MARK: - Per-feed health

    func testFailureRecordsErrorAndIncrementsCount() async throws {
        let feed = try makeFeed(url: "https://unmapped.example.com/rss.xml")

        await BackgroundFeedSync.syncAllFeeds(container: container, session: mockSession)
        let afterFirst = try refetch(feed)
        XCTAssertNotNil(afterFirst.lastSyncError)
        XCTAssertEqual(afterFirst.consecutiveSyncFailureCount, 1)

        await BackgroundFeedSync.syncAllFeeds(container: container, session: mockSession)
        let afterSecond = try refetch(feed)
        XCTAssertEqual(
            afterSecond.consecutiveSyncFailureCount, 2,
            "consecutive failures accumulate so a persistently broken feed is visible"
        )
    }

    func testSuccessClearsPreviousFailureState() async throws {
        let feed = try makeFeed(url: "https://flaky.example.com/rss.xml")
        // Start from a recorded failure.
        await BackgroundFeedSync.syncAllFeeds(container: container, session: mockSession)
        XCTAssertEqual(try refetch(feed).consecutiveSyncFailureCount, 1)

        // Now the feed responds.
        try registerResponse(url: "https://flaky.example.com/rss.xml", body: Self.rssBody)
        await BackgroundFeedSync.syncAllFeeds(container: container, session: mockSession)

        let recovered = try refetch(feed)
        XCTAssertNil(recovered.lastSyncError, "recovery must clear the error")
        XCTAssertEqual(recovered.consecutiveSyncFailureCount, 0)
    }

    // MARK: - Insertion

    func testArticlesAreInsertedAndDeduplicatedAcrossSyncs() async throws {
        try registerFeed(url: "https://good.example.com/rss.xml", body: Self.rssBody)

        await BackgroundFeedSync.syncAllFeeds(container: container, session: mockSession)
        XCTAssertEqual(try articleCount(), 2)

        // Same feed, same GUIDs: a second sync must not duplicate anything.
        UserDefaults.standard.removeObject(forKey: syncDateKey)
        await BackgroundFeedSync.syncAllFeeds(container: container, session: mockSession)
        XCTAssertEqual(
            try articleCount(), 2,
            "GUID dedup must hold across syncs — this is what the targeted GUID query replaced"
        )
    }

    func testAudioIsBackfilledOntoAnExistingArticle() async throws {
        let url = "https://podcast.example.com/rss.xml"
        // First sync: no enclosure.
        try registerFeed(url: url, body: """
        <?xml version="1.0"?>
        <rss version="2.0"><channel><title>P</title>
        <item><title>Ep</title><link>https://example.com/ep</link><guid>ep1</guid></item>
        </channel></rss>
        """)
        await BackgroundFeedSync.syncAllFeeds(container: container, session: mockSession)
        XCTAssertNil(try firstArticle().audioUrl)

        // Second sync: same GUID, now with an enclosure.
        try registerResponse(url: url, body: """
        <?xml version="1.0"?>
        <rss version="2.0"><channel><title>P</title>
        <item><title>Ep</title><link>https://example.com/ep</link><guid>ep1</guid>
        <enclosure url="https://example.com/ep.mp3" type="audio/mpeg" length="1000"/></item>
        </channel></rss>
        """)
        UserDefaults.standard.removeObject(forKey: syncDateKey)
        await BackgroundFeedSync.syncAllFeeds(container: container, session: mockSession)

        let article = try firstArticle()
        XCTAssertEqual(
            article.audioUrl, "https://example.com/ep.mp3",
            "audio must be backfilled onto the existing article, not inserted as a new one"
        )
        XCTAssertEqual(try articleCount(), 1, "backfill must not duplicate the article")
    }

    func testDeletedFeedMidSyncIsSkippedWithoutCrashing() async throws {
        let feed = try makeFeed(url: "https://good.example.com/rss.xml")
        try registerResponse(url: "https://good.example.com/rss.xml", body: Self.rssBody)

        // Delete the feed, then hand its identifier to the insert phase — the situation a
        // concurrent delete produces. `context.model(for:)` would have returned a stub here.
        let staleID = feed.persistentModelID
        let context = ModelContext(container)
        if let live = try context.fetch(FetchDescriptor<Feed>()).first {
            context.delete(live)
            try context.save()
        }

        let parsed = ParsedFeedData(
            feedID: staleID, articles: [], wasModified: true,
            newLastModified: nil, newEtag: nil, finalURL: nil
        )
        // Must not trap; the feed is simply skipped.
        await BackgroundFeedSync.insertArticlesInChunks(parsedResults: [parsed], container: container)
        XCTAssertEqual(try articleCount(), 0)
    }

    // MARK: - Helpers

    @discardableResult
    private func makeFeed(url: String = "https://feed.example.com/rss.xml") throws -> Feed {
        let context = ModelContext(container)
        let feed = Feed(title: "Feed", url: url, category: "Tech")
        context.insert(feed)
        try context.save()
        return feed
    }

    private func registerResponse(url: String, body: String) throws {
        MockURLProtocol.mockResponses[URL(string: url)!] = MockURLProtocol.MockResponse(
            statusCode: 200, headers: [:], data: body.data(using: .utf8), redirectURL: nil
        )
    }

    private func registerFeed(url: String, body: String) throws {
        try registerResponse(url: url, body: body)
        _ = try makeFeed(url: url)
    }

    private func refetch(_ feed: Feed) throws -> Feed {
        let url = feed.url
        let context = ModelContext(container)
        return try XCTUnwrap(
            try context.fetch(FetchDescriptor<Feed>(predicate: #Predicate { $0.url == url })).first
        )
    }

    private func articleCount() throws -> Int {
        try ModelContext(container).fetchCount(FetchDescriptor<Article>())
    }

    private func firstArticle() throws -> Article {
        try XCTUnwrap(try ModelContext(container).fetch(FetchDescriptor<Article>()).first)
    }
}
