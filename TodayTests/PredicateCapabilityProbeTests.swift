//
//  PredicateCapabilityProbeTests.swift
//  TodayTests
//
//  What can actually move from Swift array filtering into a #Predicate?
//
//  U3 replaces TodayView's in-view filtering with database predicates. These tests pin
//  which operations the predicate macro accepts, and — more importantly — pin the exact
//  semantics the current Swift filters have for edge cases (mixed-case categories,
//  articles with no feed), so a predicate rewrite can be checked against them rather
//  than guessed at.
//
//  Key constraint found here: `lowercased()` is rejected by the #Predicate macro at
//  COMPILE time ("The lowercased() function is not supported in this predicate").
//  TodayView's alt-visibility filter is written as
//  `feed?.category.lowercased() == "alt"`, so it cannot be ported literally. The
//  workaround pinned below is to resolve the concrete category spellings present in the
//  data first, then match against those with `contains`.
//

import XCTest
import SwiftData
@testable import Today

final class PredicateCapabilityProbeTests: XCTestCase {

    private func makeSeededContext() throws -> ModelContext {
        let schema = Schema([Feed.self, Article.self, OPMLSubscription.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)

        // Deliberately mixed casing — the reason lowercased() is in the view today.
        let categories = ["Alt", "alt", "Tech", "News"]
        for (index, category) in categories.enumerated() {
            let feed = Feed(
                title: "Feed \(category)",
                url: "https://example.com/\(index)/feed.xml",
                category: category
            )
            context.insert(feed)
            let article = Article(
                title: "Article in \(category)",
                link: "https://example.com/\(index)/1",
                publishedDate: Date(),
                guid: "guid-\(index)",
                feed: feed
            )
            article.isRead = index % 2 == 0
            article.isFavorite = index == 0
            if index == 2 { article.audioUrl = "https://example.com/a.mp3" }
            context.insert(article)
        }
        // An article with no feed — exercises optional relationship traversal.
        context.insert(Article(
            title: "Orphan",
            link: "https://example.com/orphan",
            publishedDate: Date(),
            guid: "guid-orphan"
        ))
        try context.save()
        return context
    }

    // MARK: - Supported operations

    func testDatePredicateIsSupported() throws {
        let context = try makeSeededContext()
        let cutoff = Date(timeIntervalSinceNow: -3600)
        let found = try context.fetch(FetchDescriptor<Article>(
            predicate: #Predicate { $0.publishedDate >= cutoff }
        ))
        XCTAssertEqual(found.count, 5)
    }

    func testRelationshipTraversalEqualityIsSupported() throws {
        let context = try makeSeededContext()
        let found = try context.fetch(FetchDescriptor<Article>(
            predicate: #Predicate { $0.feed?.category == "Tech" }
        ))
        XCTAssertEqual(found.map(\.title), ["Article in Tech"])
    }

    func testOptionalStringNotNilIsSupported() throws {
        let context = try makeSeededContext()
        let found = try context.fetch(FetchDescriptor<Article>(
            predicate: #Predicate { $0.audioUrl != nil }
        ))
        XCTAssertEqual(found.map(\.title), ["Article in Tech"])
    }

    func testBooleanFlagsAreSupported() throws {
        let context = try makeSeededContext()
        let unread = try context.fetch(FetchDescriptor<Article>(
            predicate: #Predicate { !$0.isRead }
        ))
        let favorites = try context.fetch(FetchDescriptor<Article>(
            predicate: #Predicate { $0.isFavorite }
        ))
        XCTAssertEqual(unread.count, 3) // indices 1, 3 + orphan
        XCTAssertEqual(favorites.map(\.title), ["Article in Alt"])
    }

    // MARK: - The alt-visibility workaround

    // Ruled out, and NOT testable: `altSpellings.contains($0.feed.flatMap { $0.category } ?? "")`
    // compiles, but CoreData cannot lower it to SQL and fails at fetch time with
    // "unimplemented SQL generation for predicate ... (bad LHS)" — the flatMap/?? becomes a
    // nested TERNARY. It raises an ObjC NSException rather than throwing a Swift error, so
    // XCTAssertThrowsError cannot catch it and it cannot be pinned by a test. Documented
    // here instead. Do not reach for this form.

    /// What works: direct `==` / `!=` against a traversed optional relationship, as a small
    /// disjunction over the concrete spellings present in the data.
    func testAltShownDisjunctionMatchesSwiftFilter() throws {
        let context = try makeSeededContext()
        let all = try context.fetch(FetchDescriptor<Article>())

        let altOnly = try context.fetch(FetchDescriptor<Article>(
            predicate: #Predicate { $0.feed?.category == "Alt" || $0.feed?.category == "alt" }
        ))
        XCTAssertEqual(
            Set(altOnly.map(\.title)),
            Set(all.filter { $0.feed?.category.lowercased() == "alt" }.map(\.title)),
            "disjunction over spellings must equal lowercased() equality"
        )
    }

    /// THE TRAP. A conjunction of inequalities silently drops articles with no feed,
    /// because in SQL `NULL != 'Alt'` evaluates to NULL rather than true. Swift's
    /// `feed?.category.lowercased() != "alt"` evaluates to true for a nil feed, so a
    /// literal port of the view's filter would make feed-less articles disappear from the
    /// default (alt-hidden) list — an R3 violation that no amount of category-level
    /// testing would surface.
    func testNaiveAltHiddenPredicateDropsFeedLessArticles() throws {
        let context = try makeSeededContext()

        let naive = try context.fetch(FetchDescriptor<Article>(
            predicate: #Predicate { $0.feed?.category != "Alt" && $0.feed?.category != "alt" }
        ))
        XCTAssertFalse(
            naive.contains { $0.title == "Orphan" },
            "documents the trap: NULL != 'Alt' is NULL, so the orphan is dropped"
        )
    }

    /// The correct alt-hidden form: admit nil feeds explicitly.
    func testAltHiddenPredicateWithExplicitNilMatchesSwiftFilter() throws {
        let context = try makeSeededContext()
        let all = try context.fetch(FetchDescriptor<Article>())

        let corrected = try context.fetch(FetchDescriptor<Article>(
            predicate: #Predicate {
                $0.feed == nil || ($0.feed?.category != "Alt" && $0.feed?.category != "alt")
            }
        ))
        XCTAssertEqual(
            Set(corrected.map(\.title)),
            Set(all.filter { $0.feed?.category.lowercased() != "alt" }.map(\.title)),
            "explicit nil admission must reproduce the Swift filter exactly, orphan included"
        )
        XCTAssertTrue(corrected.contains { $0.title == "Orphan" })
    }

