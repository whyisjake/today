//
//  OPMLDiffTests.swift
//  TodayTests
//
//  Characterization tests for OPML sync diffing (U7).
//
//  This logic has produced duplicate feeds in the past — `DatabaseMigration.deduplicateFeeds`
//  exists to clean up after it — so the add/skip/deactivate decisions are pinned here before
//  and after being extracted out of the main actor. `computeDiff` is pure, which is the whole
//  reason these can be tested at all.
//

import XCTest
import SwiftData
@testable import Today

final class OPMLDiffTests: XCTestCase {

    private typealias Manager = OPMLSubscriptionManager
    private typealias Parsed = OPMLParser.ParsedFeed

    private func fetched(
        _ feeds: [Parsed],
        title: String? = nil,
        wasModified: Bool = true
    ) -> Manager.FetchedOPML {
        Manager.FetchedOPML(
            wasModified: wasModified,
            feeds: feeds,
            opmlTitle: title,
            lastModified: nil,
            etag: nil
        )
    }

    /// Real `PersistentIdentifier`s, since `ManagedFeedSnapshot` carries them.
    private func makeFeedIDs(_ count: Int) throws -> [PersistentIdentifier] {
        let schema = Schema([Feed.self, Article.self, OPMLSubscription.self])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        let context = ModelContext(container)
        var ids: [PersistentIdentifier] = []
        for index in 0..<count {
            let feed = Feed(
                title: "F\(index)",
                url: "https://example.com/\(index)/feed.xml",
                category: "Tech"
            )
            context.insert(feed)
            ids.append(feed.persistentModelID)
        }
        try context.save()
        return ids
    }

    // MARK: - Adding

    func testFeedPresentRemotelyButNotLocallyIsAdded() throws {
        let diff = Manager.computeDiff(
            fetched: fetched([Parsed(url: "https://a.example.com/feed", title: "A", category: "Tech")]),
            managed: [],
            defaultCategory: "News"
        )
        XCTAssertEqual(diff.feedsToAdd.map(\.url), ["https://a.example.com/feed"])
        XCTAssertTrue(diff.feedIDsToDeactivate.isEmpty)
    }

    func testGeneralCategoryResolvesToTheSubscriptionDefault() throws {
        let diff = Manager.computeDiff(
            fetched: fetched([
                Parsed(url: "https://a.example.com/feed", title: "A", category: "general"),
                Parsed(url: "https://b.example.com/feed", title: "B", category: "General"),
                Parsed(url: "https://c.example.com/feed", title: "C", category: "Sports"),
            ]),
            managed: [],
            defaultCategory: "News"
        )
        XCTAssertEqual(
            diff.feedsToAdd.map(\.category),
            ["News", "News", "Sports"],
            "both spellings of general resolve to the default; anything else is preserved"
        )
    }

    /// U3: an OPML document is attacker-controlled, so an `xmlUrl` with a non-web scheme is
    /// dropped at the diff rather than being stored and handed to URLSession.
    func testEntryWithDisallowedSchemeIsNotAdded() throws {
        let diff = Manager.computeDiff(
            fetched: fetched([
                Parsed(url: "file:///etc/passwd", title: "Hostile", category: "Tech"),
                Parsed(url: "data:text/xml,<opml/>", title: "Hostile", category: "Tech"),
                Parsed(url: "javascript:alert(1)", title: "Hostile", category: "Tech"),
                Parsed(url: "ftp://evil.example.com/feed", title: "Hostile", category: "Tech"),
                Parsed(url: "https://a.example.com/feed", title: "A", category: "Tech"),
            ]),
            managed: [],
            defaultCategory: "News"
        )
        XCTAssertEqual(
            diff.feedsToAdd.map(\.url),
            ["https://a.example.com/feed"],
            "only the http(s) entry survives the scheme allow-list"
        )
    }

    /// The dropped entries must not affect the deactivation set either — a hostile `xmlUrl`
    /// should be invisible to the diff, not a way to keep something alive or kill it.
    func testDisallowedSchemeEntriesDoNotAffectDeactivation() throws {
        let ids = try makeFeedIDs(1)
        let diff = Manager.computeDiff(
            fetched: fetched([Parsed(url: "file:///etc/passwd", title: "Hostile", category: "Tech")]),
            managed: [Manager.ManagedFeedSnapshot(
                id: ids[0], url: "https://a.example.com/feed", sourceURL: nil
            )],
            defaultCategory: "News"
        )
        XCTAssertTrue(diff.feedsToAdd.isEmpty)
        XCTAssertEqual(
            diff.feedIDsToDeactivate, [ids[0]],
            "the managed feed is still missing from the (effectively empty) remote list"
        )
    }

