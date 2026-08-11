//
//  ArticleQuery.swift
//  Today
//
//  Builds bounded article fetches, replacing "fetch every Article and filter it in Swift".
//
//  Split of responsibility, and why it is where it is:
//
//  - Database predicate: the date window, the category selection, and the podcast flag.
//    These are the filters that decide how much data gets materialised, so they are the
//    ones worth pushing down.
//
//  - Swift (`applyInMemoryFilters`): alt visibility, search, read, favourite. Alt
//    visibility cannot move into a predicate — `lowercased()` is rejected by the
//    #Predicate macro at compile time, and the workarounds either fail SQL generation or
//    silently drop articles with no feed (see PredicateCapabilityProbeTests). Search stays
//    in Swift because `localizedCaseInsensitiveContains` has no predicate equivalent with
//    the same semantics. Read/favourite stay in Swift so a single fetch can serve both the
//    displayed list and the unread/favourite counts, which are computed over the window
//    *before* those filters are applied — matching TodayView today.
//
//  Filter order does not matter for correctness: every filter is conjunctive, so the
//  resulting set is the same regardless of which side of the boundary each one lands on.
//  ArticleQueryTests pins that against the pre-change behaviour.
//

import Foundation
import SwiftData

/// Which slice of articles the UI is asking for.
///
/// Modelled as a value rather than a raw string so the query layer does not have to know
/// that "Podcasts" is a localised, virtual category.
enum ArticleSelection: Equatable {
    case all
    case podcasts
    case category(String)

    /// Maps TodayView's `selectedCategory` string onto a selection.
    static func from(selectedCategory: String, podcastsTitle: String) -> ArticleSelection {
        if selectedCategory == podcastsTitle { return .podcasts }
        if selectedCategory == "All" { return .all }
        return .category(selectedCategory)
    }
}

enum ArticleQuery {

    /// Ceiling on a single windowed fetch.
    ///
    /// Generous on purpose: the Swift-side filters (alt, search) run *after* the limit, so
    /// a tight limit could hide articles the user should see. The limit exists to stop an
    /// unbounded fetch, not to page the UI.
    static let defaultFetchLimit = 3000

    /// Start of today minus `daysToLoad` days — the same cutoff TodayView computes.
    static func cutoff(daysToLoad: Int, now: Date = .now, calendar: Calendar = .current) -> Date {
        let startOfToday = calendar.startOfDay(for: now)
        return calendar.date(byAdding: .day, value: -daysToLoad, to: startOfToday) ?? startOfToday
    }

    /// A bounded, sorted, feed-prefetching descriptor for the requested window.
    ///
    /// Deliberately does **not** apply read/favourite filters — see the file comment.
    static func windowDescriptor(
        daysToLoad: Int,
        selection: ArticleSelection,
        limit: Int = defaultFetchLimit,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> FetchDescriptor<Article> {
        let sort = [SortDescriptor(\Article.publishedDate, order: .reverse)]
        var descriptor: FetchDescriptor<Article>

        switch selection {
        case .podcasts:
            // Podcasts intentionally ignore the date window — episodes are infrequent and
            // users expect the whole back catalogue. Matches TodayView.
            descriptor = FetchDescriptor(
                predicate: #Predicate { $0.audioUrl != nil },
                sortBy: sort
            )

        case .category(let category):
            let cutoffDate = cutoff(daysToLoad: daysToLoad, now: now, calendar: calendar)
            descriptor = FetchDescriptor(
                predicate: #Predicate {
                    $0.publishedDate >= cutoffDate && $0.feed?.category == category
                },
                sortBy: sort
            )

        case .all:
            let cutoffDate = cutoff(daysToLoad: daysToLoad, now: now, calendar: calendar)
            descriptor = FetchDescriptor(
                predicate: #Predicate { $0.publishedDate >= cutoffDate },
                sortBy: sort
            )
        }

        descriptor.fetchLimit = limit
        // Without this, every filter that touches feed?.category faults the relationship
        // one article at a time — the dominant cost in the pre-change read path.
        descriptor.relationshipKeyPathsForPrefetching = [\.feed]
        return descriptor
    }

    /// Count-only descriptor for the store-wide totals.
    ///
    /// These correspond to TodayView's `totalUnreadCount` / `totalFavoritesCount`, which
    /// apply neither a date window nor alt visibility, so they are expressible as pure
    /// counts and never need to materialise an object.
    static func totalCountDescriptor(unreadOnly: Bool) -> FetchDescriptor<Article> {
        unreadOnly
            ? FetchDescriptor(predicate: #Predicate { !$0.isRead })
            : FetchDescriptor(predicate: #Predicate { $0.isFavorite })
    }

    // MARK: - Swift-side filters

    /// True when an article should be visible for the given alt-visibility setting.
    ///
    /// Mirrors TodayView exactly, including the asymmetry for articles with no feed:
    /// included when alt is hidden (`nil != "alt"`), excluded when alt is shown.
    static func matchesAltVisibility(_ article: Article, altVisible: Bool) -> Bool {
        let isAlt = article.feed?.category.lowercased() == "alt"
        return altVisible ? isAlt : !isAlt
    }

    /// The window narrowed to what the list should display.
    static func applyInMemoryFilters(
        _ articles: [Article],
        altVisible: Bool,
        hideRead: Bool,
        favoritesOnly: Bool,
        searchText: String
    ) -> [Article] {
        applyDisplayFilters(
            articles.filter { matchesAltVisibility($0, altVisible: altVisible) },
            hideRead: hideRead,
            favoritesOnly: favoritesOnly,
            searchText: searchText
        )
    }

    /// Search / read / favourite only — the filters that narrow an already alt-filtered set.
    private static func applyDisplayFilters(
        _ articles: [Article],
        hideRead: Bool,
        favoritesOnly: Bool,
        searchText: String
    ) -> [Article] {
        var result = articles

        if !searchText.isEmpty {
            result = result.filter {
                $0.title.localizedCaseInsensitiveContains(searchText) ||
                $0.articleDescription?.localizedCaseInsensitiveContains(searchText) == true
            }
        }
        if hideRead {
            result = result.filter { !$0.isRead }
        }
        if favoritesOnly {
            result = result.filter { $0.isFavorite }
        }
        return result
    }

    /// Everything TodayView derives from the window, computed in one pass instead of six.
    ///
    /// `unreadCount` and `favoritesCount` are counted over the alt-filtered window *before*
    /// hideRead/favoritesOnly/search are applied, which is what TodayView does today — the
    /// counts describe the window, not the currently displayed list.
    struct Derived {
        var visible: [Article] = []
        var unreadCount = 0
        var favoritesCount = 0
        var categories: Set<String> = []
        var hasPodcastArticles = false
    }

    static func derive(
        window: [Article],
        altVisible: Bool,
        hideRead: Bool,
        favoritesOnly: Bool,
        searchText: String
    ) -> Derived {
        var derived = Derived()
        var altFiltered: [Article] = []
        altFiltered.reserveCapacity(window.count)

        for article in window where matchesAltVisibility(article, altVisible: altVisible) {
            altFiltered.append(article)
            if !article.isRead { derived.unreadCount += 1 }
            if article.isFavorite { derived.favoritesCount += 1 }
            if let category = article.feed?.category { derived.categories.insert(category) }
            if article.hasPodcastAudio { derived.hasPodcastArticles = true }
        }

        derived.visible = applyDisplayFilters(
            altFiltered,
            hideRead: hideRead,
            favoritesOnly: favoritesOnly,
            searchText: searchText
        )
        return derived
    }
}
