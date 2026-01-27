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

    @Query(sort: \Article.publishedDate, order: .reverse) private var allArticles: [Article]
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

    // Cache expensive computations
    // Show categories that have articles in the current time window OR are custom categories
    private var categories: [String] {
        // Apply time filter (same as filteredArticles)
        let now = Date.now
        let startOfToday = Calendar.current.startOfDay(for: now)
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -daysToLoad, to: startOfToday)!
        let timeFilteredArticles = allArticles.filter { $0.publishedDate >= cutoffDate }

        // Get all unique categories from articles in the time window
        var feedCategories = Set(timeFilteredArticles.compactMap { $0.feed?.category })

        // Add custom categories from CategoryManager (even if they don't have articles yet)
        for customCategory in categoryManager.customCategories {
            feedCategories.insert(customCategory)
        }

        // Filter based on Alt category visibility
        if showAltCategory {
            // When showing Alt, only show Alt category
            feedCategories = feedCategories.filter { $0.lowercased() == "alt" }
        } else {
            // When not showing Alt, exclude Alt category
            feedCategories = feedCategories.filter { $0.lowercased() != "alt" }
        }

        var result = ["All"]

        // Add Podcasts category if there are podcast articles
        if hasPodcastArticles {
            result.append(String(localized: "Podcasts"))
        }

        return result + feedCategories.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    // Count unread/favorites in the current time window and category
    // (but not search/hideRead/showFavorites to avoid circular deps)
    private var unreadCount: Int {
        var articles = allArticles

        // Apply same time filter as filteredArticles
        let now = Date.now
        let startOfToday = Calendar.current.startOfDay(for: now)
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -daysToLoad, to: startOfToday)!
        articles = articles.filter { $0.publishedDate >= cutoffDate }

        // Apply same category filter as filteredArticles
        let podcastsCategory = String(localized: "Podcasts")
        if selectedCategory == podcastsCategory {
            articles = articles.filter { $0.hasPodcastAudio }
        } else if selectedCategory != "All" {
            articles = articles.filter { $0.feed?.category == selectedCategory }
        }

        return articles.lazy.filter { !$0.isRead }.count
    }

    private var favoritesCount: Int {
        var articles = allArticles

        // Apply same time filter as filteredArticles
        let now = Date.now
        let startOfToday = Calendar.current.startOfDay(for: now)
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -daysToLoad, to: startOfToday)!
        articles = articles.filter { $0.publishedDate >= cutoffDate }

        // Apply same category filter as filteredArticles
        let podcastsCategory = String(localized: "Podcasts")
        if selectedCategory == podcastsCategory {
            articles = articles.filter { $0.hasPodcastAudio }
        } else if selectedCategory != "All" {
            articles = articles.filter { $0.feed?.category == selectedCategory }
        }

        return articles.lazy.filter { $0.isFavorite }.count
    }

    private var activeFilterCount: Int {
        showFavoritesOnly ? favoritesCount : unreadCount
    }

    // Total counts across all articles (for reference)
    private var totalUnreadCount: Int {
        allArticles.lazy.filter { !$0.isRead }.count
    }

    private var totalFavoritesCount: Int {
        allArticles.lazy.filter { $0.isFavorite }.count
    }

    // Check if there are any Alt articles
    private var hasAltArticles: Bool {
        allArticles.contains { $0.feed?.category.lowercased() == "alt" }
    }

    // Check if there are any podcast articles (ignores date filter since Podcasts shows all episodes)
    private var hasPodcastArticles: Bool {
        allArticles.contains { article in
            article.hasPodcastAudio &&
            // Respect Alt category visibility
            (showAltCategory ? article.feed?.category.lowercased() == "alt" : article.feed?.category.lowercased() != "alt")
        }
    }

    private var filteredArticles: [Article] {
        var articles = allArticles
        let podcastsCategory = String(localized: "Podcasts")

        // Filter by date range based on daysToLoad
        // Skip date filter for Podcasts - show all podcast episodes regardless of date
        if selectedCategory != podcastsCategory {
            let now = Date.now
            let startOfToday = Calendar.current.startOfDay(for: now)
            let cutoffDate = Calendar.current.date(byAdding: .day, value: -daysToLoad, to: startOfToday)!
            articles = articles.filter { $0.publishedDate >= cutoffDate }
        }

        // Filter based on Alt category visibility
        if showAltCategory {
            // When showing Alt, only show Alt articles
            articles = articles.filter { $0.feed?.category.lowercased() == "alt" }
        } else {
            // When not showing Alt, exclude Alt articles
            articles = articles.filter { $0.feed?.category.lowercased() != "alt" }
        }

        // Filter by category
        if selectedCategory == podcastsCategory {
            // Special handling for Podcasts virtual category - shows all podcasts
            articles = articles.filter { $0.hasPodcastAudio }
        } else if selectedCategory != "All" {
            articles = articles.filter { $0.feed?.category == selectedCategory }
        }

        // Filter by search text
        if !searchText.isEmpty {
            articles = articles.filter {
                $0.title.localizedCaseInsensitiveContains(searchText) ||
                $0.articleDescription?.localizedCaseInsensitiveContains(searchText) == true
            }
        }

        // Filter by read status
        if hideReadArticles {
            articles = articles.filter { !$0.isRead }
        }

        // Filter by favorites
        if showFavoritesOnly {
            articles = articles.filter { $0.isFavorite }
        }

        return articles
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
                    if showFavoritesOnly && !allArticles.isEmpty {
                        ContentUnavailableView(
                            "No Favorites Yet",
                            systemImage: "star",
                            description: Text("Swipe left on articles to add them to favorites.")
                        )
                    } else if hideReadArticles && !allArticles.isEmpty {
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
            .searchable(text: $searchText, prompt: "Search articles")
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
                if let article = modelContext.model(for: state.articleID) as? Article {
                    // For Reddit posts, show combined post + comments view
                    if article.isRedditPost {
                        if !state.context.isEmpty,
                           let currentIndex = state.context.firstIndex(of: state.articleID) {
                            let previousIndex = currentIndex - 1
                            let nextIndex = currentIndex + 1
                            let previousArticleID = previousIndex >= 0 ? state.context[previousIndex] : nil
                            let nextArticleID = nextIndex < state.context.count ? state.context[nextIndex] : nil

                            RedditPostView(
                                article: article,
                                previousArticleID: previousArticleID,
                                nextArticleID: nextArticleID,
                                onNavigateToPrevious: { prevID in
                                    Task { @MainActor in
                                        try? await Task.sleep(nanoseconds: 50_000_000)
                                        navigationState = NavigationState(articleID: prevID, context: state.context)
                                    }
                                },
                                onNavigateToNext: { nextID in
                                    Task { @MainActor in
                                        try? await Task.sleep(nanoseconds: 50_000_000)
                                        navigationState = NavigationState(articleID: nextID, context: state.context)
                                    }
                                }
                            )
                            .id(state.articleID)  // Force view refresh when article changes
                        } else {
                            RedditPostView(
                                article: article,
                                previousArticleID: nil,
                                nextArticleID: nil,
                                onNavigateToPrevious: { _ in },
                                onNavigateToNext: { _ in }
                            )
                        }
                    }
                    // For all other articles, show in-app article detail
                    // Use the captured navigation context (stable across view updates)
                    else if !state.context.isEmpty,
                       let currentIndex = state.context.firstIndex(of: state.articleID) {
                        let previousIndex = currentIndex - 1
                        let nextIndex = currentIndex + 1
                        let previousArticleID = previousIndex >= 0 ? state.context[previousIndex] : nil
                        let nextArticleID = nextIndex < state.context.count ? state.context[nextIndex] : nil

                        ArticleDetailSimple(
                            article: article,
                            previousArticleID: previousArticleID,
                            nextArticleID: nextArticleID,
                            onNavigateToPrevious: { prevID in
                                Task { @MainActor in
                                    try? await Task.sleep(nanoseconds: 50_000_000)
                                    navigationState = NavigationState(articleID: prevID, context: state.context)
                                }
                            },
                            onNavigateToNext: { nextID in
                                Task { @MainActor in
                                    try? await Task.sleep(nanoseconds: 50_000_000)
                                    navigationState = NavigationState(articleID: nextID, context: state.context)
                                }
                            }
                        )
                    } else {
                        ArticleDetailSimple(
                            article: article,
                            previousArticleID: nil,
                            nextArticleID: nil,
                            onNavigateToPrevious: { _ in },
                            onNavigateToNext: { _ in }
                        )
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
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
                            Text("\(unreadCount) unread (\(totalUnreadCount) total) • \(favoritesCount) favorites (\(totalFavoritesCount) total)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("\(unreadCount) unread • \(favoritesCount) favorites")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: (hideReadArticles || showFavoritesOnly) ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                            if hideReadArticles || showFavoritesOnly {
                                if activeFilterCount > 0 {
                                    Text("\(activeFilterCount)")
                                        .font(.caption2)
                                        .fontWeight(.semibold)
                                }
                            }
                        }
                    }
                }
            }
            .confirmationDialog(
                selectedCategory == "All"
                    ? "Mark all \(unreadCount) articles as read?"
                    : "Mark all \(unreadCount) articles in \(selectedCategory) as read?",
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
        .task {
            // Background task to populate plain text cache for existing articles
            await populatePlainTextCache()
        }
    }

    private func populatePlainTextCache() async {
        let articlesNeedingCache = allArticles.filter { $0.plainTextDescription == nil && $0.articleDescription != nil }

        guard !articlesNeedingCache.isEmpty else { return }

        // Process on main actor (required for SwiftData models)
        for article in articlesNeedingCache {
            if article.plainTextDescription == nil, let desc = article.articleDescription {
                article.plainTextDescription = desc.htmlToPlainText
            }
        }

        // Save once after processing all
        try? modelContext.save()
    }

    private func markAllAsRead() {
        var articlesToMark = allArticles.filter { !$0.isRead }

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

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(article.title.decodeHTMLEntities())
                    .font(fontOption == .serif ?
                        .system(.headline, design: .serif) :
                        .system(.headline, design: .default))
                    .fontWeight(article.isRead ? .regular : .semibold)

                // Use cached plain text if available, otherwise compute on-the-fly
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

                    // For Reddit posts, show author instead of feed title (since feed title is in header)
                    if article.isRedditPost {
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
        .navigationBarTitleDisplayMode(.inline)
    }
}
