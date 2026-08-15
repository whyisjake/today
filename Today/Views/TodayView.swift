//
//  TodayView.swift
//  Today
//
//  Main view showing today's articles from RSS feeds
//

import SwiftUI
import SwiftData

struct TodayView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL

    @ObservedObject private var categoryManager = CategoryManager.shared
    @ObservedObject private var syncManager = BackgroundSyncManager.shared

    @State private var selectedCategory: String = "All"
    @State private var searchText = ""
    @State private var hideReadArticles = false
    @State private var showFavoritesOnly = false
    @State private var navigationState: NavigationState?
    @State private var isRefreshing = false
    @State private var showMarkAllReadConfirmation = false
    @State private var daysToLoad = 1 // Start with 1 day (today)
    @AppStorage("showAltCategory") private var showAltCategory = false // Global setting for Alt category visibility
    @State private var tapCount = 0
    @AppStorage("fontOption") private var fontOption: FontOption =  .serif
    @AppStorage("shortArticleBehavior") private var shortArticleBehavior: ShortArticleBehavior = .openInAppBrowser

    // Navigation state that bundles article ID with context
    struct NavigationState: Hashable {
        let articleID: PersistentIdentifier
        let context: [PersistentIdentifier]
    }

    /// The selection driving both the fetch and the in-memory filters.
    private var selection: ArticleSelection {
        ArticleSelection.from(
            selectedCategory: selectedCategory,
            podcastsTitle: String(localized: "Podcasts")
        )
    }

    /// Chips: "All", the virtual Podcasts entry when the window has audio, then the
    /// categories present in the window plus any custom ones the user has defined.
    private func categoryChips(_ derived: ArticleQuery.Derived) -> [String] {
        var feedCategories = derived.categories

        // Custom categories appear even before they have articles.
        for customCategory in categoryManager.customCategories {
            feedCategories.insert(customCategory)
        }

        // derived.categories is already alt-scoped, but custom categories are not.
        feedCategories = showAltCategory
            ? feedCategories.filter { $0.lowercased() == "alt" }
            : feedCategories.filter { $0.lowercased() != "alt" }

        var result = ["All"]
        if derived.hasPodcastArticles {
            result.append(String(localized: "Podcasts"))
        }
        return result + feedCategories.sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
    }

    private func activeFilterCount(_ derived: ArticleQuery.Derived) -> Int {
        showFavoritesOnly ? derived.favoritesCount : derived.unreadCount
    }

    // Store-wide totals. Counted in SQLite rather than by materialising every Article —
    // these only ever render a number.
    private var totalUnreadCount: Int {
        (try? modelContext.fetchCount(ArticleQuery.totalCountDescriptor(unreadOnly: true))) ?? 0
    }

    private var totalFavoritesCount: Int {
        (try? modelContext.fetchCount(ArticleQuery.totalCountDescriptor(unreadOnly: false))) ?? 0
    }

    /// Whether the store holds any articles at all, used to distinguish "no articles yet"
    /// from "your filters hid everything".
    private var storeHasArticles: Bool {
        ((try? modelContext.fetchCount(FetchDescriptor<Article>())) ?? 0) > 0
    }

    // Computed property for the dynamic title
    private var viewTitle: String {
        if daysToLoad == 1 {
            return "Today"
        } else if daysToLoad == 2 {
            return "Yesterday"
        } else {
            return "\(daysToLoad - 1) Days Ago"
        }
    }

    // Label for the next day to load
    private var previousDayLabel: String {
        if daysToLoad == 1 {
            return "Yesterday"
        } else if daysToLoad == 2 {
            return "2 days ago"
        } else {
            return "\(daysToLoad) days ago"
        }
    }

    var body: some View {
        // ArticleWindow owns the bounded @Query so the fetch can follow daysToLoad and the
        // selected category, which live here as @State.
        ArticleWindow(daysToLoad: daysToLoad, selection: selection) { window in
            content(window: window)
        }
    }

    @ViewBuilder
    private func content(window: [Article]) -> some View {
        // One pass over the window replaces six independent full-array passes.
        let derived = Perf.measure(.articleListDerivation, "today: \(window.count) in window") {
            ArticleQuery.derive(
                window: window,
                selection: selection,
                altVisible: showAltCategory,
                hideRead: hideReadArticles,
                favoritesOnly: showFavoritesOnly,
                searchText: searchText
            )
        }
        let categories = categoryChips(derived)
        let filteredArticles = derived.visible

        NavigationStack {
            VStack(spacing: 0) {
                // Category filter
                if categories.count > 1 {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(categories, id: \.self) { category in
                                Button {
                                    selectedCategory = category
                                } label: {
                                    Text(category)
                                        .font(.subheadline)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 8)
                                        .background(
                                            selectedCategory == category ?
                                            Color.accentColor : Color.gray.opacity(0.2)
                                        )
                                        .foregroundStyle(
                                            selectedCategory == category ?
                                            .white : .primary
                                        )
                                        .cornerRadius(20)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                }

                // Articles list
                if filteredArticles.isEmpty {
                    if showFavoritesOnly && storeHasArticles {
                        ContentUnavailableView(
                            "No Favorites Yet",
                            systemImage: "star",
                            description: Text("Swipe left on articles to add them to favorites.")
                        )
                    } else if hideReadArticles && storeHasArticles {
                        ContentUnavailableView(
                            "No Unread Articles",
                            systemImage: "checkmark.circle",
                            description: Text("You're all caught up! Tap the filter icon to show read articles.")
                        )
                    } else {
                        ContentUnavailableView(
                            "No Articles Yet",
                            systemImage: "doc.text",
                            description: Text("Add some RSS feeds to get started")
                        )
                    }
                } else {
                    List {
                        ForEach(filteredArticles, id: \.persistentModelID) { article in
                            Button {
                                // Handle short articles based on user preference
                                if article.hasMinimalContent && !article.isRedditPost {
                                    switch shortArticleBehavior {
                                    case .openInBrowser:
                                        // Open in default browser (Safari)
                                        if let url = article.articleURL {
                                            openURL(url)
                                            article.isRead = true
                                            try? modelContext.save()
                                        }
                                    case .openInAppBrowser, .openInArticleView:
                                        // Open in-app (either web view or article detail)
                                        let context = filteredArticles.map { $0.persistentModelID }
                                        navigationState = NavigationState(
                                            articleID: article.persistentModelID,
                                            context: context
                                        )
                                    }
                                } else {
                                    // Regular articles always open in-app
                                    let context = filteredArticles.map { $0.persistentModelID }
                                    navigationState = NavigationState(
                                        articleID: article.persistentModelID,
                                        context: context
                                    )
                                }
                            } label: {
                                HStack {
                                    ArticleRowView(article: article, fontOption: fontOption)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                            .id(article.persistentModelID)
                            .onAppear {
                                // If first article appears and we're viewing multiple days, reset to today
                                if article.persistentModelID == filteredArticles.first?.persistentModelID && daysToLoad > 1 {
                                    resetToToday()
                                }
                            }
                            .swipeActions(edge: .leading) {
                                Button {
                                    toggleRead(article)
                                } label: {
                                    Label(
                                        article.isRead ? "Unread" : "Read",
                                        systemImage: article.isRead ? "envelope.badge" : "envelope.open"
                                    )
                                }
                                .tint(.accentColor)
                            }
                            .swipeActions(edge: .trailing) {
                                Button {
                                    toggleFavorite(article)
                                } label: {

                                    Label(
                                        article.isFavorite ? "Unfavorite" : "Favorite",
                                        systemImage: article.isFavorite ? "star.slash" : "star.fill"
                                    )
                                }
                                .tint(.yellow)
                            }
                        }

                        // Load more days button at the bottom
                        Button {
                            loadMoreDays()
                        } label: {
                            HStack {
                                Spacer()
                                VStack(spacing: 8) {
                                    Text("Load Previous Day")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                    Text(previousDayLabel)
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                                Spacer()
                            }
                            .padding()
                        }
                        .listRowBackground(Color.clear)
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .refreshable {
                        await refreshFeeds()
                    }
                }
            }
            .navigationTitle(viewTitle)
            // Pinned rather than left at the default `.automatic` placement.
            //
            // `.automatic` keeps the field collapsed until the list is pulled down, but this
            // list is also `.refreshable`, so the same downward drag drives pull-to-refresh —
            // which usually wins. The search field was effectively unreachable.
            //
            // It also fixes a dead spot: when the filtered list is empty this view renders a
            // ContentUnavailableView instead of the List, so there was no scrollable content
            // to pull and therefore no way to search at all.
            //
            // Costs a fixed row of vertical space. `navigationBarDrawer` is iOS-only, and
            // macOS puts search in the toolbar anyway, so the default stands there.
            #if os(iOS)
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Search articles"
            )
            #else
            .searchable(text: $searchText, prompt: "Search articles")
            #endif
            .onChange(of: selectedCategory) { _, newCategory in
                // Don't reset time filter when selecting Podcasts - podcasts are infrequent
                // and users expect to see all their podcast episodes
                let podcastsCategory = String(localized: "Podcasts")
                if newCategory != podcastsCategory {
                    resetToToday()
                }
            }
            .onChange(of: searchText) { _, _ in
                resetToToday()
            }
            .onChange(of: hideReadArticles) { _, _ in
                resetToToday()
            }
            .onChange(of: showFavoritesOnly) { _, _ in
                resetToToday()
            }
            .navigationDestination(item: $navigationState) { state in
                if !state.context.isEmpty,
                   let initialIndex = state.context.firstIndex(of: state.articleID) {
                    ArticlePagerView(
                        articleIDs: state.context,
                        initialIndex: initialIndex
                    )
                } else if let article = modelContext.model(for: state.articleID) as? Article {
                    // Fallback for single article without context
                    ArticleDetailSimple(
                        article: article,
                        previousArticleID: nil,
                        nextArticleID: nil,
                        onNavigateToPrevious: { _ in },
                        onNavigateToNext: { _ in }
                    )
                }
            }
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .topBarLeading) {
                    if syncManager.isSyncInProgress {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    filterMenu(derived)
                }
                #else
                ToolbarItem(placement: .primaryAction) {
                    filterMenu(derived)
                }
                ToolbarItem(placement: .navigation) {
                    if syncManager.isSyncInProgress {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
                #endif
            }
            .confirmationDialog(
                selectedCategory == "All"
                    ? "Mark all \(derived.unreadCount) articles as read?"
                    : "Mark all \(derived.unreadCount) articles in \(selectedCategory) as read?",
                isPresented: $showMarkAllReadConfirmation,
                titleVisibility: .visible
            ) {
                Button("Mark All as Read", role: .destructive) {
                    markAllAsRead()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This cannot be undone.")
            }
        }
        // The derived-field backfill used to run here on every appearance. It now runs once
        // off the main actor from TodayApp — see DatabaseMigration.backfillDerivedArticleFields.
    }

    private func filterMenu(_ derived: ArticleQuery.Derived) -> some View {
        Menu {
            Section("Read Status") {
                Button {
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 50_000_000)
                        hideReadArticles = false
                    }
                } label: {
                    Label("Show All", systemImage: hideReadArticles ? "circle" : "checkmark.circle")
                }

                Button {
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 50_000_000)
                        hideReadArticles = true
                    }
                } label: {
                    Label("Unread Only", systemImage: hideReadArticles ? "checkmark.circle" : "circle")
                }
            }

            Section("Favorites") {
                Button {
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 50_000_000)
                        showFavoritesOnly = false
                    }
                } label: {
                    Label("All Articles", systemImage: showFavoritesOnly ? "circle" : "checkmark.circle")
                }

                Button {
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 50_000_000)
                        showFavoritesOnly = true
                    }
                } label: {
                    Label("Favorites Only", systemImage: showFavoritesOnly ? "checkmark.circle" : "circle")
                }
            }

            Divider()

            Button(role: .destructive) {
                showMarkAllReadConfirmation = true
            } label: {
                Label("Mark All as Read", systemImage: "checkmark.circle.fill")
            }

            Divider()

            // Show filtered counts with total in parentheses
            if daysToLoad > 1 || selectedCategory != "All" {
                Text("\(derived.unreadCount) unread (\(totalUnreadCount) total) • \(derived.favoritesCount) favorites (\(totalFavoritesCount) total)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("\(derived.unreadCount) unread • \(derived.favoritesCount) favorites")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: (hideReadArticles || showFavoritesOnly) ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                if hideReadArticles || showFavoritesOnly {
                    if activeFilterCount(derived) > 0 {
                        Text("\(activeFilterCount(derived))")
                            .font(.caption2)
                            .fontWeight(.semibold)
                    }
                }
            }
        }
    }

    private func markAllAsRead() {
        // Deliberately store-wide and unwindowed, matching the previous behaviour: "mark all
        // as read" clears every unread article in the category, not just the visible window.
        // Fetched with a predicate rather than filtered from a full-table query.
        var articlesToMark = (try? modelContext.fetch(FetchDescriptor<Article>(
            predicate: #Predicate { !$0.isRead }
        ))) ?? []

        // Filter by category if not "All"
        if selectedCategory != "All" {
            articlesToMark = articlesToMark.filter { $0.feed?.category == selectedCategory }
        }

        // Mark articles as read
        for article in articlesToMark {
            article.isRead = true
        }

        try? modelContext.save()
    }

    private func toggleRead(_ article: Article) {
        article.isRead.toggle()
        try? modelContext.save()
    }

    private func toggleFavorite(_ article: Article) {
        article.isFavorite.toggle()
        try? modelContext.save()
    }

    private func refreshFeeds() async {
        // Prevent multiple overlapping syncs
        guard !syncManager.isSyncInProgress else {
            return
        }

        isRefreshing = true

        // Use BackgroundSyncManager for off-main-thread sync
        BackgroundSyncManager.shared.triggerManualSync()

        // Wait for sync to complete by observing isSyncInProgress
        // This provides better UX than hardcoded delays
        while syncManager.isSyncInProgress {
            try? await Task.sleep(for: .milliseconds(100))
        }

        // Keep refresh indicator visible for a moment so user sees it completed
        try? await Task.sleep(for: .milliseconds(300))
        isRefreshing = false
    }

    private func loadMoreDays() {
        daysToLoad += 1
    }

    private func resetToToday() {
        daysToLoad = 1
    }

    private func toggleAltCategory() {
        showAltCategory.toggle()
        // Reset filters when toggling Alt category
        selectedCategory = "All"
        resetToToday()
    }
}

