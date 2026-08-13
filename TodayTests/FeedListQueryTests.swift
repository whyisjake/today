//
//  FeedListQueryTests.swift
//  TodayTests
//
//  Reproduction for a crash when opening a single feed's article list on iOS.
//
//  The per-feed views build their FetchDescriptors in `init`, so a descriptor SwiftData
//  cannot execute takes down the view the moment it is constructed. These exercise the same
//  descriptor shapes directly.
//

import XCTest
import SwiftData
@testable import Today

final class FeedListQueryTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUpWithError() throws {
        try super.setUpWithError()
        let schema = Schema([Feed.self, Article.self, OPMLSubscription.self])
        container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        context = ModelContext(container)
    }

    override func tearDownWithError() throws {
        context = nil
        container = nil
        try super.tearDownWithError()
    }

    @discardableResult
    private func seedFeed(title: String, articles: Int) throws -> Feed {
        let feed = Feed(
            title: title,
            url: "https://\(title.lowercased()).example.com/rss.xml",
            category: "Tech"
        )
        context.insert(feed)
        for index in 0..<articles {
            context.insert(Article(
                title: "\(title) \(index)",
                link: "https://\(title.lowercased()).example.com/\(index)",
                publishedDate: Date(timeIntervalSinceNow: -Double(index) * 60),
                guid: "\(title)-\(index)",
                feed: feed
            ))
        }
        try context.save()
        return feed
    }

    /// The descriptor `FeedArticlesView` builds. This is the screen that crashes.
    func testPerFeedDescriptorExecutes() throws {
        let feed = try seedFeed(title: "Alpha", articles: 5)
        try seedFeed(title: "Beta", articles: 3)

        let feedId = feed.id
        var descriptor = FetchDescriptor<Article>(
            predicate: #Predicate<Article> { $0.feed?.id == feedId },
            sortBy: [SortDescriptor(\Article.publishedDate, order: .reverse)]
        )
        descriptor.fetchLimit = ArticleQuery.defaultFetchLimit
        descriptor.relationshipKeyPathsForPrefetching = [\.feed]

        let results = try context.fetch(descriptor)
        XCTAssertEqual(results.count, 5, "only this feed's articles")
        XCTAssertTrue(results.allSatisfy { $0.feed?.id == feedId })
    }

    /// Same predicate without prefetching, to isolate whether prefetching is the problem.
    func testPerFeedDescriptorWithoutPrefetchExecutes() throws {
        let feed = try seedFeed(title: "Alpha", articles: 5)
        let feedId = feed.id
        var descriptor = FetchDescriptor<Article>(
            predicate: #Predicate<Article> { $0.feed?.id == feedId },
            sortBy: [SortDescriptor(\Article.publishedDate, order: .reverse)]
        )
        descriptor.fetchLimit = ArticleQuery.defaultFetchLimit

        XCTAssertEqual(try context.fetch(descriptor).count, 5)
    }

    /// And with neither, matching what shipped before this change.
    func testPerFeedDescriptorBareExecutes() throws {
        let feed = try seedFeed(title: "Alpha", articles: 5)
        let feedId = feed.id
        let descriptor = FetchDescriptor<Article>(
            predicate: #Predicate<Article> { $0.feed?.id == feedId },
            sortBy: [SortDescriptor(\Article.publishedDate, order: .reverse)]
        )
        XCTAssertEqual(try context.fetch(descriptor).count, 5)
    }

    /// The two descriptors `FeedNewsletterView` builds.
    func testNewsletterDescriptorsExecute() throws {
        let feed = try seedFeed(title: "Alpha", articles: 30)
        // Mark some read so both descriptors return rows.
        let all = try context.fetch(FetchDescriptor<Article>())
        for (index, article) in all.enumerated() where index % 2 == 0 {
            article.isRead = true
        }
        try context.save()

        let feedId = feed.id

        var unread = FetchDescriptor<Article>(
            predicate: #Predicate<Article> { $0.feed?.id == feedId && !$0.isRead },
            sortBy: [SortDescriptor(\Article.publishedDate, order: .reverse)]
        )
        unread.fetchLimit = 15
        unread.relationshipKeyPathsForPrefetching = [\.feed]

        var read = FetchDescriptor<Article>(
            predicate: #Predicate<Article> { $0.feed?.id == feedId && $0.isRead },
            sortBy: [SortDescriptor(\Article.publishedDate, order: .reverse)]
        )
        read.fetchLimit = 15
        read.relationshipKeyPathsForPrefetching = [\.feed]

        XCTAssertEqual(try context.fetch(unread).count, 15)
        XCTAssertEqual(try context.fetch(read).count, 15)
    }

    /// A feed with no articles must return empty rather than trap.
    func testEmptyFeedReturnsNoArticles() throws {
        let feed = try seedFeed(title: "Empty", articles: 0)
        let feedId = feed.id
        var descriptor = FetchDescriptor<Article>(
            predicate: #Predicate<Article> { $0.feed?.id == feedId },
            sortBy: [SortDescriptor(\Article.publishedDate, order: .reverse)]
        )
        descriptor.fetchLimit = ArticleQuery.defaultFetchLimit
        descriptor.relationshipKeyPathsForPrefetching = [\.feed]

        XCTAssertTrue(try context.fetch(descriptor).isEmpty)
    }
}
