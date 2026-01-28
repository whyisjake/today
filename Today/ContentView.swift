//
//  ContentView.swift
//  Today
//
//  Main view with adaptive layout for iPhone (TabView) and iPad (NavigationSplitView)
//

import SwiftUI
import SwiftData

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

// MARK: - Sidebar Layout (iPad/Mac)
struct SidebarContentView: View {
    let modelContext: ModelContext
    @Query(sort: \Feed.title) private var feeds: [Feed]
    @AppStorage("showAltCategory") private var showAltFeeds = false
    @State private var selectedSidebarItem: SidebarItem? = .today
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
            NavigationSplitView {
                // Sidebar
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
            } detail: {
                // Detail view based on selection
                if let selected = selectedSidebarItem {
                    switch selected {
                    case .today:
                        TodayView()
                    case .feeds:
                        FeedListView(modelContext: modelContext)
                    case .feed(let feedId):
                        // Find the feed by ID
                        if let feed = feeds.first(where: { $0.id == feedId }) {
                            FeedDetailView(feed: feed)
                        } else {
                            // Feed was deleted - show helpful message
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
                    TodayView()
                }
            }
            .padding(.bottom, totalMiniPlayerHeight)
            
            // Global mini audio player
            MiniAudioPlayer()
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
