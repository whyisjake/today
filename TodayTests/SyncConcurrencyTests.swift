//
//  SyncConcurrencyTests.swift
//  TodayTests
//
//  Tests for the sync fetch phase's concurrency behaviour (U8).
//
//  The property under test is head-of-line freedom: one slow feed must not delay unrelated
//  feeds. The previous implementation processed feeds in sequential chunks of five, so the
//  phase cost the sum of each chunk's slowest feed — measured at 4385ms against a 1650ms
//  slowest feed on a 31-feed store, and 16.3s when five dead feeds landed in one chunk.
//
//  These use MockURLProtocol with per-URL delays, so they assert timing relationships rather
//  than absolute durations and do not touch the network.
//

import XCTest
import SwiftData
@testable import Today

final class SyncConcurrencyTests: XCTestCase {

    private var mockSession: URLSession!
    private var container: ModelContainer!

    override func setUpWithError() throws {
        try super.setUpWithError()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        mockSession = URLSession(configuration: config)
        MockURLProtocol.resetCounters()

        let schema = Schema([Feed.self, Article.self, OPMLSubscription.self])
        container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
    }

    override func tearDownWithError() throws {
        MockURLProtocol.mockResponses.removeAll()
        MockURLProtocol.resetCounters()
        mockSession = nil
        container = nil
        try super.tearDownWithError()
    }

    // MARK: - Helpers

    private static let rssBody = """
    <?xml version="1.0"?>
    <rss version="2.0"><channel><title>T</title>
    <item><title>One</title><link>https://example.com/1</link><guid>g1</guid></item>
    </channel></rss>
    """

    /// Registers `count` feed URLs and returns matching requests. `slowIndices` get `delay`.
    private func makeRequests(
        count: Int,
        slowIndices: Set<Int> = [],
        delay: TimeInterval = 0
    ) throws -> [FeedFetchRequest] {
        let context = ModelContext(container)
        var requests: [FeedFetchRequest] = []

        for index in 0..<count {
            let urlString = "https://feed\(index).example.com/rss.xml"
            let url = URL(string: urlString)!
            MockURLProtocol.mockResponses[url] = MockURLProtocol.MockResponse(
                statusCode: 200,
                headers: ["ETag": "\"e\(index)\""],
                data: Self.rssBody.data(using: .utf8),
                redirectURL: nil,
                delay: slowIndices.contains(index) ? delay : 0
            )

            let feed = Feed(title: "Feed \(index)", url: urlString, category: "Tech")
            context.insert(feed)
            requests.append(FeedFetchRequest(
                id: feed.persistentModelID, url: urlString, lastModified: nil, etag: nil
            ))
        }
        try context.save()
        return requests
    }

    // MARK: - Head-of-line blocking

    /// The core U8 assertion. One feed slower than the rest must not serialise the others:
    /// total time should track the slow feed, not accumulate across waves.
    func testOneSlowFeedDoesNotDelayTheRest() async throws {
        let slowDelay: TimeInterval = 1.0
        // 12 feeds, one slow. Under the old chunked implementation the slow feed's wave
        // blocked every later wave.
        let requests = try makeRequests(count: 12, slowIndices: [0], delay: slowDelay)

        let start = Date()
        let results = await BackgroundFeedSync.parseAllFeedsInBackground(
            requests: requests, session: mockSession
        )
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertEqual(results.count, 12, "every feed must still be fetched")
        XCTAssertLessThan(
            elapsed, slowDelay * 2,
            "elapsed \(elapsed)s should track the single slow feed, not serialise behind it"
        )
    }

    /// With more slow feeds than concurrency slots, the phase must still be bounded by
    /// ceil(slowCount / slots) waves — not by slowCount waves.
    func testManySlowFeedsStillOverlap() async throws {
        let slowDelay: TimeInterval = 0.6
        let slots = BackgroundFeedSync.maxConcurrentRequests
        let requests = try makeRequests(
            count: slots, slowIndices: Set(0..<slots), delay: slowDelay
        )

        let start = Date()
        let results = await BackgroundFeedSync.parseAllFeedsInBackground(
            requests: requests, session: mockSession
        )
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertEqual(results.count, slots)
        XCTAssertLessThan(
            elapsed, slowDelay * Double(slots),
            "all \(slots) slow feeds fit in one wave, so they must overlap rather than queue"
        )
    }

    // MARK: - Concurrency ceiling

    func testConcurrencyNeverExceedsTheConfiguredCeiling() async throws {
        // A small delay on every feed keeps requests overlapping long enough to observe.
        let requests = try makeRequests(count: 20, slowIndices: Set(0..<20), delay: 0.05)

        _ = await BackgroundFeedSync.parseAllFeedsInBackground(
            requests: requests, session: mockSession
        )

        let peak = MockURLProtocol.peakConcurrency()
        XCTAssertLessThanOrEqual(
            peak,
            BackgroundFeedSync.maxConcurrentRequests,
            "observed \(peak) concurrent requests, ceiling is \(BackgroundFeedSync.maxConcurrentRequests)"
        )
        XCTAssertGreaterThan(
            peak, 1,
            "requests should genuinely overlap, otherwise this test proves nothing"
        )
    }

