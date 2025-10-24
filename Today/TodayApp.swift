//
//  TodayApp.swift
//  Today
//
//  Created by Jake Spurlock on 10/22/25.
//

import SwiftUI
import SwiftData

@main
struct TodayApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Feed.self,
            Article.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    init() {
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
                }
        }
        .modelContainer(sharedModelContainer)
    }

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
            ("Pearls Before Swine", "https://www.gocomics.com/rss/pearlsbeforeswine", "comics"),
            ("TechCrunch", "https://techcrunch.com/feed/", "technology"),
            ("The Verge", "https://www.theverge.com/rss/index.xml", "technology"),
            ("Hacker News", "https://news.ycombinator.com/rss", "technology"),
            ("Ars Technica", "https://feeds.arstechnica.com/arstechnica/index", "technology"),
            ("Daring Fireball", "https://daringfireball.net/feeds/main", "technology"),
            ("The New York Times", "https://rss.nytimes.com/services/xml/rss/nyt/Technology.xml", "news"),
            ("BBC News", "http://feeds.bbci.co.uk/news/rss.xml", "news"),
            ("NPR", "https://feeds.npr.org/1001/rss.xml", "news"),
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
