//
//  ContentView.swift
//  Today
//
//  Main view with adaptive layout for iPhone (TabView) and iPad (NavigationSplitView)
//

import SwiftUI
import SwiftData
import OSLog

private let logger = Logger(subsystem: "com.today.app", category: "ContentView")

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @AppStorage("appearanceMode") private var appearanceMode: AppearanceMode = .system
    @AppStorage("accentColor") private var accentColor: AccentColorOption = .orange
    @StateObject private var audioPlayer = ArticleAudioPlayer.shared
    @StateObject private var podcastPlayer = PodcastAudioPlayer.shared

    // Mini player height including padding (per player)
    private static let miniPlayerHeight: CGFloat = 120

    private var isTTSActive: Bool {
        audioPlayer.isPlaying || audioPlayer.isPaused
    }

    private var isPodcastActive: Bool {
        podcastPlayer.isPlaying || podcastPlayer.isPaused
    }

    private var totalMiniPlayerHeight: CGFloat {
        var height: CGFloat = 0
        if isTTSActive { height += Self.miniPlayerHeight }
        if isPodcastActive { height += Self.miniPlayerHeight }
        return height
    }

    var body: some View {
        Group {
            if horizontalSizeClass == .regular {
                // iPad/Mac layout with sidebar
                SidebarContentView(modelContext: modelContext)
            } else {
                // iPhone layout with tab bar
                CompactContentView(modelContext: modelContext)
            }
        }
        .preferredColorScheme(appearanceMode.colorScheme)
        .tint(accentColor.color)
        .onAppear {
            // Pre-warm WebView pool for faster article loading
            _ = WebViewPool.shared
        }
    }
}

// MARK: - Compact Layout (iPhone)
struct CompactContentView: View {
    let modelContext: ModelContext
    @StateObject private var audioPlayer = ArticleAudioPlayer.shared
    @StateObject private var podcastPlayer = PodcastAudioPlayer.shared
    
    private static let miniPlayerHeight: CGFloat = 120
    
    private var isTTSActive: Bool {
        audioPlayer.isPlaying || audioPlayer.isPaused
    }
    
    private var isPodcastActive: Bool {
        podcastPlayer.isPlaying || podcastPlayer.isPaused
    }
    
    private var totalMiniPlayerHeight: CGFloat {
        var height: CGFloat = 0
        if isTTSActive { height += Self.miniPlayerHeight }
        if isPodcastActive { height += Self.miniPlayerHeight }
        return height
    }
    
    var body: some View {
        ZStack(alignment: .bottom) {
            TabView {
                TodayView()
                    .tabItem {
                        Label("Today", systemImage: "newspaper")
                    }

                FeedListView(modelContext: modelContext)
                    .tabItem {
                        Label("Feeds", systemImage: "list.bullet")
                    }

                AIChatView()
                    .tabItem {
                        Label("AI Summary", systemImage: "sparkles")
                    }

                SettingsView()
                    .tabItem {
                        Label("Settings", systemImage: "gear")
                    }
            }
            .padding(.bottom, totalMiniPlayerHeight)

            // Global mini audio player (sits above tab bar)
            MiniAudioPlayer()
        }
    }
}

// MARK: - Sidebar Layout (iPad/Mac) - Three Column
struct SidebarContentView: View {
    let modelContext: ModelContext
    @Query(sort: \Feed.title) private var feeds: [Feed]
    @Query(sort: \Article.publishedDate, order: .reverse) private var allArticles: [Article]
    @AppStorage("showAltCategory") private var showAltFeeds = false
    @AppStorage("accentColor") private var accentColor: AccentColorOption = .orange
    @State private var selectedSidebarItem: SidebarItem? = .today
    @State private var selectedArticle: Article?
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var cachedRecentArticles: [Article] = []
    @State private var lastArticleCount: Int = 0
    @State private var lastShowAltFeeds: Bool = false
    @StateObject private var audioPlayer = ArticleAudioPlayer.shared
    @StateObject private var podcastPlayer = PodcastAudioPlayer.shared
    @FocusState private var detailColumnFocused: Bool

    enum SidebarItem: Hashable {
        case today
        case feeds
        case feed(PersistentIdentifier)
        case aiChat
        case settings
    }

