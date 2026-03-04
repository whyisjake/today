import Foundation
import SwiftData
import Combine
import os

private let logger = Logger(subsystem: "com.today", category: "OPMLSubscriptionManager")

/// Manages OPML subscriptions — periodically fetches remote OPML files
/// and syncs the local feed list to match.
@MainActor
class OPMLSubscriptionManager: ObservableObject {
    let modelContext: ModelContext
    private let feedManager: FeedManager

    @Published var isSyncing = false
    @Published var syncError: String?

    init(modelContext: ModelContext, feedManager: FeedManager) {
        self.modelContext = modelContext
        self.feedManager = feedManager
    }

    // MARK: - Add Subscription

    /// Subscribe to a remote OPML URL. Fetches the OPML immediately and adds all feeds.
    func addSubscription(url: String, title: String? = nil, defaultCategory: String = "General") async throws -> OPMLSubscription {
        guard let opmlURL = URL(string: url) else {
            throw NSError(domain: "OPMLSubscription", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Invalid OPML URL"
            ])
        }

        // Prevent duplicate subscriptions for the same OPML URL
        let existingSubscriptions = try modelContext.fetch(
            FetchDescriptor<OPMLSubscription>(
                predicate: #Predicate<OPMLSubscription> { $0.url == url }
            )
        )
        if !existingSubscriptions.isEmpty {
            throw NSError(domain: "OPMLSubscription", code: -2, userInfo: [
                NSLocalizedDescriptionKey: "A subscription for this OPML URL already exists"
            ])
        }

        // Fetch the OPML (prefer XML/OPML content)
        let response = try await ConditionalHTTPClient.conditionalFetch(
            url: opmlURL,
            lastModified: nil,
            etag: nil,
            additionalHeaders: ["Accept": "application/xml, text/xml, text/x-opml, */*;q=0.1"]
        )

