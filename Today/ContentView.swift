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
    @ObservedObject private var categoryManager = CategoryManager.shared
    @AppStorage("showAltCategory") private var showAltFeeds = false
    @State private var selectedSidebarItem: SidebarItem? = .today
    @State private var selectedFeed: Feed?
    @StateObject private var audioPlayer = ArticleAudioPlayer.shared
    @StateObject private var podcastPlayer = PodcastAudioPlayer.shared
    
    enum SidebarItem: Hashable {
        case today
        case category(String)
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
    
    // Group feeds by category
    private var feedsByCategory: [(category: String, feeds: [Feed])] {
        let grouped = Dictionary(grouping: visibleFeeds) { $0.category }
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
                    }
                    
                    // Feeds grouped by category
                    ForEach(feedsByCategory, id: \.category) { categoryGroup in
                        Section(header: Text(categoryGroup.category.capitalized)) {
                            ForEach(categoryGroup.feeds, id: \.id) { feed in
                                NavigationLink(value: SidebarItem.category(feed.id.hashValue.description)) {
                                    Label(feed.title, systemImage: "doc.text")
                                }
                                .contextMenu {
                                    Button {
                                        selectedFeed = feed
                                    } label: {
                                        Label("View Feed", systemImage: "eye")
                                    }
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
                    case .category(let categoryId):
                        // Find the feed by matching hash
                        if let feed = visibleFeeds.first(where: { $0.id.hashValue.description == categoryId }) {
                            FeedDetailView(feed: feed)
                        } else {
                            TodayView()
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
        .sheet(item: $selectedFeed) { feed in
            NavigationStack {
                FeedListView(modelContext: modelContext)
                    .navigationTitle("Feeds")
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
    }
}

// MARK: - Feed Detail View
struct FeedDetailView: View {
    let feed: Feed
    @Query private var allArticles: [Article]
    @State private var searchText = ""
    
    init(feed: Feed) {
        self.feed = feed
        // Query all articles - we'll filter in the computed property
        _allArticles = Query(sort: \Article.publishedDate, order: .reverse)
    }
    
    private var articles: [Article] {
        allArticles.filter { article in
            article.feed?.id == feed.id &&
            (searchText.isEmpty || 
             article.title.localizedCaseInsensitiveContains(searchText) ||
             (article.articleDescription?.localizedCaseInsensitiveContains(searchText) ?? false))
        }
    }
    
    var body: some View {
        List(articles) { article in
            NavigationLink {
                ArticleDetailSimple(
                    article: article,
                    previousArticleID: nil,
                    nextArticleID: nil,
                    onNavigateToPrevious: { _ in },
                    onNavigateToNext: { _ in }
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
                    if let date = article.publishedDate {
                        Text(date, style: .relative)
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
