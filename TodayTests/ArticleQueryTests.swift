//
//  ArticleQueryTests.swift
//  TodayTests
//
//  R3 enforcement for U3: the bounded-query pipeline must return exactly the articles the
//  pre-change in-view filter chain returned.
//
//  `referenceFilter` below is a deliberate transcription of TodayView.filteredArticles as
//  it was before U3 — fetch everything, then filter in Swift. Every equivalence test
//  compares the new pipeline (bounded FetchDescriptor + ArticleQuery.derive) against it.
//  If someone changes the query and the two diverge, these fail, which is the whole point:
//  "same articles visible" is otherwise unfalsifiable.
//

import XCTest
import SwiftData
@testable import Today

final class ArticleQueryTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!

    /// Fixed reference point so date-window maths is deterministic.
    private let now = Date(timeIntervalSince1970: 1_760_000_000) // 2025-10-09T07:33:20Z
    private let podcastsTitle = "Podcasts"

    override func setUpWithError() throws {
        try super.setUpWithError()
        let schema = Schema([Feed.self, Article.self, OPMLSubscription.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: [config])
        context = ModelContext(container)
        try seed()
    }

    override func tearDownWithError() throws {
        context = nil
        container = nil
        try super.tearDownWithError()
    }

    // MARK: - Fixture

    /// Mixed categories (including both "Alt" and "alt" spellings), a spread of dates
    /// across 12 days, read/favourite/podcast variation, and one article with no feed.
    private func seed() throws {
        let categories = ["Technology", "News", "Alt", "alt", "Personal"]

        for (feedIndex, category) in categories.enumerated() {
            let feed = Feed(
                title: "Feed \(category) \(feedIndex)",
                url: "https://example.com/\(feedIndex)/feed.xml",
                category: category
            )
            context.insert(feed)

            for dayOffset in 0..<12 {
                let article = Article(
                    title: "\(category) day \(dayOffset)",
                    link: "https://example.com/\(feedIndex)/\(dayOffset)",
                    articleDescription: dayOffset % 3 == 0 ? "searchable needle text" : "other body",
                    publishedDate: now.addingTimeInterval(-Double(dayOffset) * 86_400 - 3600),
                    guid: "guid-\(feedIndex)-\(dayOffset)",
                    feed: feed
                )
                article.isRead = dayOffset % 2 == 0
                article.isFavorite = dayOffset % 5 == 0
                if dayOffset % 6 == 0 {
                    article.audioUrl = "https://example.com/\(feedIndex)/\(dayOffset).mp3"
                    article.audioType = "audio/mpeg"
                }
                context.insert(article)
            }
        }

        // Feed-less article, inside the 1-day window. This is the case a naive predicate
        // port silently drops (see PredicateCapabilityProbeTests).
        let orphan = Article(
            title: "Orphan needle",
            link: "https://example.com/orphan",
            articleDescription: "searchable needle text",
            publishedDate: now.addingTimeInterval(-3600),
            guid: "guid-orphan"
        )
        context.insert(orphan)

        try context.save()
    }

    private func allArticlesNewestFirst() throws -> [Article] {
        try context.fetch(FetchDescriptor<Article>(
            sortBy: [SortDescriptor(\.publishedDate, order: .reverse)]
        ))
    }

    // MARK: - Reference implementation (pre-U3 TodayView.filteredArticles)

    private func referenceFilter(
        _ allArticles: [Article],
        daysToLoad: Int,
        selectedCategory: String,
        showAltCategory: Bool,
        searchText: String,
        hideReadArticles: Bool,
        showFavoritesOnly: Bool
    ) -> [Article] {
        var articles = allArticles

        if selectedCategory != podcastsTitle {
            let startOfToday = Calendar.current.startOfDay(for: now)
            let cutoffDate = Calendar.current.date(byAdding: .day, value: -daysToLoad, to: startOfToday)!
            articles = articles.filter { $0.publishedDate >= cutoffDate }
        }

        if showAltCategory {
            articles = articles.filter { $0.feed?.category.lowercased() == "alt" }
        } else {
            articles = articles.filter { $0.feed?.category.lowercased() != "alt" }
        }

        if selectedCategory == podcastsTitle {
            articles = articles.filter { $0.hasPodcastAudio }
        } else if selectedCategory != "All" {
            articles = articles.filter { $0.feed?.category == selectedCategory }
        }

        if !searchText.isEmpty {
            articles = articles.filter {
                $0.title.localizedCaseInsensitiveContains(searchText) ||
                $0.articleDescription?.localizedCaseInsensitiveContains(searchText) == true
            }
        }
        if hideReadArticles {
            articles = articles.filter { !$0.isRead }
        }
        if showFavoritesOnly {
            articles = articles.filter { $0.isFavorite }
        }
        return articles
    }

    /// Pre-U3 unreadCount: date + category filter only, no alt/read/favourite/search.
    private func referenceWindowCount(
        _ allArticles: [Article],
        daysToLoad: Int,
        selectedCategory: String,
        unread: Bool
    ) -> Int {
        var articles = allArticles
        let startOfToday = Calendar.current.startOfDay(for: now)
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -daysToLoad, to: startOfToday)!
        articles = articles.filter { $0.publishedDate >= cutoffDate }

        if selectedCategory == podcastsTitle {
            articles = articles.filter { $0.hasPodcastAudio }
        } else if selectedCategory != "All" {
            articles = articles.filter { $0.feed?.category == selectedCategory }
        }
        return unread
            ? articles.filter { !$0.isRead }.count
            : articles.filter { $0.isFavorite }.count
    }

    // MARK: - New pipeline

    private func newPipeline(
        daysToLoad: Int,
        selectedCategory: String,
        showAltCategory: Bool,
        searchText: String,
        hideReadArticles: Bool,
        showFavoritesOnly: Bool
    ) throws -> [Article] {
        let selection = ArticleSelection.from(
            selectedCategory: selectedCategory,
            podcastsTitle: podcastsTitle
        )
        // Mirrors TodayView: only the date window / podcast bypass is fetched; category
        // filtering happens in Swift so the same fetch feeds the category switcher.
        let window = try context.fetch(ArticleQuery.windowDescriptor(
            daysToLoad: daysToLoad,
            selection: ArticleQuery.descriptorSelection(for: selection),
            now: now
        ))
        return ArticleQuery.applyInMemoryFilters(
            window,
            selection: selection,
            altVisible: showAltCategory,
            hideRead: hideReadArticles,
            favoritesOnly: showFavoritesOnly,
            searchText: searchText
        )
    }

    private func derived(
        daysToLoad: Int,
        selectedCategory: String,
        showAltCategory: Bool,
        searchText: String = "",
        hideReadArticles: Bool = false,
        showFavoritesOnly: Bool = false
    ) throws -> ArticleQuery.Derived {
        let selection = ArticleSelection.from(
            selectedCategory: selectedCategory,
            podcastsTitle: podcastsTitle
        )
        let window = try context.fetch(ArticleQuery.windowDescriptor(
            daysToLoad: daysToLoad,
            selection: ArticleQuery.descriptorSelection(for: selection),
            now: now
        ))
        return ArticleQuery.derive(
            window: window,
            selection: selection,
            altVisible: showAltCategory,
            hideRead: hideReadArticles,
            favoritesOnly: showFavoritesOnly,
            searchText: searchText
        )
    }

    // MARK: - The matrix

    func testBoundedPipelineMatchesReferenceAcrossFilterMatrix() throws {
        let all = try allArticlesNewestFirst()

        let days = [1, 2, 7, 13]
        let selections = ["All", "Technology", "News", "Alt", "Personal", podcastsTitle]
        let searches = ["", "needle", "Technology day 3"]
        var combinations = 0

        for daysToLoad in days {
            for selectedCategory in selections {
                for showAlt in [false, true] {
                    for searchText in searches {
                        for hideRead in [false, true] {
                            for favoritesOnly in [false, true] {
                                let expected = referenceFilter(
                                    all,
                                    daysToLoad: daysToLoad,
                                    selectedCategory: selectedCategory,
                                    showAltCategory: showAlt,
                                    searchText: searchText,
                                    hideReadArticles: hideRead,
                                    showFavoritesOnly: favoritesOnly
                                )
                                let actual = try newPipeline(
                                    daysToLoad: daysToLoad,
                                    selectedCategory: selectedCategory,
                                    showAltCategory: showAlt,
                                    searchText: searchText,
                                    hideReadArticles: hideRead,
                                    showFavoritesOnly: favoritesOnly
                                )

                                let label = "days=\(daysToLoad) cat=\(selectedCategory) "
                                    + "alt=\(showAlt) search=\"\(searchText)\" "
                                    + "hideRead=\(hideRead) favs=\(favoritesOnly)"

                                XCTAssertEqual(
                                    actual.map(\.guid), expected.map(\.guid),
                                    "set or order diverged — \(label)"
                                )
                                combinations += 1
                            }
                        }
                    }
                }
            }
        }

        XCTAssertEqual(combinations, 4 * 6 * 2 * 3 * 2 * 2)
    }

    // MARK: - Specific guarantees worth naming

    func testFeedLessArticleSurvivesTheBoundedPipelineWhenAltHidden() throws {
        let actual = try newPipeline(
            daysToLoad: 1, selectedCategory: "All", showAltCategory: false,
            searchText: "", hideReadArticles: false, showFavoritesOnly: false
        )
        XCTAssertTrue(
            actual.contains { $0.guid == "guid-orphan" },
            "the feed-less article must remain visible — the R3 regression the probe found"
        )
    }

    func testFeedLessArticleIsExcludedWhenAltShown() throws {
        let actual = try newPipeline(
            daysToLoad: 1, selectedCategory: "All", showAltCategory: true,
            searchText: "", hideReadArticles: false, showFavoritesOnly: false
        )
        XCTAssertFalse(actual.contains { $0.guid == "guid-orphan" })
    }

    func testBothAltSpellingsAreTreatedAsAlt() throws {
        let actual = try newPipeline(
            daysToLoad: 13, selectedCategory: "All", showAltCategory: true,
            searchText: "", hideReadArticles: false, showFavoritesOnly: false
        )
        let categories = Set(actual.compactMap { $0.feed?.category })
        XCTAssertEqual(categories, ["Alt", "alt"], "case-insensitive alt matching must hold")
    }

    func testPodcastsSelectionIgnoresTheDateWindow() throws {
        // Podcast episodes exist on days 0 and 6; a 1-day window must still show both.
        let actual = try newPipeline(
            daysToLoad: 1, selectedCategory: podcastsTitle, showAltCategory: false,
            searchText: "", hideReadArticles: false, showFavoritesOnly: false
        )
        let dayOffsets = Set(actual.map { $0.guid.split(separator: "-").last.map(String.init) ?? "" })
        XCTAssertTrue(dayOffsets.contains("6"), "podcasts must bypass the date window")
        XCTAssertTrue(actual.allSatisfy { $0.hasPodcastAudio })
    }

    func testWindowIsSortedNewestFirst() throws {
        let window = try context.fetch(ArticleQuery.windowDescriptor(
            daysToLoad: 13, selection: .all, now: now
        ))
        XCTAssertEqual(
            window.map(\.publishedDate),
            window.map(\.publishedDate).sorted(by: >),
            "descriptor must preserve reverse-chronological order"
        )
    }

    func testFetchLimitIsApplied() throws {
        let limited = try context.fetch(ArticleQuery.windowDescriptor(
            daysToLoad: 13, selection: .all, limit: 5, now: now
        ))
        XCTAssertEqual(limited.count, 5)

        // And the limit keeps the newest, not an arbitrary slice.
        let unlimited = try context.fetch(ArticleQuery.windowDescriptor(
            daysToLoad: 13, selection: .all, now: now
        ))
        XCTAssertEqual(limited.map(\.guid), Array(unlimited.prefix(5).map(\.guid)))
    }

    /// The counts must reproduce TodayView's unreadCount/favoritesCount, which apply the
    /// date and category filters but NOT alt visibility. That asymmetry is preserved
    /// deliberately, so the expected values here are alt-independent.
    func testDeriveCountsMatchReferenceWindowCountsAndIgnoreAltVisibility() throws {
        let all = try allArticlesNewestFirst()

        for daysToLoad in [1, 2, 7, 13] {
            for selectedCategory in ["All", "Technology", "Alt"] {
                let expectedUnread = referenceWindowCount(
                    all, daysToLoad: daysToLoad,
                    selectedCategory: selectedCategory, unread: true
                )
                let expectedFavorites = referenceWindowCount(
                    all, daysToLoad: daysToLoad,
                    selectedCategory: selectedCategory, unread: false
                )

                for showAlt in [false, true] {
                    let d = try derived(
                        daysToLoad: daysToLoad,
                        selectedCategory: selectedCategory,
                        showAltCategory: showAlt
                    )
                    let label = "days=\(daysToLoad) cat=\(selectedCategory) alt=\(showAlt)"
                    XCTAssertEqual(d.unreadCount, expectedUnread, "unread \(label)")
                    XCTAssertEqual(d.favoritesCount, expectedFavorites, "favorites \(label)")
                }
            }
        }
    }

    func testDeriveVisibleMatchesApplyInMemoryFilters() throws {
        for selectedCategory in ["All", "Technology", podcastsTitle] {
            for showAlt in [false, true] {
                for hideRead in [false, true] {
                    let d = try derived(
                        daysToLoad: 7, selectedCategory: selectedCategory,
                        showAltCategory: showAlt, searchText: "needle",
                        hideReadArticles: hideRead
                    )
                    let direct = try newPipeline(
                        daysToLoad: 7, selectedCategory: selectedCategory,
                        showAltCategory: showAlt, searchText: "needle",
                        hideReadArticles: hideRead, showFavoritesOnly: false
                    )
                    XCTAssertEqual(
                        d.visible.map(\.guid), direct.map(\.guid),
                        "derive().visible must equal applyInMemoryFilters — cat=\(selectedCategory) alt=\(showAlt) hideRead=\(hideRead)"
                    )
                }
            }
        }
    }

    /// The category switcher must keep every category in the window regardless of which
    /// one is selected — otherwise selecting a category leaves one chip and no way back.
    func testCategorySetIsIndependentOfCurrentSelection() throws {
        let whenAll = try derived(daysToLoad: 13, selectedCategory: "All", showAltCategory: false)
        let whenNarrowed = try derived(
            daysToLoad: 13, selectedCategory: "Technology", showAltCategory: false
        )

        XCTAssertEqual(
            whenNarrowed.categories, whenAll.categories,
            "selecting a category must not shrink the switcher"
        )
        XCTAssertTrue(whenAll.categories.isSuperset(of: ["Technology", "News", "Personal"]))
        XCTAssertFalse(
            whenAll.categories.contains { $0.lowercased() == "alt" },
            "alt categories stay out of the switcher when alt is hidden"
        )
    }

    func testCategorySetMatchesReferenceComputation() throws {
        let all = try allArticlesNewestFirst()

        for daysToLoad in [1, 7, 13] {
            for showAlt in [false, true] {
                // Reference: pre-U3 TodayView.categories — date-filtered articles, collect
                // feed categories, then filter that set by alt-ness.
                let startOfToday = Calendar.current.startOfDay(for: now)
                let cutoff = Calendar.current.date(byAdding: .day, value: -daysToLoad, to: startOfToday)!
                var expected = Set(all.filter { $0.publishedDate >= cutoff }
                    .compactMap { $0.feed?.category })
                expected = showAlt
                    ? expected.filter { $0.lowercased() == "alt" }
                    : expected.filter { $0.lowercased() != "alt" }

                let d = try derived(
                    daysToLoad: daysToLoad, selectedCategory: "All", showAltCategory: showAlt
                )
                XCTAssertEqual(
                    d.categories, expected,
                    "categories diverged — days=\(daysToLoad) alt=\(showAlt)"
                )
            }
        }
    }

    func testHasPodcastArticlesMatchesReference() throws {
        let all = try allArticlesNewestFirst()
        for showAlt in [false, true] {
            let expected = all.contains { article in
                article.hasPodcastAudio
                    && ArticleQuery.matchesAltVisibility(article, altVisible: showAlt)
            }
            // Widest window so the derived flag sees the same articles the reference does.
            let d = try derived(
                daysToLoad: 3650, selectedCategory: "All", showAltCategory: showAlt
            )
            XCTAssertEqual(d.hasPodcastArticles, expected, "alt=\(showAlt)")
        }
    }

    func testTotalCountDescriptorsMatchFullScan() throws {
        let all = try allArticlesNewestFirst()
        XCTAssertEqual(
            try context.fetchCount(ArticleQuery.totalCountDescriptor(unreadOnly: true)),
            all.filter { !$0.isRead }.count
        )
        XCTAssertEqual(
            try context.fetchCount(ArticleQuery.totalCountDescriptor(unreadOnly: false)),
            all.filter { $0.isFavorite }.count
        )
    }

    // MARK: - Edge cases

    func testEmptyStoreYieldsNothingAndDoesNotThrow() throws {
        let emptyConfig = ModelConfiguration(
            schema: Schema([Feed.self, Article.self, OPMLSubscription.self]),
            isStoredInMemoryOnly: true
        )
        let emptyContainer = try ModelContainer(
            for: Schema([Feed.self, Article.self, OPMLSubscription.self]),
            configurations: [emptyConfig]
        )
        let emptyContext = ModelContext(emptyContainer)

        let window = try emptyContext.fetch(ArticleQuery.windowDescriptor(
            daysToLoad: 1, selection: .all, now: now
        ))
        XCTAssertTrue(window.isEmpty)

        let derived = ArticleQuery.derive(
            window: window, selection: .all, altVisible: false,
            hideRead: false, favoritesOnly: false, searchText: ""
        )
        XCTAssertTrue(derived.visible.isEmpty)
        XCTAssertEqual(derived.unreadCount, 0)
        XCTAssertEqual(derived.favoritesCount, 0)
        XCTAssertTrue(derived.categories.isEmpty)
        XCTAssertFalse(derived.hasPodcastArticles)
    }

    func testWindowWiderThanAvailableDataReturnsEverythingInWindow() throws {
        let wide = try context.fetch(ArticleQuery.windowDescriptor(
            daysToLoad: 3650, selection: .all, now: now
        ))
        let all = try allArticlesNewestFirst()
        XCTAssertEqual(wide.count, all.count)
    }

    func testFutureDatedArticleIsIncludedLikeToday() throws {
        // Pin a non-alt feed: an alt-categorised one would be filtered out with
        // showAltCategory: false and the assertion below would be about the fixture.
        let feed = try context.fetch(FetchDescriptor<Feed>(
            predicate: #Predicate<Feed> { $0.category == "Technology" }
        )).first!
        let future = Article(
            title: "From the future",
            link: "https://example.com/future",
            publishedDate: now.addingTimeInterval(86_400 * 3),
            guid: "guid-future",
            feed: feed
        )
        context.insert(future)
        try context.save()

        let all = try allArticlesNewestFirst()
        let expected = referenceFilter(
            all, daysToLoad: 1, selectedCategory: "All", showAltCategory: false,
            searchText: "", hideReadArticles: false, showFavoritesOnly: false
        )
        let actual = try newPipeline(
            daysToLoad: 1, selectedCategory: "All", showAltCategory: false,
            searchText: "", hideReadArticles: false, showFavoritesOnly: false
        )
        XCTAssertEqual(actual.map(\.guid), expected.map(\.guid))
        XCTAssertTrue(actual.contains { $0.guid == "guid-future" })
    }

    func testUnknownCategorySelectionReturnsNothing() throws {
        let actual = try newPipeline(
            daysToLoad: 13, selectedCategory: "NoSuchCategory", showAltCategory: false,
            searchText: "", hideReadArticles: false, showFavoritesOnly: false
        )
        XCTAssertTrue(actual.isEmpty)
    }

    // MARK: - Library-wide non-alt counts (AI features)

    /// These back the assistant's "you have N articles, M unread" answers, so they must stay
    /// store-wide and exact even though the articles handed to the AI are windowed. The
    /// reference is the pre-U5 expression: count over all non-alt articles.
    func testNonAltCountsMatchFullScan() throws {
        let all = try allArticlesNewestFirst()
        let expectedTotal = all.filter { $0.feed?.category.lowercased() != "alt" }.count
        let expectedUnread = all.filter {
            $0.feed?.category.lowercased() != "alt" && !$0.isRead
        }.count

        let counts = ArticleQuery.nonAltCounts(in: context)

        XCTAssertEqual(counts.total, expectedTotal)
        XCTAssertEqual(counts.unread, expectedUnread)
    }

    /// The fixture has both "Alt" and "alt" feeds; both must be excluded.
    func testNonAltCountsExcludeEveryAltSpelling() throws {
        let all = try allArticlesNewestFirst()
        let altCount = all.filter { $0.feed?.category.lowercased() == "alt" }.count
        XCTAssertGreaterThan(altCount, 0, "fixture must contain alt articles for this to mean anything")

        let counts = ArticleQuery.nonAltCounts(in: context)
        XCTAssertEqual(counts.total, all.count - altCount)
    }

    /// The feed-less article has no category, so it is not alt and must be counted.
    func testNonAltCountsIncludeFeedLessArticles() throws {
        let counts = ArticleQuery.nonAltCounts(in: context)
        let all = try allArticlesNewestFirst()
        let orphanIsUnread = all.first { $0.guid == "guid-orphan" }?.isRead == false

        XCTAssertEqual(counts.total, all.filter { $0.feed?.category.lowercased() != "alt" }.count)
        if orphanIsUnread {
            XCTAssertGreaterThan(counts.unread, 0)
        }
    }

    func testNonAltCountsAreZeroOnAnEmptyStore() throws {
        let schema = Schema([Feed.self, Article.self, OPMLSubscription.self])
        let emptyContainer = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        let counts = ArticleQuery.nonAltCounts(in: ModelContext(emptyContainer))
        XCTAssertEqual(counts.total, 0)
        XCTAssertEqual(counts.unread, 0)
    }

    /// Marking an article read must move the unread total without touching the grand total.
    func testNonAltCountsTrackReadStateChanges() throws {
        let before = ArticleQuery.nonAltCounts(in: context)

        let target = try context.fetch(FetchDescriptor<Article>(
            predicate: #Predicate { !$0.isRead && $0.feed?.category == "Technology" }
        )).first
        let unwrapped = try XCTUnwrap(target)
        unwrapped.isRead = true
        try context.save()

        let after = ArticleQuery.nonAltCounts(in: context)
        XCTAssertEqual(after.total, before.total)
        XCTAssertEqual(after.unread, before.unread - 1)
    }

    // MARK: - Rolling window (sidebar)

    /// The sidebar filters on a rolling N×24h cutoff from `now`, not from the start of
    /// today like TodayView. Reference is the pre-U4 sidebar expression.
    func testRollingWindowPipelineMatchesReference() throws {
        let all = try allArticlesNewestFirst()

        for daysBack in [1, 7, 30] {
            for showAlt in [false, true] {
                let cutoff = Calendar.current.date(byAdding: .day, value: -daysBack, to: now)!
                let expected = all.filter { article in
                    article.publishedDate >= cutoff &&
                    (showAlt
                        ? article.feed?.category.lowercased() == "alt"
                        : article.feed?.category.lowercased() != "alt")
                }

                let window = try context.fetch(ArticleQuery.rollingWindowDescriptor(
                    daysBack: daysBack, now: now
                ))
                let actual = window.filter {
                    ArticleQuery.isWithinRollingWindow($0, daysBack: daysBack, now: now)
                        && ArticleQuery.matchesAltVisibility($0, altVisible: showAlt)
                }

                XCTAssertEqual(
                    actual.map(\.guid), expected.map(\.guid),
                    "rolling window diverged — daysBack=\(daysBack) alt=\(showAlt)"
                )
            }
        }
    }

    /// The descriptor's margin is what keeps a long-lived view correct: its lower bound is
    /// frozen at init, but the exact cutoff moves forward, so the frozen bound must stay
    /// more generous than the cutoff — never less.
    func testRollingDescriptorBoundIsMoreGenerousThanTheExactCutoff() throws {
        let daysBack = 7
        let window = try context.fetch(ArticleQuery.rollingWindowDescriptor(
            daysBack: daysBack, now: now
        ))
        let exact = window.filter {
            ArticleQuery.isWithinRollingWindow($0, daysBack: daysBack, now: now)
        }
        XCTAssertGreaterThanOrEqual(
            window.count, exact.count,
            "descriptor must be a superset of the exact window"
        )

        // Simulate the view having been created a day ago: the descriptor built then must
        // still cover everything today's exact cutoff admits.
        let yesterday = now.addingTimeInterval(-86_400)
        let staleWindow = try context.fetch(ArticleQuery.rollingWindowDescriptor(
            daysBack: daysBack, now: yesterday
        ))
        let exactToday = Set(
            try allArticlesNewestFirst()
                .filter { ArticleQuery.isWithinRollingWindow($0, daysBack: daysBack, now: now) }
                .map(\.guid)
        )
        XCTAssertTrue(
            Set(staleWindow.map(\.guid)).isSuperset(of: exactToday),
            "a day-old descriptor must still cover today's window — this is what marginDays buys"
        )
    }

    func testRollingWindowExcludesArticlesOlderThanTheCutoff() throws {
        let window = try context.fetch(ArticleQuery.rollingWindowDescriptor(
            daysBack: 2, now: now
        ))
        let exact = window.filter {
            ArticleQuery.isWithinRollingWindow($0, daysBack: 2, now: now)
        }
        let cutoff = Calendar.current.date(byAdding: .day, value: -2, to: now)!
        XCTAssertTrue(exact.allSatisfy { $0.publishedDate >= cutoff })
        XCTAssertFalse(exact.isEmpty)
    }

    func testRollingWindowRespectsFetchLimit() throws {
        let limited = try context.fetch(ArticleQuery.rollingWindowDescriptor(
            daysBack: 30, limit: 4, now: now
        ))
        XCTAssertEqual(limited.count, 4)
    }

    func testCutoffMatchesTodayViewComputation() {
        for daysToLoad in [1, 2, 7, 30] {
            let startOfToday = Calendar.current.startOfDay(for: now)
            let expected = Calendar.current.date(byAdding: .day, value: -daysToLoad, to: startOfToday)!
            XCTAssertEqual(ArticleQuery.cutoff(daysToLoad: daysToLoad, now: now), expected)
        }
    }
}