    func testAlreadyManagedFeedIsNotAddedAgain() throws {
        let ids = try makeFeedIDs(1)
        let diff = Manager.computeDiff(
            fetched: fetched([Parsed(url: "https://a.example.com/feed", title: "A", category: "Tech")]),
            managed: [Manager.ManagedFeedSnapshot(
                id: ids[0], url: "https://a.example.com/feed", sourceURL: nil
            )],
            defaultCategory: "News"
        )
        XCTAssertTrue(diff.feedsToAdd.isEmpty, "re-adding a managed feed is how duplicates appear")
        XCTAssertTrue(diff.feedIDsToDeactivate.isEmpty)
    }

    /// The redirect case: the stored `url` differs from the OPML's URL, and `sourceURL` holds
    /// the original. Matching must use `sourceURL`, or every sync would re-add the feed.
    func testFeedMatchedBySourceURLIsNotAddedAgain() throws {
        let ids = try makeFeedIDs(1)
        let diff = Manager.computeDiff(
            fetched: fetched([Parsed(url: "https://a.example.com/feed", title: "A", category: "Tech")]),
            managed: [Manager.ManagedFeedSnapshot(
                id: ids[0],
                url: "https://cdn.a.example.com/feed",      // after redirect
                sourceURL: "https://a.example.com/feed"     // as listed in the OPML
            )],
            defaultCategory: "News"
        )
        XCTAssertTrue(
            diff.feedsToAdd.isEmpty,
            "matching on sourceURL is what stops a redirected feed being re-added every sync"
        )
        XCTAssertTrue(diff.feedIDsToDeactivate.isEmpty)
    }

    // MARK: - Churn: the OPML lists a URL in a form addFeed does not store

    /// Reproduces feed churn seen in a real device log: `+15 added, -15 deactivated` on every
    /// single sync of the same unchanged subscription.
    ///
    /// `FeedManager.addFeed` upgrades `http://` to `https://` and stores the feed under the
    /// https URL, but OPML matching compares against the URL as listed. So an http-listed feed
    /// looks *missing* (deactivated) and its OPML entry looks *new* (re-added) forever. Worse,
    /// the re-add is a no-op — `addFeed` returns the existing feed without clearing `isActive` —
    /// so the feed stays deactivated and silently stops syncing.
    func testHTTPListedFeedStoredAsHTTPSDoesNotChurn() throws {
        let ids = try makeFeedIDs(1)
        let diff = Manager.computeDiff(
            fetched: fetched([Parsed(
                url: "http://techcrunch.com/feed/", title: "TechCrunch", category: "all"
            )]),
            managed: [Manager.ManagedFeedSnapshot(
                id: ids[0], url: "https://techcrunch.com/feed/", sourceURL: nil
            )],
            defaultCategory: "News"
        )

        XCTAssertTrue(
            diff.feedsToAdd.isEmpty,
            "an http-listed feed already stored as https must not be re-added"
        )
        XCTAssertTrue(
            diff.feedIDsToDeactivate.isEmpty,
            "…and must not be deactivated, which is what silently stops it syncing"
        )
    }

    /// Same shape for Reddit, which addFeed rewrites to a .rss URL.
    func testRedditFeedStoredAsRSSDoesNotChurn() throws {
        let ids = try makeFeedIDs(1)
        let diff = Manager.computeDiff(
            fetched: fetched([Parsed(
                url: "https://www.reddit.com/r/swift", title: "r/swift", category: "all"
            )]),
            managed: [Manager.ManagedFeedSnapshot(
                id: ids[0], url: "https://www.reddit.com/r/swift.rss", sourceURL: nil
            )],
            defaultCategory: "News"
        )
        XCTAssertTrue(diff.feedsToAdd.isEmpty)
        XCTAssertTrue(diff.feedIDsToDeactivate.isEmpty)
    }

    /// An http-only domain is exempt from the https upgrade, so it must still match as http.
    func testHTTPOnlyDomainStillMatches() throws {
        let ids = try makeFeedIDs(1)
        let diff = Manager.computeDiff(
            fetched: fetched([Parsed(
                url: "http://scripting.com/rss.xml", title: "Scripting", category: "all"
            )]),
            managed: [Manager.ManagedFeedSnapshot(
                id: ids[0], url: "http://scripting.com/rss.xml", sourceURL: nil
            )],
            defaultCategory: "News"
        )
        XCTAssertTrue(diff.feedsToAdd.isEmpty)
        XCTAssertTrue(diff.feedIDsToDeactivate.isEmpty)
    }

