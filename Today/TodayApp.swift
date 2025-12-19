//
//  TodayApp.swift
//  Today
//
//  Created by Jake Spurlock on 10/22/25.
//

import SwiftUI
import SwiftData
import AVFoundation

@main
struct TodayApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Feed.self,
            Article.self,
            PodcastDownload.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    init() {
        // Configure audio session to mix with other audio (music, podcasts, etc.)
        // This allows animated GIFs and videos to play without interrupting user's audio
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Failed to set audio session category: \(error)")
        }

        // Register background tasks
        BackgroundSyncManager.shared.registerBackgroundTasks()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    // Schedule background sync when app launches
                    BackgroundSyncManager.shared.enableBackgroundFetch()

                    // Add default feeds on first launch
                    addDefaultFeedsIfNeeded()

                    // Run database migrations
                    Task {
                        await DatabaseMigration.shared.runMigrations(modelContext: sharedModelContainer.mainContext)
                    }

                    // Check if we need to sync on launch (content older than 2 hours)
                    checkAndSyncIfNeeded()
                }
        }
        .modelContainer(sharedModelContainer)
    }

    @MainActor
    private func checkAndSyncIfNeeded() {
        // Check if a sync is already in progress before proceeding
        guard !FeedManager.isSyncInProgress() else {
            print("⏭️ Sync already in progress, skipping launch sync check")
            return
        }
        
        if FeedManager.needsSync() {
            let lastSync = FeedManager.getLastSyncDate()
            if let lastSync = lastSync {
                let hoursSince = Date().timeIntervalSince(lastSync) / 3600
                print("⚠️ Content is stale (last sync: \(String(format: "%.1f", hoursSince))h ago). Triggering sync...")
            } else {
                print("⚠️ No previous sync detected. Triggering initial sync...")
            }

            Task {
                let feedManager = FeedManager(modelContext: sharedModelContainer.mainContext)
                await feedManager.syncAllFeeds()
            }
        } else {
            if let lastSync = FeedManager.getLastSyncDate() {
                let minutesSince = Date().timeIntervalSince(lastSync) / 60
                print("✅ Content is fresh (last sync: \(String(format: "%.0f", minutesSince))m ago). No sync needed.")
            }
        }
    }

    @MainActor
    private func addDefaultFeedsIfNeeded() {
        let context = sharedModelContainer.mainContext

        // Check if any feeds already exist
        let fetchDescriptor = FetchDescriptor<Feed>()
        let existingFeeds = try? context.fetch(fetchDescriptor)

        guard existingFeeds?.isEmpty ?? true else {
            return // Feeds already exist, don't add defaults
        }

        // Default feeds to add
        let defaultFeeds = [
            ("Jake Spurlock", "https://jakespurlock.com/feed/", "personal"),
            ("Matt Mullenweg", "https://ma.tt/feed/", "personal"),
            ("XKCD", "https://xkcd.com/rss.xml", "comics"),
            ("TechCrunch", "https://techcrunch.com/feed/", "technology"),
            ("The Verge", "https://www.theverge.com/rss/index.xml", "technology"),
            ("Hacker News", "https://news.ycombinator.com/rss", "technology"),
            ("Ars Technica", "https://feeds.arstechnica.com/arstechnica/index", "technology"),
            ("Daring Fireball", "https://daringfireball.net/feeds/main", "technology"),
            ("The New York Times", "https://rss.nytimes.com/services/xml/rss/nyt/Technology.xml", "news"),
            ("BBC News", "http://feeds.bbci.co.uk/news/rss.xml", "news"),
            ("NPR", "https://feeds.npr.org/1001/rss.xml", "news"),
            ("r/politics", "https://www.reddit.com/r/politics/.json", "news"),
            ("r/TodayRSS", "https://www.reddit.com/r/TodayRSS/.json", "tech"),
            ("r/itookapicture", "https://www.reddit.com/r/itookapicture/.json", "social"),
            ("r/astrophotography", "https://www.reddit.com/r/astrophotography/.json", "social"),
        ]

        // Create Feed objects
        for (title, url, category) in defaultFeeds {
            let feed = Feed(title: title, url: url, category: category)
            context.insert(feed)
        }

        // Save the context
        try? context.save()

        // Sync the feeds to get initial articles
        Task {
            let feedManager = FeedManager(modelContext: context)
            await feedManager.syncAllFeeds()
        }
    }
}