    /// The same NULL trap applies to plain category selection: today's Swift filter
    /// `feed?.category == selected` excludes nil-feed articles, and the predicate form
    /// agrees here — pinned so the asymmetry with the negated case is explicit.
    func testCategorySelectionPredicateExcludesFeedLessArticlesLikeSwift() throws {
        let context = try makeSeededContext()
        let all = try context.fetch(FetchDescriptor<Article>())

        let predicate = try context.fetch(FetchDescriptor<Article>(
            predicate: #Predicate { $0.feed?.category == "Tech" }
        ))
        XCTAssertEqual(
            Set(predicate.map(\.title)),
            Set(all.filter { $0.feed?.category == "Tech" }.map(\.title))
        )
        XCTAssertFalse(predicate.contains { $0.title == "Orphan" })
    }

    /// Records how the feed-less article is treated today, since it is asymmetric and
    /// easy to get wrong: shown when alt is hidden, hidden when alt is shown.
    func testFeedLessArticleIsAsymmetricUnderAltFiltering() throws {
        let context = try makeSeededContext()
        let all = try context.fetch(FetchDescriptor<Article>())

        XCTAssertTrue(
            all.filter { $0.feed?.category.lowercased() != "alt" }.contains { $0.title == "Orphan" },
            "alt-hidden INCLUDES feed-less articles (nil != \"alt\")"
        )
        XCTAssertFalse(
            all.filter { $0.feed?.category.lowercased() == "alt" }.contains { $0.title == "Orphan" },
            "alt-shown EXCLUDES feed-less articles"
        )
    }
}
