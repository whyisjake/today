//
//  HostThrottleTests.swift
//  TodayTests
//
//  Covers per-host request pacing.
//

import XCTest
@testable import Today

final class HostThrottleTests: XCTestCase {

    override func setUp() async throws {
        await HostThrottle.shared.reset()
    }

    override func tearDown() async throws {
        await HostThrottle.shared.reset()
    }

    // MARK: - Which hosts are paced

    /// Subdomains share one budget: `www.reddit.com` and `old.reddit.com` are one service, and
    /// pacing them separately would let a store with feeds on both burst straight into a 429.
    func testRedditSubdomainsShareOneThrottleKey() throws {
        let hosts = [
            "https://www.reddit.com/r/x.rss",
            "https://old.reddit.com/r/x.rss",
            "https://reddit.com/r/x.rss",
        ]
        for host in hosts {
            let url = try XCTUnwrap(URL(string: host))
            XCTAssertEqual(HostThrottle.key(for: url), "reddit.com", "\(host) should share the budget")
        }
    }

    /// Everything else is unthrottled — a typical sync must not be slowed down by this.
    func testOtherHostsAreNotThrottled() throws {
        for host in ["https://techcrunch.com/feed/", "https://xkcd.com/rss.xml", "https://i.redd.it/a.jpg"] {
            let url = try XCTUnwrap(URL(string: host))
            XCTAssertNil(HostThrottle.key(for: url), "\(host) should not be paced")
        }
    }

    // MARK: - Pacing behaviour

    /// The first request goes straight through; nothing should pay a cold-start delay.
    func testFirstRequestToAHostDoesNotWait() async throws {
        let url = try XCTUnwrap(URL(string: "https://www.reddit.com/r/x.rss"))

        let start = Date()
        await HostThrottle.shared.waitForTurn(url)

        XCTAssertLessThan(Date().timeIntervalSince(start), 0.5, "the first request should not be delayed")
    }

    /// An unthrottled host never waits, however many requests it makes.
    func testUnthrottledHostNeverWaits() async throws {
        let url = try XCTUnwrap(URL(string: "https://techcrunch.com/feed/"))

        let start = Date()
        for _ in 0..<5 { await HostThrottle.shared.waitForTurn(url) }

        XCTAssertLessThan(Date().timeIntervalSince(start), 0.5)
    }

    /// The point of the whole file: concurrent callers queue behind each other rather than all
    /// reading the same slot and firing together, which is what produced the 429s.
    func testConcurrentCallersToTheSameHostAreSerialised() async throws {
        let url = try XCTUnwrap(URL(string: "https://www.reddit.com/r/x.rss"))

        // Claim the first slot so the two below must both queue.
        await HostThrottle.shared.waitForTurn(url)

        let start = Date()
        async let first: Void = HostThrottle.shared.waitForTurn(url)
        async let second: Void = HostThrottle.shared.waitForTurn(url)
        _ = await (first, second)
        let elapsed = Date().timeIntervalSince(start)

        // Two queued requests at a 2s interval means the later one waits ~4s, not ~2s: they
        // stack rather than sharing a single slot.
        XCTAssertGreaterThan(elapsed, 3.0, "concurrent callers must not collapse onto one slot")
    }

    // MARK: - 429 handling

    /// A 429 with `Retry-After` is the host stating its own terms; honour them.
    func testRetryAfterHeaderIsHonoured() async throws {
        let url = try XCTUnwrap(URL(string: "https://www.reddit.com/r/x.rss"))

        await HostThrottle.shared.penalize(url, retryAfter: "3")

        let start = Date()
        await HostThrottle.shared.waitForTurn(url)
        XCTAssertGreaterThan(
            Date().timeIntervalSince(start), 2.0,
            "the next request must wait out the interval the host asked for"
        )
    }

    /// A penalty on Reddit must not stall unrelated feeds.
    func testPenaltyOnOneHostDoesNotDelayAnother() async throws {
        let reddit = try XCTUnwrap(URL(string: "https://www.reddit.com/r/x.rss"))
        let other = try XCTUnwrap(URL(string: "https://techcrunch.com/feed/"))

        await HostThrottle.shared.penalize(reddit, retryAfter: "30")

        let start = Date()
        await HostThrottle.shared.waitForTurn(other)
        XCTAssertLessThan(Date().timeIntervalSince(start), 0.5, "other hosts are unaffected")
    }
}
