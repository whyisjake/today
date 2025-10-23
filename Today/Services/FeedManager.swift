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
        // Fetch the feed to validate and get metadata
        let (feedTitle, feedDescription, _) = try await RSSFeedService.shared.fetchFeed(url: url)

        let feed = Feed(
            title: feedTitle.isEmpty ? url : feedTitle,
            url: url,
            feedDescription: feedDescription.isEmpty ? nil : feedDescription,
            category: category
        )

        modelContext.insert(feed)
        try modelContext.save()

        // Fetch initial articles
        try await syncFeed(feed)

        return feed
    }

    /// Sync a specific feed
    func syncFeed(_ feed: Feed) async throws {
        let (_, _, parsedArticles) = try await RSSFeedService.shared.fetchFeed(url: feed.url)

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
                    feed: feed
                )

                modelContext.insert(article)
            }
        }

        feed.lastFetched = Date()
        try modelContext.save()
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
