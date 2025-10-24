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
    @Query(sort: \Article.publishedDate, order: .reverse) private var allArticles: [Article]

    @State private var selectedCategory: String = "all"
    @State private var searchText = ""
    @State private var hideReadArticles = false
    @State private var showFavoritesOnly = false
    @State private var selectedArticleID: PersistentIdentifier?
    @State private var isRefreshing = false
    @State private var showMarkAllReadConfirmation = false

    // Cache expensive computations
    private var categories: [String] {
        let feedCategories = Set(allArticles.compactMap { $0.feed?.category })
        return ["all"] + feedCategories.sorted()
    }

    private var unreadCount: Int {
        allArticles.lazy.filter { !$0.isRead }.count
    }

    private var favoritesCount: Int {
        allArticles.lazy.filter { $0.isFavorite }.count
    }

    private var activeFilterCount: Int {
        showFavoritesOnly ? favoritesCount : unreadCount
    }

    private var filteredArticles: [Article] {
        var articles = allArticles

        // Filter by category
        if selectedCategory != "all" {
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
                                    Text(category.capitalized)
                                        .font(.subheadline)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 8)
                                        .background(
                                            selectedCategory == category ?
                                            Color.blue : Color.gray.opacity(0.2)
                                        )
                                        .foregroundStyle(
                                            selectedCategory == category ?
                                            .white : .primary
                                        )
                                        .cornerRadius(20)
                                }
                            }
                        }
                        .padding()
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
                        ForEach(filteredArticles, id: \.id) { article in
                            Button {
                                Task { @MainActor in
                                    try? await Task.sleep(nanoseconds: 50_000_000)
                                    selectedArticleID = article.persistentModelID
                                }
                            } label: {
                                HStack {
                                    ArticleRowView(article: article)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                            .id(article.id)
                            .swipeActions(edge: .leading) {
                                Button {
                                    toggleRead(article)
                                } label: {
                                    Label(
                                        article.isRead ? "Unread" : "Read",
                                        systemImage: article.isRead ? "envelope.badge" : "envelope.open"
                                    )
                                }
                                .tint(.blue)
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
                    }
                    .listStyle(.plain)
                    .refreshable {
                        await refreshFeeds()
                    }
                }
            }
            .navigationTitle("Today")
            .searchable(text: $searchText, prompt: "Search articles")
            .navigationDestination(item: $selectedArticleID) { articleID in
                if let article = modelContext.model(for: articleID) as? Article {
                    // Find next article in filtered list
                    if let currentIndex = filteredArticles.firstIndex(where: { $0.persistentModelID == articleID }) {
                        let nextIndex = currentIndex + 1
                        let nextArticleID = nextIndex < filteredArticles.count ? filteredArticles[nextIndex].persistentModelID : nil
                        ArticleDetailSimple(article: article, nextArticleID: nextArticleID, onNavigateToNext: { nextID in
                            Task { @MainActor in
                                try? await Task.sleep(nanoseconds: 50_000_000)
                                selectedArticleID = nextID
                            }
                        })
                    } else {
                        ArticleDetailSimple(article: article, nextArticleID: nil, onNavigateToNext: { _ in })
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

                        Text("\(unreadCount) unread • \(favoritesCount) favorites")
                            .foregroundStyle(.secondary)
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
                selectedCategory == "all"
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

        // Filter by category if not "all"
        if selectedCategory != "all" {
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
        isRefreshing = true
        let feedManager = FeedManager(modelContext: modelContext)
        await feedManager.syncAllFeeds()
        isRefreshing = false
    }
}

struct ArticleRowView: View {
    let article: Article

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(article.title)
                    .font(.headline)
                    .fontWeight(article.isRead ? .regular : .semibold)

                // Use cached plain text if available, otherwise compute on-the-fly
                if let plainText = article.plainTextDescription ?? article.articleDescription?.htmlToPlainText {
                    Text(plainText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                HStack {
                    Text(article.publishedDate, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    if let feedTitle = article.feed?.title {
                        Text("•")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)

                        Text(feedTitle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                    if article.isRead {
                        Image(systemName: "envelope.open.fill")
                            .font(.caption2)
                            .foregroundStyle(.blue)
                    }
                    if article.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.caption2)
                            .foregroundStyle(.yellow)
                    }
                }
            }

            // Display article image if available
            if let imageUrl = article.imageUrl, let url = URL(string: imageUrl) {
                AsyncImage(url: url) { phase in
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
        .padding(.vertical, 4)
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
                    if let url = URL(string: article.link) {
                        openURL(url)
                    }
                } label: {
                    Label("Read Full Article", systemImage: "safari")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
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