    /// Repairing existing damage: a managed feed present in the remote OPML must be marked for
    /// reactivation, otherwise feeds already stuck at isActive = false stay stuck even after
    /// the matching bug is fixed.
    func testManagedFeedPresentInRemoteIsMarkedForReactivation() throws {
        let ids = try makeFeedIDs(1)
        let diff = Manager.computeDiff(
            fetched: fetched([Parsed(
                url: "http://techcrunch.com/feed/", title: "TechCrunch", category: "all"
            )]),
            managed: [Manager.ManagedFeedSnapshot(
                id: ids[0], url: "https://techcrunch.com/feed/", sourceURL: nil, isActive: false
            )],
            defaultCategory: "News"
        )
        XCTAssertEqual(
            diff.feedIDsToReactivate, [ids[0]],
            "a feed still listed in the OPML should be reactivated if it was deactivated"
        )
    }

    func testActiveFeedStillListedIsNotMarkedForReactivation() throws {
        let ids = try makeFeedIDs(1)
        let diff = Manager.computeDiff(
            fetched: fetched([Parsed(
                url: "http://techcrunch.com/feed/", title: "TechCrunch", category: "all"
            )]),
            managed: [Manager.ManagedFeedSnapshot(
                id: ids[0], url: "https://techcrunch.com/feed/", sourceURL: nil, isActive: true
            )],
            defaultCategory: "News"
        )
        XCTAssertTrue(
            diff.feedIDsToReactivate.isEmpty,
            "an already-active feed needs no write; this is what keeps a settled sync a no-op"
        )
    }

    // MARK: - Deactivating

    func testManagedFeedMissingFromRemoteIsDeactivated() throws {
        let ids = try makeFeedIDs(2)
        let diff = Manager.computeDiff(
            fetched: fetched([Parsed(url: "https://a.example.com/feed", title: "A", category: "Tech")]),
            managed: [
                Manager.ManagedFeedSnapshot(id: ids[0], url: "https://a.example.com/feed", sourceURL: nil),
                Manager.ManagedFeedSnapshot(id: ids[1], url: "https://gone.example.com/feed", sourceURL: nil),
            ],
            defaultCategory: "News"
        )
        XCTAssertEqual(diff.feedIDsToDeactivate, [ids[1]])
        XCTAssertTrue(diff.feedsToAdd.isEmpty)
    }

    func testDeactivationAlsoMatchesOnSourceURL() throws {
        let ids = try makeFeedIDs(1)
        let diff = Manager.computeDiff(
            fetched: fetched([]), // remote OPML is now empty
            managed: [Manager.ManagedFeedSnapshot(
                id: ids[0],
                url: "https://cdn.a.example.com/feed",
                sourceURL: "https://a.example.com/feed"
            )],
            defaultCategory: "News"
        )
        XCTAssertEqual(diff.feedIDsToDeactivate, [ids[0]])
    }

    func testEmptyRemoteDeactivatesEverythingManaged() throws {
        let ids = try makeFeedIDs(3)
        let managed = ids.enumerated().map { index, id in
            Manager.ManagedFeedSnapshot(
                id: id, url: "https://example.com/\(index)/feed.xml", sourceURL: nil
            )
        }
        let diff = Manager.computeDiff(fetched: fetched([]), managed: managed, defaultCategory: "News")
        XCTAssertEqual(Set(diff.feedIDsToDeactivate), Set(ids))
    }

    // MARK: - Combined and idempotency

    func testAddAndDeactivateInTheSameSync() throws {
        let ids = try makeFeedIDs(1)
        let diff = Manager.computeDiff(
            fetched: fetched([Parsed(url: "https://new.example.com/feed", title: "N", category: "Tech")]),
            managed: [Manager.ManagedFeedSnapshot(
                id: ids[0], url: "https://old.example.com/feed", sourceURL: nil
            )],
            defaultCategory: "News"
        )
        XCTAssertEqual(diff.feedsToAdd.map(\.url), ["https://new.example.com/feed"])
        XCTAssertEqual(diff.feedIDsToDeactivate, [ids[0]])
    }

    /// Running the same sync twice must be a no-op the second time. This is the property that
    /// actually prevents duplicate feeds; a repeated non-empty `feedsToAdd` is the bug.
    func testDiffIsIdempotentOnceApplied() throws {
        let ids = try makeFeedIDs(1)
        let remote = [Parsed(url: "https://a.example.com/feed", title: "A", category: "Tech")]

        let first = Manager.computeDiff(fetched: fetched(remote), managed: [], defaultCategory: "News")
        XCTAssertEqual(first.feedsToAdd.count, 1)

        // Simulate the feed now being managed, then diff again.
        let second = Manager.computeDiff(
            fetched: fetched(remote),
            managed: [Manager.ManagedFeedSnapshot(
                id: ids[0], url: "https://a.example.com/feed", sourceURL: nil
            )],
            defaultCategory: "News"
        )
        XCTAssertEqual(second, Manager.OPMLDiff(), "a settled subscription must diff to nothing")
    }

    // MARK: - Title