    private static let miniPlayerHeight: CGFloat = 120

    private var isTTSActive: Bool {
        audioPlayer.isPlaying || audioPlayer.isPaused
    }

    private var isPodcastActive: Bool {
        podcastPlayer.isPlaying || podcastPlayer.isPaused
    }

    private var totalMiniPlayerHeight: CGFloat {
        var height: CGFloat = 0
        if isTTSActive { height += Self.miniPlayerHeight }
        if isPodcastActive { height += Self.miniPlayerHeight }
        return height
    }

    // Filter feeds based on Alt category visibility
    private var visibleFeeds: [Feed] {
        if showAltFeeds {
            return feeds.filter { $0.category.lowercased() == "alt" }
        } else {
            return feeds.filter { $0.category.lowercased() != "alt" }
        }
    }

    // Group feeds by category (normalized to lowercase for consistent grouping)
    private var feedsByCategory: [(category: String, feeds: [Feed])] {
        let grouped = Dictionary(grouping: visibleFeeds) { $0.category.lowercased() }
        return grouped.sorted { $0.key < $1.key }
            .map { (category: $0.key, feeds: $0.value.sorted { $0.title < $1.title }) }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            mainSplitView
            MiniAudioPlayer()
        }
        .onChange(of: selectedSidebarItem) { oldValue, newValue in
            logger.info("📍 Sidebar selection changed: \(String(describing: oldValue)) → \(String(describing: newValue))")
        }
        .onChange(of: selectedArticle) { oldValue, newValue in
            logger.info("📄 Article selection changed: \(oldValue?.title ?? "nil") → \(newValue?.title ?? "nil")")
        }
        .onAppear {
            logger.info("🚀 SidebarContentView appeared with \(self.feeds.count) feeds, \(self.allArticles.count) articles")
            // Initialize cached articles synchronously on first appear (need data immediately)
            if cachedRecentArticles.isEmpty && !allArticles.isEmpty {
                lastArticleCount = allArticles.count
                lastShowAltFeeds = showAltFeeds
                cachedRecentArticles = computeRecentArticles()
            }
        }
        .task {
            // Auto-select first article on launch (macOS)
            if selectedArticle == nil, let firstArticle = cachedRecentArticles.first {
                selectedArticle = firstArticle
                logger.info("📄 Auto-selected first article: \(firstArticle.title)")
            }
        }
        .onChange(of: allArticles.count) { oldCount, newCount in
            // Update cache when articles change
            updateCachedArticlesIfNeeded()
            // Auto-select first article when articles first load (macOS)
            if oldCount == 0 && newCount > 0 && selectedArticle == nil {
                if let firstArticle = cachedRecentArticles.first {
                    selectedArticle = firstArticle
                    logger.info("📄 Auto-selected first article after load: \(firstArticle.title)")
                }
            }
        }
        .onChange(of: showAltFeeds) { _, _ in
            // Update cache when alt feeds toggle changes
            updateCachedArticlesIfNeeded()
        }
    }

    // MARK: - Navigation Helpers

    private func navigateToNextArticle() {
        guard let current = selectedArticle,
              let currentIndex = currentArticlesList.firstIndex(where: { $0.id == current.id }),
              currentIndex < currentArticlesList.count - 1 else {
            return
        }
        selectedArticle = currentArticlesList[currentIndex + 1]
        logger.info("⌨️ Navigated to next article via keyboard: \(self.currentArticlesList[currentIndex + 1].title)")
    }

    private func navigateToPreviousArticle() {
        guard let current = selectedArticle,
              let currentIndex = currentArticlesList.firstIndex(where: { $0.id == current.id }),
              currentIndex > 0 else {
            return
        }
        selectedArticle = currentArticlesList[currentIndex - 1]
        logger.info("⌨️ Navigated to previous article via keyboard: \(self.currentArticlesList[currentIndex - 1].title)")
    }

    // Cached articles for the Today view (updated when data changes)
    private var recentArticles: [Article] {
        cachedRecentArticles
    }

    // Compute filtered articles - only called when data actually changes
    private func computeRecentArticles() -> [Article] {
        let start = CFAbsoluteTimeGetCurrent()
        let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let result = allArticles.filter { article in
            article.publishedDate >= sevenDaysAgo &&
            (showAltFeeds ? article.feed?.category.lowercased() == "alt" : article.feed?.category.lowercased() != "alt")
        }
        let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000
        if elapsed > 10 {
            logger.info("📊 recentArticles computed in \(elapsed, format: .fixed(precision: 1))ms for \(self.allArticles.count) articles → \(result.count) results")
        }
        return result
    }

    // Update cached articles when underlying data changes
    // Uses Task with sleep to fully break out of layout cycle
    private func updateCachedArticlesIfNeeded() {
        // Only recompute if data actually changed
        guard allArticles.count != lastArticleCount || showAltFeeds != lastShowAltFeeds else {
            return
        }

        // Capture current values before async
        let currentCount = allArticles.count
        let currentShowAlt = showAltFeeds

        // Use Task with tiny sleep to fully break out of current layout cycle
        Task { @MainActor in
            // Tiny delay to escape the layout pass
            try? await Task.sleep(for: .milliseconds(10))

            // Double-check we still need to update
            guard currentCount != lastArticleCount || currentShowAlt != lastShowAltFeeds else {
                return
            }
            lastArticleCount = currentCount
            lastShowAltFeeds = currentShowAlt
            cachedRecentArticles = computeRecentArticles()
        }
    }

    // MARK: - Main Split View
    private var mainSplitView: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebarList
                .navigationTitle("Today")
                .listStyle(.sidebar)
        } content: {
            contentColumnView
        } detail: {
            detailColumnView
        }
        .navigationSplitViewStyle(.balanced)
        .padding(.bottom, totalMiniPlayerHeight)
        #if os(macOS)
        .focusedSceneValue(\.selectedArticle, $selectedArticle)
        .modifier(KeyboardShortcutsModifier(
            selectedSidebarItem: $selectedSidebarItem,
            onNextArticle: navigateToNextArticle,
            onPreviousArticle: navigateToPreviousArticle
        ))
        #endif
    }

    // MARK: - Detail Column View
    @ViewBuilder
    private var detailColumnView: some View {
        if let article = selectedArticle {
            ArticleDetailColumn(
                article: article,
                articles: currentArticlesList,
                selectedArticle: $selectedArticle
            )
            .id(article.id)
        } else {
            ContentUnavailableView(
                "Select an Article",
                systemImage: "doc.text",
                description: Text("Choose an article from the list to read it here.")
            )
        }
    }

    // MARK: - Content Column View
    @ViewBuilder
    private var contentColumnView: some View {
        if let selected = selectedSidebarItem {
            switch selected {
            case .today:
                ArticleListColumn(
                    articles: recentArticles,
                    title: "Today",
                    selectedArticle: $selectedArticle
                )
            case .feeds:
                FeedListView(modelContext: modelContext)
            case .feed(let feedId):
                if let feed = feeds.first(where: { $0.id == feedId }) {
                    ArticleListColumn(
                        articles: feed.articles?.sorted { $0.publishedDate > $1.publishedDate } ?? [],
                        title: feed.title,
                        selectedArticle: $selectedArticle
                    )
                } else {
                    ContentUnavailableView(
                        "Feed Not Found",
                        systemImage: "doc.text.fill.badge.questionmark",
                        description: Text("This feed is no longer available.")
                    )
                }
            case .aiChat:
                AIChatView()
            case .settings:
                SettingsView()
            }
        } else {
            ArticleListColumn(
                articles: recentArticles,
                title: "Today",
                selectedArticle: $selectedArticle
            )
        }
    }

    // Current articles list based on sidebar selection (for prev/next navigation)
    private var currentArticlesList: [Article] {
        guard let selected = selectedSidebarItem else {
            return recentArticles
        }
        switch selected {
        case .today:
            return recentArticles
        case .feed(let feedId):
            if let feed = feeds.first(where: { $0.id == feedId }) {
                return feed.articles?.sorted { $0.publishedDate > $1.publishedDate } ?? []
            }
            return []
        case .feeds, .aiChat, .settings:
            return recentArticles
        }
    }

    // MARK: - Sidebar List

    @ViewBuilder
    private var sidebarList: some View {
        #if os(macOS)
        // On macOS, use manual selection to avoid system highlight overlay
        List {
            // Main sections
            Section {
                sidebarButton(item: .today, label: "Today", icon: "newspaper")
                sidebarButton(item: .feeds, label: "Manage Feeds", icon: "list.bullet")
            }

            // Feeds grouped by category
            ForEach(feedsByCategory, id: \.category) { categoryGroup in
                Section(header: Text(categoryGroup.category.capitalized)) {
                    ForEach(categoryGroup.feeds, id: \.id) { feed in
                        sidebarButton(item: .feed(feed.id), label: feed.title, icon: "doc.text")
                    }
                }
            }

            // AI and Settings
            Section {
                sidebarButton(item: .aiChat, label: "AI Summary", icon: "sparkles")
                sidebarButton(item: .settings, label: "Settings", icon: "gear")
            }
        }
        #else
        List(selection: $selectedSidebarItem) {
            // Main sections
            Section {
                NavigationLink(value: SidebarItem.today) {
                    Label("Today", systemImage: "newspaper")
                }
                NavigationLink(value: SidebarItem.feeds) {
                    Label("Manage Feeds", systemImage: "list.bullet")
                }
            }

            // Feeds grouped by category
            ForEach(feedsByCategory, id: \.category) { categoryGroup in
                Section(header: Text(categoryGroup.category.capitalized)) {
                    ForEach(categoryGroup.feeds, id: \.id) { feed in
                        NavigationLink(value: SidebarItem.feed(feed.id)) {
                            Label(feed.title, systemImage: "doc.text")
                        }
                    }
                }
            }

            // AI and Settings
            Section {
                NavigationLink(value: SidebarItem.aiChat) {
                    Label("AI Summary", systemImage: "sparkles")
                }
                NavigationLink(value: SidebarItem.settings) {
                    Label("Settings", systemImage: "gear")
                }
            }
        }
        #endif
    }

    #if os(macOS)
    // Helper to create sidebar button with custom selection background
    @ViewBuilder
    private func sidebarButton(item: SidebarItem, label: String, icon: String) -> some View {
        Button {
            selectedSidebarItem = item
        } label: {
            Label(label, systemImage: icon)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(sidebarRowBackground(for: item))
    }

    // Custom sidebar row background that respects the app's accent color
    @ViewBuilder
    private func sidebarRowBackground(for item: SidebarItem) -> some View {
        if selectedSidebarItem == item {
            RoundedRectangle(cornerRadius: 4)
                .fill(accentColor.color.opacity(0.15))
        } else {
            Color.clear
        }
    }
    #endif
}

