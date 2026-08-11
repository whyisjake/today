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

    /// Descriptor for a **rolling** N-day window, as the sidebar uses — measured from `now`
    /// rather than from the start of today, which is how `SidebarContentView` has always
    /// computed its 7-day cutoff.
    ///
    /// Over-fetches by `marginDays` on purpose. A view's `@Query` descriptor is built once
    /// in `init`, but the rolling cutoff moves forward as time passes. Since the cutoff only
    /// ever moves *forward*, a slightly older lower bound stays generous indefinitely, and
    /// the exact cutoff is re-applied in Swift by `isWithinRollingWindow`. The alternative —
    /// a frozen exact bound — would slowly diverge from the intended window in a long-lived
    /// window on macOS.
    static func rollingWindowDescriptor(
        daysBack: Int,
        marginDays: Int = 1,
        limit: Int = defaultFetchLimit,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> FetchDescriptor<Article> {
        let lowerBound = calendar.date(byAdding: .day, value: -(daysBack + marginDays), to: now) ?? now
        var descriptor = FetchDescriptor<Article>(
            predicate: #Predicate { $0.publishedDate >= lowerBound },
            sortBy: [SortDescriptor(\Article.publishedDate, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        descriptor.relationshipKeyPathsForPrefetching = [\.feed]
        return descriptor
    }

    /// The exact rolling-window test, evaluated fresh so it does not drift.
    static func isWithinRollingWindow(
        _ article: Article,
        daysBack: Int,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Bool {
        let cutoff = calendar.date(byAdding: .day, value: -daysBack, to: now) ?? now
        return article.publishedDate >= cutoff
    }

    /// Store-wide totals excluding alt-category articles, counted exactly.
    ///
    /// The AI features describe the user's whole library ("you have N articles, M unread"),
    /// so these must not be window-scoped even though the articles handed to the AI are.
    ///
    /// Alt exclusion cannot go into a predicate (`lowercased()` is unavailable, and the
    /// workarounds fail SQL generation — see PredicateCapabilityProbeTests), so the alt
    /// contribution is counted per alt feed and subtracted. There are only ever a handful
    /// of feeds, and these are count queries that materialise nothing.
    static func nonAltCounts(in context: ModelContext) -> (total: Int, unread: Int) {
        let total = (try? context.fetchCount(FetchDescriptor<Article>())) ?? 0
        let unread = (try? context.fetchCount(
            FetchDescriptor<Article>(predicate: #Predicate { !$0.isRead })
        )) ?? 0

        let feeds = (try? context.fetch(FetchDescriptor<Feed>())) ?? []
        let altFeedIDs = feeds.filter { $0.category.lowercased() == "alt" }.map(\.id)

        var altTotal = 0
        var altUnread = 0
        for feedID in altFeedIDs {
            altTotal += (try? context.fetchCount(FetchDescriptor<Article>(
                predicate: #Predicate { $0.feed?.id == feedID }
            ))) ?? 0
            altUnread += (try? context.fetchCount(FetchDescriptor<Article>(
                predicate: #Predicate { $0.feed?.id == feedID && !$0.isRead }
            ))) ?? 0
        }

        return (max(total - altTotal, 0), max(unread - altUnread, 0))
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

    /// True when an article satisfies the current selection.
    ///
    /// `.all` matches everything; `.podcasts` matches articles with audio; `.category`
    /// requires exact category equality, which excludes articles with no feed — matching
    /// TodayView's `feed?.category == selectedCategory`.
    static func matchesSelection(_ article: Article, selection: ArticleSelection) -> Bool {
        switch selection {
        case .all: return true
        case .podcasts: return article.hasPodcastAudio
        case .category(let category): return article.feed?.category == category
        }
    }

    /// The window narrowed to what the list should display.
    static func applyInMemoryFilters(
        _ articles: [Article],
        selection: ArticleSelection = .all,
        altVisible: Bool,
        hideRead: Bool,
        favoritesOnly: Bool,
        searchText: String
    ) -> [Article] {
        let scoped = articles.filter {
            matchesAltVisibility($0, altVisible: altVisible)
                && matchesSelection($0, selection: selection)
        }
        return applyDisplayFilters(
            scoped,
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
    struct Derived {
        /// What the list renders.
        var visible: [Article] = []
        /// Counted over the window scoped by selection only — **not** by alt visibility,
        /// and before hideRead/favoritesOnly/search.
        ///
        /// The missing alt scoping is not an oversight: TodayView's `unreadCount` and
        /// `favoritesCount` apply the date and category filters but never the alt filter,
        /// so with alt hidden the counts already include alt articles the list does not
        /// show. Reproduced verbatim to keep R3 — worth revisiting as its own fix, but
        /// changing it here would be a silent behaviour change hiding inside a perf pass.
        var unreadCount = 0
        var favoritesCount = 0
        /// Categories present in the alt-filtered window, deliberately **ignoring** the
        /// current selection: these feed the category switcher, so narrowing them to the
        /// selected category would leave the user with a single chip and no way back.
        var categories: Set<String> = []
        /// Whether any podcast article exists in the alt-filtered window, used to decide
        /// whether the Podcasts chip appears.
        var hasPodcastArticles = false
    }

    /// - Parameter window: articles from `windowDescriptor` — date-bounded (or
    ///   podcast-bypassed), and **not** category-filtered, since `categories` needs the
    ///   full window to populate the switcher.
    static func derive(
        window: [Article],
        selection: ArticleSelection,
        altVisible: Bool,
        hideRead: Bool,
        favoritesOnly: Bool,
        searchText: String
    ) -> Derived {
        var derived = Derived()
        var scoped: [Article] = []
        scoped.reserveCapacity(window.count)

        // One pass, three different scopings — each matching what TodayView does today.
        for article in window {
            let matchesSelection = matchesSelection(article, selection: selection)

            // Counts: selection only, deliberately not alt-scoped (see Derived).
            if matchesSelection {
                if !article.isRead { derived.unreadCount += 1 }
                if article.isFavorite { derived.favoritesCount += 1 }
            }

            guard matchesAltVisibility(article, altVisible: altVisible) else { continue }

            // Switcher inputs: whole alt-filtered window, ignoring selection.
            if let category = article.feed?.category { derived.categories.insert(category) }
            if article.hasPodcastAudio { derived.hasPodcastArticles = true }

            // List: alt and selection.
            if matchesSelection { scoped.append(article) }
        }

        derived.visible = applyDisplayFilters(
            scoped,
            hideRead: hideRead,
            favoritesOnly: favoritesOnly,
            searchText: searchText
        )
        return derived
    }

    /// Which descriptor to fetch for a given selection.
    ///
    /// Only the date window (or the podcast bypass) is pushed into the predicate; category
    /// filtering stays in Swift so one fetch can serve both the list and the category
    /// switcher. The date window is where the reduction comes from — one day out of years
    /// of history — so keeping category in Swift costs little.
    static func descriptorSelection(for selection: ArticleSelection) -> ArticleSelection {
        switch selection {
        case .podcasts: return .podcasts
        case .all, .category: return .all
        }
    }
}