struct ArticleRowView: View {
    let article: Article
    let fontOption: FontOption
    var isInFeedView: Bool = false // When true, show author for Reddit posts; when false, show subreddit

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(article.title.decodeHTMLEntities())
                    .font(fontOption == .serif ?
                        .system(.headline, design: .serif) :
                        .system(.headline, design: .default))
                    .fontWeight(article.isRead ? .regular : .semibold)

                // Prefer the value computed at insert. The fallback only fires for articles
                // that predate the cache and have not been backfilled yet — stripping HTML
                // here costs five regular expressions per row while scrolling.
                if let plainText = article.plainTextDescription ?? article.articleDescription?.htmlToPlainText {
                    Text(plainText)
                        .font(fontOption == .serif ?
                            .system(.subheadline, design: .serif) :
                            .system(.subheadline, design: .default))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                HStack {
                    Text(article.publishedDate, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    // For Reddit posts, show subreddit in Today view, author in feed view
                    if article.isRedditPost {
                        if isInFeedView {
                            // In feed view, show author since subreddit is already known
                            if let author = article.author {
                                Text("•")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 4)

                                Text(author)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            // In Today view, show subreddit for context
                            if let subreddit = article.redditSubreddit {
                                Text("•")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 4)

                                Text("r/\(subreddit)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } else {
                        // For non-Reddit posts, show feed title as before
                        if let feedTitle = article.feed?.title {
                            Text("•")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 4)

                            Text(feedTitle)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()
                    if article.hasPodcastAudio {
                        Image(systemName: "waveform")
                            .font(.caption2)
                            .foregroundStyle(Color.accentColor)
                    } else if article.hasMinimalContent && !article.isRedditPost {
                        Image(systemName: "arrow.up.forward.square")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if article.isRead {
                        Image(systemName: "envelope.open.fill")
                            .font(.caption2)
                            .foregroundStyle(Color.accentColor)
                    }
                    if article.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.caption2)
                            .foregroundStyle(.yellow)
                    }
                }
            }

            // Display article image if available
            if let imageUrl = article.imageUrl {
                // Convert HTTP to HTTPS for ATS compliance
                let secureUrl = imageUrl.hasPrefix("http://")
                    ? imageUrl.replacingOccurrences(of: "http://", with: "https://")
                    : imageUrl
                AsyncImage(url: URL(string: secureUrl)) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                            .frame(width: 80, height: 80)
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 80, height: 80)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    case .failure:
                        Image(systemName: "photo")
                            .foregroundStyle(.gray)
                            .frame(width: 80, height: 80)
                            .background(Color.gray.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    @unknown default:
                        EmptyView()
                    }
                }
            }
        }
    }
}

struct ArticleDetailView: View {
    let article: Article
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(article.title)
                    .font(.title2)
                    .fontWeight(.bold)

                HStack {
                    if let author = article.author {
                        Text("By \(author)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(article.publishedDate, style: .date)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Divider()

                if let description = article.articleDescription {
                    Text(description.htmlToAttributedString)
                        .font(.body)
                }

                Button {
                    if let url = article.articleURL {
                        openURL(url)
                    }
                } label: {
                    Label("Read Full Article", systemImage: "safari")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor)
                        .foregroundStyle(.white)
                        .cornerRadius(10)
                }
                .padding(.top)
            }
            .padding()
        }
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}