// MARK: - Article Filter Options
enum ArticleFilter: String, CaseIterable {
    case all = "All"
    case unread = "Unread"
    case favorites = "Favorites"

    var systemImage: String {
        switch self {
        case .all: return "tray.full"
        case .unread: return "envelope.badge"
        case .favorites: return "star"
        }
    }
}

// MARK: - Article Sort Options
enum ArticleSort: String, CaseIterable {
    case newest = "Newest First"
    case oldest = "Oldest First"
    case title = "By Title"

    var systemImage: String {
        switch self {
        case .newest: return "arrow.down"
        case .oldest: return "arrow.up"
        case .title: return "textformat"
        }
    }
}

// MARK: - Article List Column (Middle Column)
struct ArticleListColumn: View {
    let articles: [Article]
    let title: String
    @Binding var selectedArticle: Article?
    @State private var searchText = ""
    @State private var filter: ArticleFilter = .all
    @State private var sort: ArticleSort = .newest

    private var processedArticles: [Article] {
        let start = CFAbsoluteTimeGetCurrent()
        var result = articles

        // Apply filter
        result = applyFilter(to: result)
        
        // Apply search
        result = applySearch(to: result)
        
        // Apply sort
        result = applySort(to: result)

        let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000
        if elapsed > 10 {
            logger.warning("⚠️ processedArticles took \(elapsed, format: .fixed(precision: 1))ms for \(self.articles.count) articles")
        }
        return result
    }
    
