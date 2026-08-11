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

            // Match on the canonical form as well as the URL as listed, for the same reason
            // syncSubscription does — a feed stored earlier is stored canonically.
            let feedURL = FeedURLNormalizer.canonical(parsedFeed.url)
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

    // MARK: - Off-main stages

    /// Sendable snapshot of a subscription, so the fetch/parse stage needs no model access.
    struct SubscriptionSnapshot: Sendable {
        let url: String
        let title: String
        let defaultCategory: String
        let httpLastModified: String?
        let httpEtag: String?
    }

    /// Result of the off-main fetch and parse.
    struct FetchedOPML: Sendable {
        let wasModified: Bool
        let feeds: [OPMLParser.ParsedFeed]
        let opmlTitle: String?
        let lastModified: String?
        let etag: String?
    }

    /// Sendable snapshot of a feed this subscription manages.
    struct ManagedFeedSnapshot: Sendable {
        let id: PersistentIdentifier
        let url: String
        let sourceURL: String?
        /// Needed so reactivation targets only feeds that are actually inactive, which keeps a
        /// settled subscription diffing to nothing.
        var isActive: Bool = true

        /// Matching uses the original OPML URL when present, since `url` may have been
        /// rewritten by a redirect.
        var matchURL: String { sourceURL ?? url }
    }

    /// What a sync should change. Computed without touching the model graph so it can be
    /// unit-tested directly — this code has produced duplicate feeds before, which is why
    /// `DatabaseMigration.deduplicateFeeds` exists.
    struct OPMLDiff: Sendable, Equatable {
        var feedsToAdd: [OPMLParser.ParsedFeed] = []
        var feedIDsToDeactivate: [PersistentIdentifier] = []
        /// Managed feeds still present in the remote OPML. They are reactivated in case an
        /// earlier sync deactivated them — see `FeedURLNormalizer` for how that used to happen
        /// on every sync, and why those feeds could never recover on their own.
        var feedIDsToReactivate: [PersistentIdentifier] = []
        var newTitle: String?
    }

    /// Fetch and parse an OPML document. Network and XML parsing, entirely off the main
    /// thread — `@concurrent` rather than plain `nonisolated` because this module builds with
    /// SWIFT_APPROACHABLE_CONCURRENCY, under which a `nonisolated async` function would run
    /// on the caller's executor (here, the main actor).
    @concurrent nonisolated static func fetchAndParse(
        _ snapshot: SubscriptionSnapshot
    ) async throws -> FetchedOPML {
        #if DEBUG
        assert(!Thread.isMainThread, "OPML fetch/parse must not run on the main thread")
        #endif

        guard let opmlURL = URL(string: snapshot.url) else {
            throw NSError(domain: "OPMLSubscription", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Invalid OPML URL"
            ])
        }

        let response = try await ConditionalHTTPClient.conditionalFetch(
            url: opmlURL,
            lastModified: snapshot.httpLastModified,
            etag: snapshot.httpEtag,
            additionalHeaders: ["Accept": "application/xml, text/xml, text/x-opml, */*;q=0.1"]
        )

        guard response.wasModified, let data = response.data else {
            return FetchedOPML(
                wasModified: false, feeds: [], opmlTitle: nil,
                lastModified: response.lastModified, etag: response.etag
            )
        }

        let parser = OPMLParser()
        let parsedFeeds = try parser.parse(data: data)

        return FetchedOPML(
            wasModified: true,
            feeds: parsedFeeds,
            opmlTitle: parser.opmlTitle,
            lastModified: response.lastModified,
            etag: response.etag
        )
    }

    /// Pure diff: what to add, what to deactivate, whether the title changed.
    ///
    /// Deliberately identical in behaviour to the previous inline logic — matching on
    /// `sourceURL ?? url`, resolving a "general" category to the subscription default, and
    /// leaving feeds that exist but are not managed by this subscription alone. Whether a
    /// candidate already exists globally still needs a database lookup and stays in `apply`.
    nonisolated static func computeDiff(
        fetched: FetchedOPML,
        managed: [ManagedFeedSnapshot],
        defaultCategory: String
    ) -> OPMLDiff {
        var diff = OPMLDiff()

        if let opmlTitle = fetched.opmlTitle, !opmlTitle.isEmpty {
            diff.newTitle = opmlTitle
        }

        // Compare canonical forms on both sides. The remote document lists URLs however the
        // publisher wrote them, while feeds are stored in the form addFeed normalises to — so
        // comparing them raw made an http-listed feed perpetually look both missing and new.
        let remoteURLs = Set(fetched.feeds.map { FeedURLNormalizer.canonical($0.url) })
        let localMatchURLs = Set(managed.map { FeedURLNormalizer.canonical($0.matchURL) })

        let newURLs = remoteURLs.subtracting(localMatchURLs)
        diff.feedsToAdd = fetched.feeds
            .filter { newURLs.contains(FeedURLNormalizer.canonical($0.url)) }
            .map { parsed in
                let category = parsed.category.lowercased() == "general"
                    ? defaultCategory
                    : parsed.category
                return OPMLParser.ParsedFeed(url: parsed.url, title: parsed.title, category: category)
            }

        let removedURLs = localMatchURLs.subtracting(remoteURLs)
        diff.feedIDsToDeactivate = managed
            .filter { removedURLs.contains(FeedURLNormalizer.canonical($0.matchURL)) }
            .map(\.id)

        // Everything still listed remotely is reactivated. Without this, feeds already
        // deactivated by the churn bug would stay deactivated forever, since re-adding them is
        // a no-op: addFeed finds the existing feed and returns it without touching isActive.
        diff.feedIDsToReactivate = managed
            .filter { !$0.isActive && !removedURLs.contains(FeedURLNormalizer.canonical($0.matchURL)) }
            .map(\.id)

        return diff
    }

    // MARK: - Sync Subscription

    /// Sync a single OPML subscription — fetch the OPML, diff, add/deactivate feeds.
    ///
    /// Stays on the main actor because it owns `@Published` state and `mainContext`, but the
    /// expensive stages no longer do: fetch and XML parse run on `@concurrent` statics, and
    /// the managed-feed snapshot and deactivations run on a background `ModelContext`.
    ///
    /// Adding a *new* feed still hops to the main actor via `FeedManager.addFeed`, which owns
    /// URL normalisation, Reddit conversion, redirect handling and the initial article fetch.
    /// That path only runs when the remote OPML actually gained a feed; the per-cycle cost —
    /// the fetch and parse that happen on every sync — is now entirely off-main.
    func syncSubscription(_ subscription: OPMLSubscription) async throws {
        guard subscription.isActive else { return }

        let snapshot = SubscriptionSnapshot(
            url: subscription.url,
            title: subscription.title,
            defaultCategory: subscription.defaultCategory,
            httpLastModified: subscription.httpLastModified,
            httpEtag: subscription.httpEtag
        )

        let fetched: FetchedOPML
        do {
            fetched = try await Self.fetchAndParse(snapshot)
        } catch {
            logger.error("OPML fetch failed for \(snapshot.url): \(error.localizedDescription)")
            throw error
        }

        // Cache headers advance whether or not the document changed.
        subscription.httpLastModified = fetched.lastModified
        subscription.httpEtag = fetched.etag
        subscription.lastFetched = Date()

        guard fetched.wasModified else {
            logger.info("OPML subscription '\(snapshot.title)' not modified (304)")
            try modelContext.save()
            return
        }

        let container = modelContext.container
        let managed = await Self.managedFeedSnapshots(
            subscriptionURL: snapshot.url, container: container
        )
        let diff = Self.computeDiff(
            fetched: fetched, managed: managed, defaultCategory: snapshot.defaultCategory
        )

        if let newTitle = diff.newTitle {
            subscription.title = newTitle
        }

        // Activation changes run off-main; they need no main-actor state.
        let deactivatedCount = await Self.setFeedsActive(
            false, ids: diff.feedIDsToDeactivate, container: container
        )
        let reactivatedCount = await Self.setFeedsActive(
            true, ids: diff.feedIDsToReactivate, container: container
        )

        // New feeds go through FeedManager on the main actor — see the note above.
        var addedCount = 0
        for parsedFeed in diff.feedsToAdd {
            // The existence check and the insert must stay adjacent: a concurrent sync
            // interleaving between them is how duplicate feeds were created before.
            guard !(try feedAlreadyExists(url: parsedFeed.url)) else { continue }
            do {
                let feed = try await feedManager.addFeed(url: parsedFeed.url, category: parsedFeed.category)
                feed.opmlSubscriptionURL = snapshot.url
                addedCount += 1
            } catch {
                logger.warning("Failed to add feed \(parsedFeed.url): \(error.localizedDescription)")
            }
        }

        try modelContext.save()
        logger.info("Synced OPML '\(subscription.title)': +\(addedCount) added, -\(deactivatedCount) deactivated, \(reactivatedCount) reactivated")
    }

    /// True when a feed with this URL already exists, by stored URL or original source URL.
    /// Matches the previous behaviour, including that a user-added feed is left unclaimed.
    private func feedAlreadyExists(url: String) throws -> Bool {
        // Check the canonical form as well as the URL as listed: a feed added earlier is stored
        // canonically, so checking only the raw OPML URL misses it and pointlessly re-enters
        // addFeed.
        let candidates = Set([url, FeedURLNormalizer.canonical(url)])
        for candidate in candidates {
            let byURL = try modelContext.fetch(
                FetchDescriptor<Feed>(predicate: #Predicate<Feed> { $0.url == candidate })
            )
            if !byURL.isEmpty { return true }
            let bySource = try modelContext.fetch(
                FetchDescriptor<Feed>(predicate: #Predicate<Feed> { $0.sourceURL == candidate })
            )
            if !bySource.isEmpty { return true }
        }
        return false
    }

    /// Snapshot this subscription's managed feeds on a background context.
    @concurrent nonisolated static func managedFeedSnapshots(
        subscriptionURL: String,
        container: ModelContainer
    ) async -> [ManagedFeedSnapshot] {
        let context = ModelContext(container)
        let feeds = (try? context.fetch(
            FetchDescriptor<Feed>(predicate: #Predicate<Feed> { $0.opmlSubscriptionURL == subscriptionURL })
        )) ?? []
        return feeds.map {
            ManagedFeedSnapshot(
                id: $0.persistentModelID,
                url: $0.url,
                sourceURL: $0.sourceURL,
                isActive: $0.isActive
            )
        }
    }

    /// Set `isActive` on feeds by identifier, on a background context.
    /// - Returns: the number of feeds whose value actually changed.
    @concurrent nonisolated static func setFeedsActive(
        _ isActive: Bool,
        ids: [PersistentIdentifier],
        container: ModelContainer
    ) async -> Int {
        guard !ids.isEmpty else { return 0 }
        let context = ModelContext(container)
        var count = 0
        for id in ids {
            let matches = (try? context.fetch(FetchDescriptor<Feed>(
                predicate: #Predicate<Feed> { $0.persistentModelID == id }
            ))) ?? []
            guard let feed = matches.first, feed.isActive != isActive else { continue }
            feed.isActive = isActive
            count += 1
        }
        try? context.save()
        return count
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
