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

    private var categories: [String] {
        let feedCategories = Set(allArticles.compactMap { $0.feed?.category })
        return ["all"] + feedCategories.sorted()
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

        // Show only articles from the last 7 days
        let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        articles = articles.filter { $0.publishedDate >= sevenDaysAgo }

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
                    if hideReadArticles && !allArticles.isEmpty {
                        ContentUnavailableView(
                            "No Unread Articles",
                            systemImage: "checkmark.circle",
                            description: Text("You're all caught up! Tap the eye icon to show read articles.")
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
                        ForEach(filteredArticles) { article in
                            NavigationLink(destination: ArticleDetailSimple(article: article)) {
                                ArticleRowView(article: article)
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
                }
            }
            .navigationTitle("Today")
            .searchable(text: $searchText, prompt: "Search articles")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            hideReadArticles = false
                        } label: {
                            Label("Show All", systemImage: hideReadArticles ? "circle" : "checkmark.circle")
                        }

                        Button {
                            hideReadArticles = true
                        } label: {
                            Label("Unread Only", systemImage: hideReadArticles ? "checkmark.circle" : "circle")
                        }

                        Divider()

                        let unreadCount = allArticles.filter { !$0.isRead }.count
                        Text("\(unreadCount) unread articles")
                            .foregroundStyle(.secondary)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: hideReadArticles ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                            if hideReadArticles {
                                let unreadCount = allArticles.filter { !$0.isRead }.count
                                if unreadCount > 0 {
                                    Text("\(unreadCount)")
                                        .font(.caption2)
                                        .fontWeight(.semibold)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func toggleRead(_ article: Article) {
        article.isRead.toggle()
        try? modelContext.save()
    }

    private func toggleFavorite(_ article: Article) {
        article.isFavorite.toggle()
        try? modelContext.save()
    }
}

struct ArticleRowView: View {
    let article: Article

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    if let feedTitle = article.feed?.title {
                        Text(feedTitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(article.publishedDate, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Text(article.title)
                    .font(.headline)
                    .fontWeight(article.isRead ? .regular : .semibold)

                if let description = article.articleDescription {
                    Text(description.htmlToAttributedString)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                HStack {
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