    private func applyFilter(to articles: [Article]) -> [Article] {
        switch filter {
        case .all:
            return articles
        case .unread:
            return articles.filter { !$0.isRead }
        case .favorites:
            return articles.filter { $0.isFavorite }
        }
    }
    
    private func applySearch(to articles: [Article]) -> [Article] {
        guard !searchText.isEmpty else { return articles }
        
        return articles.filter { article in
            let titleMatches = article.title.localizedCaseInsensitiveContains(searchText)
            let descriptionMatches = article.articleDescription?.localizedCaseInsensitiveContains(searchText) ?? false
            let contentMatches = article.content?.localizedCaseInsensitiveContains(searchText) ?? false
            return titleMatches || descriptionMatches || contentMatches
        }
    }
    
    private func applySort(to articles: [Article]) -> [Article] {
        switch sort {
        case .newest:
            return articles.sorted { $0.publishedDate > $1.publishedDate }
        case .oldest:
            return articles.sorted { $0.publishedDate < $1.publishedDate }
        case .title:
            return articles.sorted { $0.title.localizedCompare($1.title) == .orderedAscending }
        }
    }

    var body: some View {
        articleList
            .navigationTitle(title)
            .searchable(text: $searchText, prompt: "Search articles")
            .onAppear {
                logger.info("📋 ArticleListColumn appeared: \(title) with \(articles.count) articles")
            }
            .onChange(of: selectedArticle) { oldValue, newValue in
                logger.info("📋 ArticleListColumn selection changed: \(oldValue?.title ?? "nil") → \(newValue?.title ?? "nil")")
            }
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    // Filter menu
                    Menu {
                        Picker("Filter", selection: $filter) {
                            ForEach(ArticleFilter.allCases, id: \.self) { filterOption in
                                Label(filterOption.rawValue, systemImage: filterOption.systemImage)
                                    .tag(filterOption)
                            }
                        }
                    } label: {
                        Label("Filter", systemImage: filter == .all ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                    }

                    // Sort menu
                    Menu {
                        Picker("Sort", selection: $sort) {
                            ForEach(ArticleSort.allCases, id: \.self) { sortOption in
                                Label(sortOption.rawValue, systemImage: sortOption.systemImage)
                                    .tag(sortOption)
                            }
                        }
                    } label: {
                        Label("Sort", systemImage: "arrow.up.arrow.down")
                    }
                }
            }
    }

    @ViewBuilder
    private var articleList: some View {
        #if os(macOS)
        // On macOS, don't use List selection binding to avoid system highlight overlay
        List {
            ForEach(processedArticles) { article in
                SidebarArticleRow(article: article, isSelected: selectedArticle?.id == article.id)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedArticle = article
                    }
            }
        }
        #else
        List(selection: $selectedArticle) {
            ForEach(processedArticles) { article in
                SidebarArticleRow(article: article, isSelected: selectedArticle?.id == article.id)
                    .tag(article)
            }
        }
        #endif
    }
}