    func testNonEmptyOPMLTitleIsCarried() throws {
        let diff = Manager.computeDiff(
            fetched: fetched([], title: "My Reading List"), managed: [], defaultCategory: "News"
        )
        XCTAssertEqual(diff.newTitle, "My Reading List")
    }

    func testEmptyOrMissingOPMLTitleIsIgnored() throws {
        XCTAssertNil(
            Manager.computeDiff(fetched: fetched([], title: ""), managed: [], defaultCategory: "News").newTitle,
            "an empty title must not overwrite the subscription's existing one"
        )
        XCTAssertNil(
            Manager.computeDiff(fetched: fetched([], title: nil), managed: [], defaultCategory: "News").newTitle
        )
    }

    // MARK: - Isolation

    /// `fetchAndParse` opens with `assert(!Thread.isMainThread)`. XCTest calls from the main
    /// thread, so if `@concurrent` ever stops taking effect — for example if someone
    /// "simplifies" it to plain `nonisolated`, which under SWIFT_APPROACHABLE_CONCURRENCY
    /// runs on the caller's executor — this test traps instead of quietly putting network and
    /// XML parsing back on the main thread.
    ///
    /// The empty URL makes it throw before any network access, so the test stays hermetic.
    func testFetchAndParseRunsOffTheMainThread() async {
        let snapshot = Manager.SubscriptionSnapshot(
            url: "",
            title: "Broken",
            defaultCategory: "News",
            httpLastModified: nil,
            httpEtag: nil
        )

        do {
            _ = try await Manager.fetchAndParse(snapshot)
            XCTFail("an empty URL should have thrown")
        } catch {
            // Reaching here means the off-main assertion inside did not trip.
        }
    }

    // MARK: - Applying deactivations off-main

    func testDeactivateFeedsSetsIsActiveFalseAndReportsCount() async throws {
        let schema = Schema([Feed.self, Article.self, OPMLSubscription.self])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        let context = ModelContext(container)
        let keep = Feed(title: "Keep", url: "https://keep.example.com/feed", category: "Tech")
        let drop = Feed(title: "Drop", url: "https://drop.example.com/feed", category: "Tech")
        context.insert(keep)
        context.insert(drop)
        try context.save()

        let count = await OPMLSubscriptionManager.setFeedsActive(
            false, ids: [drop.persistentModelID], container: container
        )
        XCTAssertEqual(count, 1)

        let verify = ModelContext(container)
        let feeds = try verify.fetch(FetchDescriptor<Feed>())
        XCTAssertEqual(feeds.first { $0.title == "Drop" }?.isActive, false)
        XCTAssertEqual(feeds.first { $0.title == "Keep" }?.isActive, true, "unrelated feeds untouched")
    }

    func testSetFeedsActiveWithNoIDsIsANoOp() async throws {
        let schema = Schema([Feed.self, Article.self, OPMLSubscription.self])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        let count = await OPMLSubscriptionManager.setFeedsActive(false, ids: [], container: container)
        XCTAssertEqual(count, 0)
    }

    func testManagedFeedSnapshotsReturnOnlyThisSubscriptionsFeeds() async throws {
        let schema = Schema([Feed.self, Article.self, OPMLSubscription.self])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        let context = ModelContext(container)

        let mine = Feed(title: "Mine", url: "https://mine.example.com/feed", category: "Tech")
        mine.opmlSubscriptionURL = "https://list.example.com/opml"
        let theirs = Feed(title: "Theirs", url: "https://theirs.example.com/feed", category: "Tech")
        theirs.opmlSubscriptionURL = "https://other.example.com/opml"
        let userAdded = Feed(title: "User", url: "https://user.example.com/feed", category: "Tech")
        context.insert(mine)
        context.insert(theirs)
        context.insert(userAdded)
        try context.save()

        let snapshots = await OPMLSubscriptionManager.managedFeedSnapshots(
            subscriptionURL: "https://list.example.com/opml", container: container
        )
        XCTAssertEqual(snapshots.map(\.url), ["https://mine.example.com/feed"])
    }

    /// A user-added feed must never be deactivated by an OPML sync, because it is not in the
    /// managed set to begin with.
    func testUserAddedFeedsAreNeverInTheDeactivationSet() throws {
        let ids = try makeFeedIDs(1)
        // managed contains only subscription-owned feeds; a user feed simply isn't here.
        let diff = Manager.computeDiff(
            fetched: fetched([]),
            managed: [Manager.ManagedFeedSnapshot(
                id: ids[0], url: "https://managed.example.com/feed", sourceURL: nil
            )],
            defaultCategory: "News"
        )
        XCTAssertEqual(diff.feedIDsToDeactivate, [ids[0]])
        XCTAssertEqual(diff.feedIDsToDeactivate.count, 1, "only managed feeds are ever deactivated")
    }
}