        guard let data = response.data else {
            throw NSError(domain: "OPMLSubscription", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "No data returned from OPML URL"
            ])
        }

        // Parse the OPML
        let parser = OPMLParser()
        let parsedFeeds = try parser.parse(data: data)

        // Create the subscription
        let subscriptionTitle = title ?? parser.opmlTitle ?? url
        let subscription = OPMLSubscription(
            title: subscriptionTitle,
            url: url,
            defaultCategory: defaultCategory
        )
        subscription.lastFetched = Date()
        subscription.httpLastModified = response.lastModified
        subscription.httpEtag = response.etag

        modelContext.insert(subscription)
        try modelContext.save()

        // Add feeds from the OPML
        var addedCount = 0
        for parsedFeed in parsedFeeds {
            let category = parsedFeed.category.lowercased() == "general" ? defaultCategory : parsedFeed.category

            // Check if feed already exists (by stored URL or original source URL)
            let feedURL = parsedFeed.url
            let existingByURL = try modelContext.fetch(
                FetchDescriptor<Feed>(predicate: #Predicate<Feed> { $0.url == feedURL })
            )
            let existingBySource = try modelContext.fetch(
                FetchDescriptor<Feed>(predicate: #Predicate<Feed> { $0.sourceURL == feedURL })
            )
            let existing = existingByURL.isEmpty ? existingBySource : existingByURL

            if existing.isEmpty {
                do {
                    let feed = try await feedManager.addFeed(url: parsedFeed.url, category: category)
                    feed.opmlSubscriptionURL = url
                    addedCount += 1
                } catch {
                    logger.warning("Failed to add feed \(parsedFeed.url): \(error.localizedDescription)")
                }
            } else if let existingFeed = existing.first, existingFeed.opmlSubscriptionURL == nil {
                // Feed exists but was user-added — don't claim it, just skip
                logger.info("Feed \(parsedFeed.url) already exists (user-added), skipping")
            }
        }

        try modelContext.save()
        logger.info("Added OPML subscription '\(subscriptionTitle)' with \(addedCount) new feeds")
        return subscription
    }

    // MARK: - Sync Subscription

    /// Sync a single OPML subscription — fetch the OPML, diff, add/deactivate feeds.
    func syncSubscription(_ subscription: OPMLSubscription) async throws {
        guard subscription.isActive else { return }

        guard let opmlURL = URL(string: subscription.url) else {
            logger.error("Invalid URL for subscription: \(subscription.url)")
            return
        }

        let response = try await ConditionalHTTPClient.conditionalFetch(
            url: opmlURL,
            lastModified: subscription.httpLastModified,
            etag: subscription.httpEtag,
            additionalHeaders: ["Accept": "application/xml, text/xml, text/x-opml, */*;q=0.1"]
        )

        // Update cache headers
        subscription.httpLastModified = response.lastModified
        subscription.httpEtag = response.etag
        subscription.lastFetched = Date()

        // If not modified, nothing to do
        guard response.wasModified, let data = response.data else {
            logger.info("OPML subscription '\(subscription.title)' not modified (304)")
            try modelContext.save()
            return
        }

        // Parse the updated OPML
        let parser = OPMLParser()
        let parsedFeeds = try parser.parse(data: data)

        // Update title if the OPML has one
        if let opmlTitle = parser.opmlTitle, !opmlTitle.isEmpty {
            subscription.title = opmlTitle
        }

        let remoteURLs = Set(parsedFeeds.map { $0.url })

        // Find feeds managed by this subscription
        let subscriptionURL = subscription.url
        let managedFeeds = try modelContext.fetch(
            FetchDescriptor<Feed>(predicate: #Predicate<Feed> { $0.opmlSubscriptionURL == subscriptionURL })
        )
        // Use sourceURL (original OPML URL) for matching, falling back to stored url
        let localSourceURLs = Set(managedFeeds.map { $0.sourceURL ?? $0.url })

        // Add new feeds (in remote but not in managed set)
        let newURLs = remoteURLs.subtracting(localSourceURLs)
        var addedCount = 0
        for parsedFeed in parsedFeeds where newURLs.contains(parsedFeed.url) {
            let category = parsedFeed.category.lowercased() == "general" ? subscription.defaultCategory : parsedFeed.category

            // Check if feed already exists (by stored URL or original source URL)
            let feedURL = parsedFeed.url
            let existingByURL = try modelContext.fetch(
                FetchDescriptor<Feed>(predicate: #Predicate<Feed> { $0.url == feedURL })
            )
            let existingBySource = try modelContext.fetch(
                FetchDescriptor<Feed>(predicate: #Predicate<Feed> { $0.sourceURL == feedURL })
            )

            if existingByURL.isEmpty && existingBySource.isEmpty {
                do {
                    let feed = try await feedManager.addFeed(url: parsedFeed.url, category: category)
                    feed.opmlSubscriptionURL = subscription.url
                    addedCount += 1
                } catch {
                    logger.warning("Failed to add feed \(parsedFeed.url): \(error.localizedDescription)")
                }
            }
            // If feed exists but isn't managed by this subscription, skip it
            // (don't create a duplicate, and don't claim user-added feeds)
        }

        // Deactivate removed feeds (in local/managed but not in remote OPML)
        let removedSourceURLs = localSourceURLs.subtracting(remoteURLs)
        var deactivatedCount = 0
        for feed in managedFeeds where removedSourceURLs.contains(feed.sourceURL ?? feed.url) {
            feed.isActive = false
            deactivatedCount += 1
        }

        try modelContext.save()
        logger.info("Synced OPML '\(subscription.title)': +\(addedCount) added, -\(deactivatedCount) deactivated")
    }

    // MARK: - Sync All

    /// Sync all active OPML subscriptions. Called during background sync.
    func syncAllSubscriptions() async {
        isSyncing = true
        syncError = nil

        do {
            let subscriptions = try modelContext.fetch(
                FetchDescriptor<OPMLSubscription>(predicate: #Predicate<OPMLSubscription> { $0.isActive == true })
            )

            guard !subscriptions.isEmpty else {
                isSyncing = false
                return
            }

            logger.info("Syncing \(subscriptions.count) OPML subscription(s)")

            for subscription in subscriptions {
                do {
                    try await syncSubscription(subscription)
                } catch {
                    logger.error("Failed to sync subscription '\(subscription.title)': \(error.localizedDescription)")
                }
            }
        } catch {
            syncError = error.localizedDescription
            logger.error("Failed to fetch subscriptions: \(error.localizedDescription)")
        }

        isSyncing = false
    }

    // MARK: - Remove Subscription

    /// Remove a subscription. Optionally removes all feeds it manages.
    func removeSubscription(_ subscription: OPMLSubscription, removeFeeds: Bool) throws {
        if removeFeeds {
            let subscriptionURL = subscription.url
            let managedFeeds = try modelContext.fetch(
                FetchDescriptor<Feed>(predicate: #Predicate<Feed> { $0.opmlSubscriptionURL == subscriptionURL })
            )
            for feed in managedFeeds {
                modelContext.delete(feed)
            }
        } else {
            // Unlink feeds from this subscription so they become user-owned
            let subscriptionURL = subscription.url
            let managedFeeds = try modelContext.fetch(
                FetchDescriptor<Feed>(predicate: #Predicate<Feed> { $0.opmlSubscriptionURL == subscriptionURL })
            )
            for feed in managedFeeds {
                feed.opmlSubscriptionURL = nil
            }
        }

        modelContext.delete(subscription)
        try modelContext.save()
        logger.info("Removed OPML subscription '\(subscription.title)' (removeFeeds: \(removeFeeds))")
    }
}