// MARK: - Sidebar Article Row View
struct SidebarArticleRow: View {
    let article: Article
    var isSelected: Bool = false
    @Environment(\.modelContext) private var modelContext
    @AppStorage("accentColor") private var accentColor: AccentColorOption = .orange

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(article.title.decodeHTMLEntities())
                    .font(.headline)
                    .fontWeight(article.isRead ? .regular : .semibold)
                    .foregroundStyle(isSelected ? Color.white : (article.isRead ? .secondary : .primary))

                if let plainText = article.plainTextDescription ?? article.articleDescription?.htmlToPlainText {
                    Text(plainText)
                        .font(.subheadline)
                        .foregroundStyle(isSelected ? Color.white.opacity(0.9) : .secondary)
                        .lineLimit(2)
                }

                HStack {
                    Text(article.publishedDate, style: .relative)
                        .font(.caption)
                        .foregroundStyle(isSelected ? Color.white.opacity(0.8) : Color.primary.opacity(0.6))

                    if article.isRedditPost {
                        if let author = article.author {
                            Text("•")
                                .font(.caption)
                                .foregroundStyle(isSelected ? Color.white.opacity(0.8) : Color.primary.opacity(0.6))
                            Text(author)
                                .font(.caption)
                                .foregroundStyle(isSelected ? Color.white.opacity(0.8) : Color.primary.opacity(0.6))
                        }
                    } else if let feedTitle = article.feed?.title {
                        Text("•")
                            .font(.caption)
                            .foregroundStyle(isSelected ? Color.white.opacity(0.8) : Color.primary.opacity(0.6))
                        Text(feedTitle)
                            .font(.caption)
                            .foregroundStyle(isSelected ? Color.white.opacity(0.8) : Color.primary.opacity(0.6))
                    }

                    Spacer()

                    // Status indicators
                    if article.hasPodcastAudio {
                        Image(systemName: "waveform")
                            .font(.caption)
                            .foregroundStyle(isSelected ? Color.white : accentColor.color)
                    } else if article.hasMinimalContent && !article.isRedditPost {
                        Image(systemName: "arrow.up.forward.square")
                            .font(.caption)
                            .foregroundStyle(isSelected ? Color.white.opacity(0.8) : Color.primary.opacity(0.6))
                    }
                    if article.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.caption)
                            .foregroundStyle(isSelected ? Color.white : .yellow)
                    }
                }
            }

            // Thumbnail image
            if let imageUrl = article.imageUrl {
                let secureUrl = imageUrl.hasPrefix("http://")
                    ? imageUrl.replacingOccurrences(of: "http://", with: "https://")
                    : imageUrl
                AsyncImage(url: URL(string: secureUrl)) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                            .frame(width: 60, height: 60)
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 60, height: 60)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    case .failure:
                        Image(systemName: "photo")
                            .foregroundStyle(.gray)
                            .frame(width: 60, height: 60)
                            .background(Color.gray.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    @unknown default:
                        EmptyView()
                    }
                }
            }
        }
        .padding(.vertical, 4)
        #if os(macOS)
        .padding(.horizontal, 8)
        .background(
            isSelected
                ? RoundedRectangle(cornerRadius: 8)
                    .fill(accentColor.color)
                : nil
        )
        #endif
        .contextMenu {
            // Mark Read/Unread
            Button {
                article.isRead.toggle()
                try? modelContext.save()
            } label: {
                Label(
                    article.isRead ? "Mark as Unread" : "Mark as Read",
                    systemImage: article.isRead ? "envelope.badge" : "envelope.open"
                )
            }

            // Favorite/Unfavorite
            Button {
                article.isFavorite.toggle()
                try? modelContext.save()
            } label: {
                Label(
                    article.isFavorite ? "Remove from Favorites" : "Add to Favorites",
                    systemImage: article.isFavorite ? "star.slash" : "star"
                )
            }

            Divider()

            // Share
            if let url = article.articleURL {
                ShareLink(item: url) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
            }

            // Open in Safari
            if let url = article.articleURL {
                Link(destination: url) {
                    Label("Open in Safari", systemImage: "safari")
                }
            }
        }
    }
}