    func testAllFeedsAreFetchedWhenThereAreMoreFeedsThanSlots() async throws {
        let requests = try makeRequests(count: 17)
        let results = await BackgroundFeedSync.parseAllFeedsInBackground(
            requests: requests, session: mockSession
        )
        XCTAssertEqual(
            Set(results.map(\.feedID)), Set(requests.map(\.id)),
            "the refill loop must schedule every feed exactly once"
        )
    }

    // MARK: - Edge cases

    func testEmptyRequestListReturnsEmpty() async {
        let results = await BackgroundFeedSync.parseAllFeedsInBackground(
            requests: [], session: mockSession
        )
        XCTAssertTrue(results.isEmpty)
    }

    func testSingleFeedWorks() async throws {
        let requests = try makeRequests(count: 1)
        let results = await BackgroundFeedSync.parseAllFeedsInBackground(
            requests: requests, session: mockSession
        )
        XCTAssertEqual(results.count, 1)
        XCTAssertTrue(results[0].wasModified)
    }

    /// A feed that fails must not abort the sync or drop its neighbours.
    func testOneFailingFeedDoesNotAffectTheOthers() async throws {
        var requests = try makeRequests(count: 5)
        // An unmapped URL gets MockURLProtocol's synthetic 404 with no body, which fails to
        // parse and therefore yields nil for that feed.
        let context = ModelContext(container)
        let broken = Feed(title: "Broken", url: "https://unmapped.example.com/rss.xml", category: "Tech")
        context.insert(broken)
        try context.save()
        requests.append(FeedFetchRequest(
            id: broken.persistentModelID,
            url: "https://unmapped.example.com/rss.xml",
            lastModified: nil,
            etag: nil
        ))

        let results = await BackgroundFeedSync.parseAllFeedsInBackground(
            requests: requests, session: mockSession
        )

        XCTAssertEqual(results.count, 5, "the five healthy feeds must all survive")
        XCTAssertFalse(results.contains { $0.feedID == broken.persistentModelID })
    }

    func testNotModifiedFeedsAreReportedAsUnmodified() async throws {
        let context = ModelContext(container)
        let urlString = "https://cached.example.com/rss.xml"
        let url = URL(string: urlString)!
        MockURLProtocol.mockResponses[url] = MockURLProtocol.MockResponse(
            statusCode: 304, headers: [:], data: nil, redirectURL: nil
        )
        let feed = Feed(title: "Cached", url: urlString, category: "Tech")
        context.insert(feed)
        try context.save()

        let results = await BackgroundFeedSync.parseAllFeedsInBackground(
            requests: [FeedFetchRequest(
                id: feed.persistentModelID, url: urlString,
                lastModified: "Mon, 23 Oct 2023 10:00:00 GMT", etag: "\"abc\""
            )],
            session: mockSession
        )

        XCTAssertEqual(results.count, 1)
        XCTAssertFalse(results[0].wasModified)
        XCTAssertTrue(results[0].articles.isEmpty)
        XCTAssertEqual(results[0].newEtag, "\"abc\"", "304 preserves the cached validators")
    }

    // MARK: - Cancellation

    /// Cancelling must stop scheduling new work while keeping what already succeeded, rather
    /// than discarding the whole phase.
    func testCancellationStopsSchedulingAndKeepsPartialResults() async throws {
        let requests = try makeRequests(count: 30, slowIndices: Set(0..<30), delay: 0.2)

        let task = Task {
            await BackgroundFeedSync.parseAllFeedsInBackground(
                requests: requests, session: mockSession
            )
        }

        // Let a couple of waves complete, then cancel mid-phase.
        try await Task.sleep(for: .milliseconds(500))
        task.cancel()
        let results = await task.value

        XCTAssertLessThan(
            results.count, requests.count,
            "cancellation should have prevented the remaining feeds from being scheduled"
        )
        XCTAssertGreaterThan(
            results.count, 0,
            "feeds that already completed must be kept, not discarded"
        )
    }

    func testCancellationBeforeStartingYieldsNoResults() async throws {
        let requests = try makeRequests(count: 10, slowIndices: Set(0..<10), delay: 0.2)

        let task = Task {
            // Cancelled before the group is primed, so fetchOne's early exit fires.
            await BackgroundFeedSync.parseAllFeedsInBackground(
                requests: requests, session: mockSession
            )
        }
        task.cancel()
        let results = await task.value

        XCTAssertTrue(
            results.isEmpty,
            "a sync cancelled before it began should not issue requests"
        )
    }
}
