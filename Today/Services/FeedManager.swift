//
//  FeedManager.swift
//  Today
//
//  Service for managing RSS feed subscriptions and syncing
//

import Foundation
import SwiftData
import Combine

@MainActor
class FeedManager: ObservableObject {
    private let modelContext: ModelContext

    @Published var isSyncing = false
    @Published var lastSyncDate: Date?
    @Published var syncError: String?

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    /// Add a new RSS feed subscription
    func addFeed(url: String, category: String = "general") async throws -> Feed {
        // Convert Reddit URLs to JSON format
        let feedURL = convertRedditURLToJSON(url)

        // Fetch the feed to validate and get metadata
        let (feedTitle, feedDescription, _) = try await fetchFeed(url: feedURL)

        let feed = Feed(
            title: feedTitle.isEmpty ? feedURL : feedTitle,
            url: feedURL,
            feedDescription: feedDescription.isEmpty ? nil : feedDescription,
            category: category
        )

        modelContext.insert(feed)
        try modelContext.save()

        // Fetch initial articles
        try await syncFeed(feed)

        return feed
    }

    /// Convert Reddit URLs to JSON format
    /// Handles: reddit.com/r/subreddit.rss -> reddit.com/r/subreddit.json
    /// Also: reddit.com/r/subreddit -> reddit.com/r/subreddit.json
    private func convertRedditURLToJSON(_ url: String) -> String {
        var urlString = url

        // Convert .rss to .json
        if urlString.contains("reddit.com/r/") && urlString.hasSuffix(".rss") {
            urlString = urlString.replacingOccurrences(of: ".rss", with: ".json")
        }
        // Add .json if it's a subreddit URL without extension
        else if urlString.contains("reddit.com/r/") && !urlString.hasSuffix(".json") {
            // Remove trailing slash if present
            if urlString.hasSuffix("/") {
                urlString = String(urlString.dropLast())
            }
            urlString += ".json"
        }

        return urlString
    }

    /// Fetch feed using appropriate parser (RSS or Reddit JSON)
    private func fetchFeed(url: String) async throws -> (feedTitle: String, feedDescription: String, articles: [RSSParser.ParsedArticle]) {
        if isRedditJSON(url) {
            // Use Reddit JSON parser
            guard let feedURL = URL(string: url) else {
                throw FeedError.invalidURL
            }

            var request = URLRequest(url: feedURL)
            request.setValue("ios:com.today.app:v1.0 (by /u/TodayApp)", forHTTPHeaderField: "User-Agent")

            let (data, _) = try await URLSession.shared.data(for: request)

            let parser = RedditJSONParser()
            let (feedTitle, feedDescription, redditPosts) = try parser.parseSubredditFeed(data: data)

            // Convert Reddit posts to ParsedArticle format
            let articles = redditPosts.map { $0.toArticle() }

            return (feedTitle, feedDescription, articles)
        } else {
            // Use RSS parser
            return try await RSSFeedService.shared.fetchFeed(url: url)
        }
    }

    /// Check if URL is a Reddit JSON feed
    private func isRedditJSON(_ url: String) -> Bool {
        return url.contains("reddit.com") && url.hasSuffix(".json")
    }

    /// Sync a specific feed
    func syncFeed(_ feed: Feed) async throws {
        let (_, _, parsedArticles) = try await fetchFeed(url: feed.url)

        // Get existing article GUIDs to avoid duplicates
        let existingGUIDs = Set(feed.articles?.map { $0.guid } ?? [])

        // Add new articles
        for parsedArticle in parsedArticles {
            if !existingGUIDs.contains(parsedArticle.guid) {
                let article = Article(
                    title: parsedArticle.title,
                    link: parsedArticle.link,
                    articleDescription: parsedArticle.description,
                    content: parsedArticle.content,
                    contentEncoded: parsedArticle.contentEncoded,
                    imageUrl: parsedArticle.imageUrl,
                    publishedDate: parsedArticle.publishedDate ?? Date(),
                    author: parsedArticle.author,
                    guid: parsedArticle.guid,
                    feed: feed,
                    redditSubreddit: parsedArticle.redditSubreddit,
                    redditCommentsUrl: parsedArticle.redditCommentsUrl,
                    redditPostId: parsedArticle.redditPostId
                )

                modelContext.insert(article)
            }
        }

        feed.lastFetched = Date()
        try modelContext.save()
    }

    enum FeedError: LocalizedError {
        case invalidURL

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "Invalid feed URL"
            }
        }
    }

    /// Sync all active feeds
    func syncAllFeeds() async {
        isSyncing = true
        syncError = nil

        defer {
            isSyncing = false
            lastSyncDate = Date()
        }

        do {
            let descriptor = FetchDescriptor<Feed>(
                predicate: #Predicate<Feed> { $0.isActive }
            )
            let feeds = try modelContext.fetch(descriptor)

            for feed in feeds {
                do {
                    try await syncFeed(feed)
                } catch {
                    print("Error syncing feed \(feed.title): \(error.localizedDescription)")
                    // Continue with other feeds even if one fails
                }
            }
        } catch {
            syncError = error.localizedDescription
        }
    }

    /// Delete a feed and all its articles
    func deleteFeed(_ feed: Feed) throws {
        modelContext.delete(feed)
        try modelContext.save()
    }
}