// MARK: - Article Detail Column (Right Column)
struct ArticleDetailColumn: View {
    let article: Article
    let articles: [Article]
    @Binding var selectedArticle: Article?
    @Environment(\.modelContext) private var modelContext
    @State private var isAtBottom = false

    // Find current article index and compute previous/next
    private var currentIndex: Int? {
        articles.firstIndex(where: { $0.id == article.id })
    }

    private var previousArticle: Article? {
        guard let index = currentIndex, index > 0 else { return nil }
        return articles[index - 1]
    }

    private var nextArticle: Article? {
        guard let index = currentIndex, index < articles.count - 1 else { return nil }
        return articles[index + 1]
    }
    
    private func handleSpaceBarPress() {
        // For Reddit posts: space bar advances to next article
        // (Users can scroll comments with trackpad/mouse; space provides quick navigation)
        if article.isRedditPost {
            if let next = nextArticle {
                selectedArticle = next
                logger.info("⌨️ Space on Reddit: advanced to next article: \(next.title)")
            }
            return
        }
        
        // For regular articles with WebView scrolling
        if isAtBottom {
            // At bottom, advance to next article
            if let next = nextArticle {
                selectedArticle = next
                logger.info("⌨️ Space at bottom: advanced to next article: \(next.title)")
            }
        } else {
            // Not at bottom, scroll page down
            #if os(macOS)
            NotificationCenter.default.post(name: .scrollPageDown, object: nil)
            logger.info("⌨️ Space: scrolling page down")
            #endif
        }
    }

