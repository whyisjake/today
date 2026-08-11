//
//  ModelSchemaTests.swift
//  TodayTests
//
//  Schema-level tests for the Article/Feed models.
//
//  These guard the index additions from U2. Adding an #Index is a lightweight SwiftData
//  migration, but it is still a store change — the important cases are that an existing
//  store opens without data loss, and that the guid index did not become a uniqueness
//  constraint (GUIDs are only unique within a feed).
//

import XCTest
import SwiftData
@testable import Today

final class ModelSchemaTests: XCTestCase {

    private var storeURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        storeURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("schema-test-\(UUID().uuidString).store")
    }

    override func tearDownWithError() throws {
        // SwiftData writes sidecar files alongside the store; clear them all.
        if let storeURL {
            let fm = FileManager.default
            for suffix in ["", "-shm", "-wal"] {
                let url = URL(fileURLWithPath: storeURL.path + suffix)
                if fm.fileExists(atPath: url.path) {
                    try? fm.removeItem(at: url)
                }
            }
        }
        storeURL = nil
        try super.tearDownWithError()
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Feed.self, Article.self, OPMLSubscription.self])
        let config = ModelConfiguration(schema: schema, url: storeURL)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private func makeInMemoryContainer() throws -> ModelContainer {
        let schema = Schema([Feed.self, Article.self, OPMLSubscription.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    // MARK: - Fresh store

    func testFreshStoreCreatesAndRoundTrips() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)

        let feed = Feed(title: "Example", url: "https://example.com/feed.xml", category: "Tech")
        context.insert(feed)
        let article = Article(
            title: "Hello",
            link: "https://example.com/1",
            publishedDate: Date(),
            guid: "guid-1",
            feed: feed
        )
        context.insert(article)
        try context.save()

        let feeds = try context.fetch(FetchDescriptor<Feed>())
        let articles = try context.fetch(FetchDescriptor<Article>())
        XCTAssertEqual(feeds.count, 1)
        XCTAssertEqual(articles.count, 1)
        XCTAssertEqual(articles.first?.feed?.title, "Example")
    }

    // MARK: - Migration of an existing store

    func testExistingStoreOpensWithoutDataLoss() throws {
        // Write a store, close it, reopen it — the reopen exercises the migration path
        // against data that already exists on disk.
        let expectedFeeds = 3
        let expectedArticles = 12

        do {
            let container = try makeContainer()
            let context = ModelContext(container)
            for feedIndex in 0..<expectedFeeds {
                let feed = Feed(
                    title: "Feed \(feedIndex)",
                    url: "https://example.com/\(feedIndex)/feed.xml",
                    category: "Tech"
                )
                context.insert(feed)
                for articleIndex in 0..<(expectedArticles / expectedFeeds) {
                    context.insert(Article(
                        title: "Article \(feedIndex)-\(articleIndex)",
                        link: "https://example.com/\(feedIndex)/\(articleIndex)",
                        publishedDate: Date(timeIntervalSinceNow: -Double(articleIndex) * 3600),
                        guid: "guid-\(feedIndex)-\(articleIndex)",
                        feed: feed
                    ))
                }
            }
            try context.save()
        }

        // Reopen from disk.
        let reopened = try makeContainer()
        let context = ModelContext(reopened)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Feed>()), expectedFeeds)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Article>()), expectedArticles)
    }

    // MARK: - The guid index must not be a uniqueness constraint

    func testDuplicateGUIDsAcrossDifferentFeedsAreAllowed() throws {
        // Two feeds legitimately carrying the same GUID must both persist. If the guid
        // index were ever changed to #Unique, this would silently upsert and lose one.
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)

        let feedA = Feed(title: "A", url: "https://a.example.com/feed.xml", category: "Tech")
        let feedB = Feed(title: "B", url: "https://b.example.com/feed.xml", category: "Tech")
        context.insert(feedA)
        context.insert(feedB)

        let sharedGUID = "http://shared.example.com/post/1"
        context.insert(Article(title: "From A", link: "https://a.example.com/1",
                               publishedDate: Date(), guid: sharedGUID, feed: feedA))
        context.insert(Article(title: "From B", link: "https://b.example.com/1",
                               publishedDate: Date(), guid: sharedGUID, feed: feedB))
        try context.save()

        let matching = try context.fetch(
            FetchDescriptor<Article>(predicate: #Predicate { $0.guid == sharedGUID })
        )
        XCTAssertEqual(matching.count, 2, "duplicate GUIDs across feeds must both persist")
        XCTAssertEqual(Set(matching.compactMap { $0.feed?.title }), ["A", "B"])
    }

    func testDuplicateGUIDsWithinTheSameFeedAlsoPersist() throws {
        // Dedup is enforced in application code (BackgroundFeedSync), not by the schema.
        // Pinning that so a future #Unique change is a deliberate, visible decision.
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)

        let feed = Feed(title: "A", url: "https://a.example.com/feed.xml", category: "Tech")
        context.insert(feed)
        context.insert(Article(title: "First", link: "https://a.example.com/1",
                               publishedDate: Date(), guid: "dupe", feed: feed))
        context.insert(Article(title: "Second", link: "https://a.example.com/2",
                               publishedDate: Date(), guid: "dupe", feed: feed))
        try context.save()

        XCTAssertEqual(
            try context.fetchCount(FetchDescriptor<Article>(predicate: #Predicate { $0.guid == "dupe" })),
            2,
            "the guid index must not deduplicate; dedup is application-level"
        )
    }

    // MARK: - Indexed predicates return correct results

    func testDateWindowPredicateReturnsOnlyArticlesInWindow() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        let feed = Feed(title: "A", url: "https://a.example.com/feed.xml", category: "Tech")
        context.insert(feed)

        // One article per day going back 10 days.
        for dayOffset in 0..<10 {
            context.insert(Article(
                title: "Day \(dayOffset)",
                link: "https://a.example.com/\(dayOffset)",
                publishedDate: Date(timeIntervalSinceNow: -Double(dayOffset) * 86_400),
                guid: "guid-\(dayOffset)",
                feed: feed
            ))
        }
        try context.save()

        let cutoff = Date(timeIntervalSinceNow: -3.5 * 86_400)
        let windowed = try context.fetch(FetchDescriptor<Article>(
            predicate: #Predicate { $0.publishedDate >= cutoff },
            sortBy: [SortDescriptor(\.publishedDate, order: .reverse)]
        ))

        XCTAssertEqual(windowed.count, 4, "days 0-3 fall inside a 3.5-day window")
        XCTAssertEqual(windowed.map(\.title), ["Day 0", "Day 1", "Day 2", "Day 3"])
    }

    func testFetchCountMatchesFilteredFetchForReadAndFavourite() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        let feed = Feed(title: "A", url: "https://a.example.com/feed.xml", category: "Tech")
        context.insert(feed)

        for index in 0..<20 {
            let article = Article(
                title: "Article \(index)",
                link: "https://a.example.com/\(index)",
                publishedDate: Date(timeIntervalSinceNow: -Double(index) * 60),
                guid: "guid-\(index)",
                feed: feed
            )
            article.isRead = index % 4 == 0      // 5 read, 15 unread
            article.isFavorite = index % 5 == 0  // 4 favorites
            context.insert(article)
        }
        try context.save()

        let unreadCount = try context.fetchCount(
            FetchDescriptor<Article>(predicate: #Predicate { !$0.isRead })
        )
        let favouriteCount = try context.fetchCount(
            FetchDescriptor<Article>(predicate: #Predicate { $0.isFavorite })
        )

        // fetchCount must agree with materialising and filtering, since U3 replaces the
        // array-filter counts with fetchCount.
        let all = try context.fetch(FetchDescriptor<Article>())
        XCTAssertEqual(unreadCount, all.filter { !$0.isRead }.count)
        XCTAssertEqual(favouriteCount, all.filter { $0.isFavorite }.count)
        XCTAssertEqual(unreadCount, 15)
        XCTAssertEqual(favouriteCount, 4)
    }

    func testActiveFeedPredicateExcludesInactiveFeeds() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)

        let active = Feed(title: "Active", url: "https://a.example.com/feed.xml", category: "Tech")
        let inactive = Feed(title: "Inactive", url: "https://b.example.com/feed.xml", category: "Tech")
        inactive.isActive = false
        context.insert(active)
        context.insert(inactive)
        try context.save()

        let fetched = try context.fetch(
            FetchDescriptor<Feed>(predicate: #Predicate<Feed> { $0.isActive })
        )
        XCTAssertEqual(fetched.map(\.title), ["Active"])
    }
}
