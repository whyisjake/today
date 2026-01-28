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
    @State private var selectedSidebarItem: SidebarItem? = .today
    @State private var selectedArticle: Article?
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @StateObject private var audioPlayer = ArticleAudioPlayer.shared
    @StateObject private var podcastPlayer = PodcastAudioPlayer.shared

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
            NavigationSplitView(columnVisibility: $columnVisibility) {
                // Sidebar (Column 1): Feed list and navigation
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
                .navigationTitle("Today")
                .listStyle(.sidebar)
            } content: {
                // Content (Column 2): Article list or management views
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
            } detail: {
                // Detail (Column 3): Article content
                if let article = selectedArticle {
                    ArticleDetailColumn(
                        article: article,
                        articles: currentArticlesList,
                        selectedArticle: $selectedArticle
                    )
                    .id(article.id) // Force complete view recreation on article change
                } else {
                    ContentUnavailableView(
                        "Select an Article",
                        systemImage: "doc.text",
                        description: Text("Choose an article from the list to read it here.")
                    )
                }
            }
            .navigationSplitViewStyle(.balanced)
            .padding(.bottom, totalMiniPlayerHeight)
            // Keyboard shortcuts for sidebar navigation
            .background {
                Group {
                    Button("") { selectedSidebarItem = .today }
                        .keyboardShortcut("1", modifiers: .command)
                    Button("") { selectedSidebarItem = .feeds }
                        .keyboardShortcut("2", modifiers: .command)
                    Button("") { selectedSidebarItem = .aiChat }
                        .keyboardShortcut("3", modifiers: .command)
                    Button("") { selectedSidebarItem = .settings }
                        .keyboardShortcut("4", modifiers: .command)
                }
                .opacity(0)
            }

            // Global mini audio player
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
        }
    }

    // Articles from the last 7 days for the Today view
    private var recentArticles: [Article] {
        let start = CFAbsoluteTimeGetCurrent()
        let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let result = allArticles.filter { article in
            article.publishedDate >= sevenDaysAgo &&
            (showAltFeeds ? article.feed?.category.lowercased() == "alt" : article.feed?.category.lowercased() != "alt")
        }
        let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000
        if elapsed > 10 {
            logger.warning("⚠️ recentArticles took \(elapsed, format: .fixed(precision: 1))ms for \(self.allArticles.count) articles → \(result.count) results")
        }
        return result
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
        switch filter {
        case .all:
            break
        case .unread:
            result = result.filter { !$0.isRead }
        case .favorites:
            result = result.filter { $0.isFavorite }
        }

        // Apply search
        if !searchText.isEmpty {
            result = result.filter { article in
                article.title.localizedCaseInsensitiveContains(searchText) ||
                (article.articleDescription?.localizedCaseInsensitiveContains(searchText) ?? false) ||
                (article.content?.localizedCaseInsensitiveContains(searchText) ?? false)
            }
        }

        // Apply sort
        switch sort {
        case .newest:
            result = result.sorted { $0.publishedDate > $1.publishedDate }
        case .oldest:
            result = result.sorted { $0.publishedDate < $1.publishedDate }
        case .title:
            result = result.sorted { $0.title.localizedCompare($1.title) == .orderedAscending }
        }

        let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000
        if elapsed > 10 {
            logger.warning("⚠️ processedArticles took \(elapsed, format: .fixed(precision: 1))ms for \(self.articles.count) articles")
        }
        return result
    }

    var body: some View {
        List(selection: $selectedArticle) {
            ForEach(processedArticles) { article in
                SidebarArticleRow(article: article)
                    .tag(article)
            }
        }
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
}

// MARK: - Sidebar Article Row View
struct SidebarArticleRow: View {
    let article: Article
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(article.title.decodeHTMLEntities())
                    .font(.headline)
                    .fontWeight(article.isRead ? .regular : .semibold)
                    .foregroundStyle(article.isRead ? .secondary : .primary)

                if let plainText = article.plainTextDescription ?? article.articleDescription?.htmlToPlainText {
                    Text(plainText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                HStack {
                    Text(article.publishedDate, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.tertiary)

                    if article.isRedditPost {
                        if let author = article.author {
                            Text("•")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                            Text(author)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    } else if let feedTitle = article.feed?.title {
                        Text("•")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        Text(feedTitle)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }

                    Spacer()

                    // Status indicators
                    if article.hasPodcastAudio {
                        Image(systemName: "waveform")
                            .font(.caption)
                            .foregroundStyle(Color.accentColor)
                    } else if article.hasMinimalContent && !article.isRedditPost {
                        Image(systemName: "arrow.up.forward.square")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    if article.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.caption)
                            .foregroundStyle(.yellow)
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

    // Maximum width for comfortable reading (Apple HIG recommendation)
    private let maxReadingWidth: CGFloat = 700

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
                HStack {
                    Spacer(minLength: 0)
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
                    .frame(maxWidth: maxReadingWidth)
                    Spacer(minLength: 0)
                }
            }
        }
        .onAppear {
            logger.info("📖 ArticleDetailColumn appeared: \(article.title) (Reddit: \(article.isRedditPost))")
            // Mark as read when displayed
            if !article.isRead {
                article.isRead = true
                try? modelContext.save()
            }
        }
        // Keyboard navigation: j/k for next/previous article
        .background {
            Group {
                Button("") {
                    if let prev = previousArticle {
                        selectedArticle = prev
                    }
                }
                .keyboardShortcut("k", modifiers: [])

                Button("") {
                    if let next = nextArticle {
                        selectedArticle = next
                    }
                }
                .keyboardShortcut("j", modifiers: [])
            }
            .opacity(0)
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

#Preview {
    ContentView()
        .modelContainer(for: Feed.self, inMemory: true)
}