    var body: some View {
        Group {
            // Show RedditPostView directly for Reddit posts (full width for visual content)
            // Regular articles get constrained width for comfortable reading
            if article.isRedditPost {
                RedditPostView(
                    article: article,
                    previousArticleID: previousArticle?.persistentModelID,
                    nextArticleID: nextArticle?.persistentModelID,
                    onNavigateToPrevious: { _ in
                        if let prev = previousArticle {
                            selectedArticle = prev
                        }
                    },
                    onNavigateToNext: { _ in
                        if let next = nextArticle {
                            selectedArticle = next
                        }
                    }
                )
            } else {
                ArticleDetailSimple(
                    article: article,
                    previousArticleID: previousArticle?.persistentModelID,
                    nextArticleID: nextArticle?.persistentModelID,
                    onNavigateToPrevious: { _ in
                        if let prev = previousArticle {
                            selectedArticle = prev
                        }
                    },
                    onNavigateToNext: { _ in
                        if let next = nextArticle {
                            selectedArticle = next
                        }
                    }
                )
            }
        }
        .modifier(ArticleActionShortcutsModifier(article: article))
        #if os(macOS)
        // Space bar handler works for all article types
        .background {
            Button("") { handleSpaceBarPress() }
                .keyboardShortcut(.space, modifiers: [])
                .opacity(0)
        }
        // Scroll position tracking (only fires for WebView-based articles)
        .onReceive(NotificationCenter.default.publisher(for: .articleScrolledToBottom)) { notification in
            if let scrolledArticleID = notification.object as? PersistentIdentifier,
               scrolledArticleID == article.persistentModelID {
                isAtBottom = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .articleScrolledFromBottom)) { notification in
            if let scrolledArticleID = notification.object as? PersistentIdentifier,
               scrolledArticleID == article.persistentModelID {
                isAtBottom = false
            }
        }
        #endif
        .onAppear {
            logger.info("📖 ArticleDetailColumn appeared: \(article.title) (Reddit: \(article.isRedditPost))")
            // Mark as read when displayed
            if !article.isRead {
                article.isRead = true
                try? modelContext.save()
            }
        }
        .onChange(of: article.id) { _, _ in
            // Reset bottom state when article changes
            isAtBottom = false
        }
    }
}

// MARK: - Feed Detail View
struct FeedDetailView: View {
    let feed: Feed
    @State private var searchText = ""
    
    // Query articles filtered by feed at the database level for better performance
    @Query private var articles: [Article]
    
    init(feed: Feed) {
        self.feed = feed
        // Use predicate to filter at database level
        let feedId = feed.id
        let predicate = #Predicate<Article> { article in
            article.feed?.id == feedId
        }
        _articles = Query(
            filter: predicate,
            sort: \Article.publishedDate,
            order: .reverse
        )
    }
    
    private var filteredArticles: [Article] {
        guard !searchText.isEmpty else { return articles }
        return articles.filter { article in
            article.title.localizedCaseInsensitiveContains(searchText) ||
            (article.articleDescription?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }
    
    var body: some View {
        List {
            ForEach(Array(filteredArticles.enumerated()), id: \.element.id) { index, article in
                NavigationLink {
                    // Provide navigation context for previous/next article navigation
                    let previousArticleID = index > 0 ? filteredArticles[index - 1].id : nil
                    let nextArticleID = index < filteredArticles.count - 1 ? filteredArticles[index + 1].id : nil
                    
                    ArticleDetailSimple(
                        article: article,
                        previousArticleID: previousArticleID,
                        nextArticleID: nextArticleID,
                        onNavigateToPrevious: { _ in
                            // Navigation handled by SwiftUI
                        },
                        onNavigateToNext: { _ in
                            // Navigation handled by SwiftUI
                        }
                    )
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(article.title)
                            .font(.headline)
                        if let description = article.articleDescription {
                            Text(description)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        Text(article.publishedDate, style: .relative)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .navigationTitle(feed.title)
        .searchable(text: $searchText, prompt: "Search articles")
    }
}

// MARK: - Keyboard Shortcuts Modifier
#if os(macOS)
struct KeyboardShortcutsModifier: ViewModifier {
    @Binding var selectedSidebarItem: SidebarContentView.SidebarItem?
    let onNextArticle: () -> Void
    let onPreviousArticle: () -> Void
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    
    func body(content: Content) -> some View {
        content
            .background {
                // All keyboard shortcuts (hidden buttons that respond to key presses)
                Group {
                    // Sidebar navigation shortcuts
                    Button("") { selectedSidebarItem = .today }
                        .keyboardShortcut("1", modifiers: .command)
                    Button("") { selectedSidebarItem = .feeds }
                        .keyboardShortcut("2", modifiers: .command)
                    Button("") { selectedSidebarItem = .aiChat }
                        .keyboardShortcut("3", modifiers: .command)
                    Button("") { selectedSidebarItem = .settings }
                        .keyboardShortcut("4", modifiers: .command)
                    
                    // Article navigation shortcuts (J/K keys)
                    Button("") { onNextArticle() }
                        .keyboardShortcut("j", modifiers: [])
                    Button("") { onPreviousArticle() }
                        .keyboardShortcut("k", modifiers: [])
                }
                .opacity(0)
            }
            .onReceive(NotificationCenter.default.publisher(for: .navigateToNextArticle)) { _ in
                onNextArticle()
            }
            .onReceive(NotificationCenter.default.publisher(for: .navigateToPreviousArticle)) { _ in
                onPreviousArticle()
            }
    }
}

// MARK: - Article Action Shortcuts Modifier
struct ArticleActionShortcutsModifier: ViewModifier {
    let article: Article
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    
    func body(content: Content) -> some View {
        content
            .background {
                // Direct keyboard shortcuts for article actions
                Group {
                    Button("") { toggleFavorite() }
                        .keyboardShortcut("f", modifiers: .command)
                    Button("") { toggleRead() }
                        .keyboardShortcut("u", modifiers: .command)
                    Button("") { openInBrowser() }
                        .keyboardShortcut("o", modifiers: .command)
                    Button("") { shareArticle() }
                        .keyboardShortcut("s", modifiers: [.command, .shift])
                }
                .opacity(0)
            }
            .onReceive(NotificationCenter.default.publisher(for: .toggleArticleFavorite)) { _ in
                toggleFavorite()
            }
            .onReceive(NotificationCenter.default.publisher(for: .toggleArticleRead)) { _ in
                toggleRead()
            }
            .onReceive(NotificationCenter.default.publisher(for: .openArticleInBrowser)) { _ in
                openInBrowser()
            }
            .onReceive(NotificationCenter.default.publisher(for: .shareArticle)) { _ in
                shareArticle()
            }
    }
    
    private func toggleFavorite() {
        article.isFavorite.toggle()
        try? modelContext.save()
        logger.info("⌨️ Toggled favorite via keyboard: \(article.title) → \(article.isFavorite)")
    }
    
    private func toggleRead() {
        article.isRead.toggle()
        try? modelContext.save()
        logger.info("⌨️ Toggled read via keyboard: \(article.title) → \(article.isRead)")
    }
    
    private func openInBrowser() {
        guard let url = article.articleURL else { return }
        openURL(url)
        logger.info("⌨️ Opened in browser via keyboard: \(article.title)")
    }
    
    private func shareArticle() {
        guard let url = article.articleURL else { return }
        // Create a sharing service picker
        let sharingPicker = NSSharingServicePicker(items: [url])
        
        // Get the key window and present from its content view
        if let window = NSApp.keyWindow,
           let contentView = window.contentView {
            sharingPicker.show(relativeTo: .zero, of: contentView, preferredEdge: .minY)
            logger.info("⌨️ Shared article via keyboard: \(article.title)")
        }
    }
}
#else
struct KeyboardShortcutsModifier: ViewModifier {
    @Binding var selectedSidebarItem: SidebarContentView.SidebarItem?
    let onNextArticle: () -> Void
    let onPreviousArticle: () -> Void
    
    func body(content: Content) -> some View {
        content // No keyboard shortcuts on iOS
    }
}

struct ArticleActionShortcutsModifier: ViewModifier {
    let article: Article
    
    func body(content: Content) -> some View {
        content // No keyboard shortcuts on iOS
    }
}
#endif

#Preview {
    ContentView()
        .modelContainer(for: Feed.self, inMemory: true)
}
