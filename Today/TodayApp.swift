//
//  TodayApp.swift
//  Today
//
//  Created by Jake Spurlock on 10/22/25.
//

import SwiftUI
import SwiftData
import AVFoundation

#if os(macOS)
import AppKit

// Notification names for text size changes
extension Notification.Name {
    static let increaseTextSize = Notification.Name("increaseTextSize")
    static let decreaseTextSize = Notification.Name("decreaseTextSize")
    static let resetTextSize = Notification.Name("resetTextSize")
    static let navigateToNextArticle = Notification.Name("navigateToNextArticle")
    static let navigateToPreviousArticle = Notification.Name("navigateToPreviousArticle")
    static let navigateToNextImage = Notification.Name("navigateToNextImage")
    static let navigateToPreviousImage = Notification.Name("navigateToPreviousImage")
    static let toggleArticleFavorite = Notification.Name("toggleArticleFavorite")
    static let toggleArticleRead = Notification.Name("toggleArticleRead")
    static let openArticleInBrowser = Notification.Name("openArticleInBrowser")
    static let shareArticle = Notification.Name("shareArticle")
    static let scrollPageDown = Notification.Name("scrollPageDown")
    static let articleScrolledToBottom = Notification.Name("articleScrolledToBottom")
    static let articleScrolledFromBottom = Notification.Name("articleScrolledFromBottom")
}

// Focused values for keyboard shortcuts
extension FocusedValues {
    struct SelectedArticleKey: FocusedValueKey {
        typealias Value = Binding<Article?>
    }
    
    var selectedArticle: Binding<Article?>? {
        get { self[SelectedArticleKey.self] }
        set { self[SelectedArticleKey.self] = newValue }
    }
}
#endif

@main
struct TodayApp: App {
    @AppStorage("accentColor") private var accentColor: AccentColorOption = .orange
    
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Feed.self,
            Article.self,
            OPMLSubscription.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    init() {
        let initInterval = Perf.begin(.appInit)
        defer { Perf.end(initInterval) }

        #if os(iOS)
        // Configure audio session to mix with other audio (music, podcasts, etc.)
        // This allows animated GIFs and videos to play without interrupting user's audio
        // Note: We only configure the category here, not activate the session.
        // The session will be activated when audio playback is needed (TTS or podcasts).
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default)
        } catch {
            print("Failed to set audio session category: \(error)")
        }

        // Register background tasks (nonisolated - safe to call from init)
        BackgroundSyncManager.shared.registerBackgroundTasks()
        #endif

        // Debug: delete all articles and reset sync state so the next launch behaves like a cold start.
        // Activate via the "-ResetArticlesOnLaunch" launch argument (see the "Today (Cold Launch)" scheme).
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ResetArticlesOnLaunch") {
            resetArticlesForTesting()
        }

        // Generate a realistically large store on demand, so read-path cost can be
        // measured without waiting weeks for one to accumulate naturally.
        // Usage: -SeedLargeStore [-SeedFeedCount 20] [-SeedArticlesPerFeed 500]
        if ProcessInfo.processInfo.arguments.contains("-SeedLargeStore") {
            seedLargeStoreForTesting()
        }

        // Force a sync on this launch without deleting anything.
        //
        // needsSync() gates on a 2-hour window, and the sync date cannot be cleared from
        // outside the app: the live CFPreferences value shadows the on-disk plist, so
        // `defaults write` from the host is silently ignored. Clearing it from in here is
        // the only reliable way to measure the sync path repeatedly.
        if ProcessInfo.processInfo.arguments.contains("-ForceSyncOnLaunch") {
            UserDefaults.standard.removeObject(forKey: "com.today.lastGlobalSyncDate")
            print("🔁 [Debug] Cleared sync date — this launch will sync")
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .tint(accentColor.color)
                .onAppear {
                    // Set the model container for background sync (must be on MainActor)
                    BackgroundSyncManager.shared.modelContainer = sharedModelContainer

                    // Schedule background sync when app launches
                    BackgroundSyncManager.shared.enableBackgroundFetch()

                    // Add default feeds on first launch (deferred so first frame renders first)
                    let container = sharedModelContainer
                    Task.detached(priority: .userInitiated) {
                        try? await Task.sleep(for: .milliseconds(100))
                        await addDefaultFeedsIfNeeded(container: container)
                    }

                    // Run database migrations on the main actor at low priority after UI is ready.
                    // @MainActor ensures mainContext is accessed on the correct actor.
                    // Guarded by UserDefaults — no-op on all launches after the first.
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(3))
                        await Perf.measureAsync(.databaseMigration) {
                            await DatabaseMigration.shared.runMigrations(modelContext: sharedModelContainer.mainContext)
                        }
                    }

                    // Backfill derived article fields off the main actor. Guarded and
                    // resumable, so this is a no-op on all launches after it completes.
                    // Deferred past the migration above so the two don't contend.
                    Task.detached(priority: .utility) {
                        try? await Task.sleep(for: .seconds(5))
                        await DatabaseMigration.shared.backfillDerivedArticleFields(container: container)
                    }

                    // Check if we need to sync on launch (content older than 2 hours).
                    // Delay increased to 1500ms to ensure first frame and @Query fetches complete.
                    checkAndSyncIfNeeded()
                }
                #if os(macOS)
                .frame(minWidth: 900, minHeight: 600)
                .onAppear {
                    restoreWindowFrame()
                }
                .onDisappear {
                    saveWindowFrame()
                }
                #endif
        }
        .modelContainer(sharedModelContainer)
        #if os(macOS)
        .defaultSize(width: 1200, height: 800)
        .commands {
            // Standard text editing commands
            CommandGroup(replacing: .textEditing) {
                Button("Copy") {
                    NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("c", modifiers: .command)
                
                Button("Select All") {
                    NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("a", modifiers: .command)
            }
            
            // Custom Feeds menu
            CommandMenu("Feeds") {
                Button("Sync All Feeds") {
                    BackgroundSyncManager.shared.triggerManualSync()
                }
                .keyboardShortcut("r", modifiers: .command)
                
                Divider()
                
                Button("Mark All as Read") {
                    Task { @MainActor in
                        markAllArticlesAsRead()
                    }
                }
                .keyboardShortcut("k", modifiers: [.command, .shift])
            }
            
            // Navigation menu
            CommandMenu("Navigate") {
                Button("Next Article") {
                    NotificationCenter.default.post(name: .navigateToNextArticle, object: nil)
                }
                .keyboardShortcut("j")
                
                Button("Previous Article") {
                    NotificationCenter.default.post(name: .navigateToPreviousArticle, object: nil)
                }
                .keyboardShortcut("k")
                
                Divider()
                
                Button("Previous Image") {
                    NotificationCenter.default.post(name: .navigateToPreviousImage, object: nil)
                }
                .keyboardShortcut(.leftArrow, modifiers: [])
                
                Button("Next Image") {
                    NotificationCenter.default.post(name: .navigateToNextImage, object: nil)
                }
                .keyboardShortcut(.rightArrow, modifiers: [])
            }
            
            // Article actions menu
            CommandMenu("Article") {
                Button("Toggle Favorite") {
                    NotificationCenter.default.post(name: .toggleArticleFavorite, object: nil)
                }
                .keyboardShortcut("f", modifiers: .command)
                
                Button("Toggle Read/Unread") {
                    NotificationCenter.default.post(name: .toggleArticleRead, object: nil)
                }
                .keyboardShortcut("u", modifiers: .command)
                
                Divider()
                
                Button("Open in Browser") {
                    NotificationCenter.default.post(name: .openArticleInBrowser, object: nil)
                }
                .keyboardShortcut("o", modifiers: .command)
                
                Button("Share Article") {
                    NotificationCenter.default.post(name: .shareArticle, object: nil)
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
            }
            
            // View menu additions
            CommandGroup(after: .sidebar) {
                Divider()
                
                Button("Increase Text Size") {
                    NotificationCenter.default.post(name: .increaseTextSize, object: nil)
                }
                .keyboardShortcut("+", modifiers: .command)
                
                Button("Decrease Text Size") {
                    NotificationCenter.default.post(name: .decreaseTextSize, object: nil)
                }
                .keyboardShortcut("-", modifiers: .command)
                
                Button("Reset Text Size") {
                    NotificationCenter.default.post(name: .resetTextSize, object: nil)
                }
                .keyboardShortcut("0", modifiers: .command)
            }
        }
        #endif

        #if os(macOS)
        Settings {
            SettingsView()
                .modelContainer(sharedModelContainer)
                .tint(accentColor.color)
        }
        .defaultSize(width: 550, height: 400)

        // Now Playing window
        WindowGroup("Now Playing", id: "now-playing") {
            NowPlayingView()
                .tint(accentColor.color)
        }
        .defaultSize(width: 420, height: 650)
        .windowResizability(.contentSize)
        #endif
    }

    @MainActor
    private func checkAndSyncIfNeeded() {
        guard FeedManager.needsSync() else { return }

        // Delay sync to let first frame and @Query fetches complete before network work begins
        Task.detached(priority: .utility) {
            try? await Task.sleep(for: .milliseconds(1500))
            await BackgroundSyncManager.shared.triggerManualSync()
        }
    }
    
    @MainActor
    private func markAllArticlesAsRead() {
        let context = sharedModelContainer.mainContext
        let fetchDescriptor = FetchDescriptor<Article>(predicate: #Predicate { article in
            !article.isRead
        })
        
        guard let articles = try? context.fetch(fetchDescriptor) else { return }
        
        for article in articles {
            article.isRead = true
        }
        
        try? context.save()
    }
    
    #if os(macOS)
    // MARK: - Window State Persistence
    
    @MainActor
    private func saveWindowFrame() {
        guard let window = NSApplication.shared.windows.first else { return }
        let frame = window.frame
        
        UserDefaults.standard.set(frame.origin.x, forKey: "windowX")
        UserDefaults.standard.set(frame.origin.y, forKey: "windowY")
        UserDefaults.standard.set(frame.size.width, forKey: "windowWidth")
        UserDefaults.standard.set(frame.size.height, forKey: "windowHeight")
    }
    
    @MainActor
    private func restoreWindowFrame() {
        guard let window = NSApplication.shared.windows.first else {
            // If window isn't ready yet, try again after a short delay
            Task {
                try? await Task.sleep(for: .milliseconds(100))
                restoreWindowFrame()
            }
            return
        }
        
        let x = UserDefaults.standard.double(forKey: "windowX")
        let y = UserDefaults.standard.double(forKey: "windowY")
        let width = UserDefaults.standard.double(forKey: "windowWidth")
        let height = UserDefaults.standard.double(forKey: "windowHeight")
        
        // Only restore if we have saved values (width > 0 indicates saved state exists)
        guard width > 0 else { return }
        
        let frame = NSRect(x: x, y: y, width: width, height: height)
        window.setFrame(frame, display: true)
    }
    #endif

    // MARK: - Debug Helpers

    #if DEBUG
    private func resetArticlesForTesting() {
        let context = ModelContext(sharedModelContainer)
        let descriptor = FetchDescriptor<Article>()
        if let articles = try? context.fetch(descriptor) {
            for article in articles { context.delete(article) }
            try? context.save()
            print("🧹 [Debug] Deleted \(articles.count) articles for cold-launch test")
        }
        // Clear the last sync date so checkAndSyncIfNeeded() treats this as a stale launch
        UserDefaults.standard.removeObject(forKey: "com.today.lastGlobalSyncDate")
        print("🧹 [Debug] Reset sync date — app will sync on next launch")
    }

    /// Seed a large store for performance measurement.
    ///
    /// Article `publishedDate` values are spread across a 90-day window so date-window
    /// predicates and the day-by-day "load previous day" path get realistic distribution
    /// rather than every article landing in the same bucket. Descriptions carry HTML so
    /// plain-text and minimal-content derivation costs are realistic too.
    private func seedLargeStoreForTesting() {
        let defaults = UserDefaults.standard
        let feedCount = defaults.integer(forKey: "SeedFeedCount") > 0
            ? defaults.integer(forKey: "SeedFeedCount") : 20
        let articlesPerFeed = defaults.integer(forKey: "SeedArticlesPerFeed") > 0
            ? defaults.integer(forKey: "SeedArticlesPerFeed") : 500
        let windowDays = 90

        let context = ModelContext(sharedModelContainer)

        // Idempotent: seeding runs in init(), so without this a second launch with the
        // flag would double the store. Keeping it a no-op lets you seed once and then
        // measure cold launch on subsequent runs with the same flag set.
        let seededMarker = "https://example.invalid/seed/0/feed.xml"
        let existing = try? context.fetch(
            FetchDescriptor<Feed>(predicate: #Predicate<Feed> { $0.url == seededMarker })
        )
        if let existing, !existing.isEmpty {
            let count = (try? context.fetchCount(FetchDescriptor<Article>())) ?? -1
            print("🌱 [Debug] Store already seeded (\(count) articles) — skipping")
            return
        }

        let categories = ["Technology", "News", "Personal", "Social", "Comics", "Alt"]
        let start = Date()
        var inserted = 0

        for feedIndex in 0..<feedCount {
            let feed = Feed(
                title: "Seeded Feed \(feedIndex)",
                url: "https://example.invalid/seed/\(feedIndex)/feed.xml",
                category: categories[feedIndex % categories.count]
            )
            context.insert(feed)

            for articleIndex in 0..<articlesPerFeed {
                // Spread across the window, oldest last, deterministically.
                let ageSeconds = Double(articleIndex) / Double(max(articlesPerFeed - 1, 1))
                    * Double(windowDays) * 86_400
                let published = Date(timeIntervalSinceNow: -ageSeconds)

                let article = Article(
                    title: "Seeded article \(articleIndex) from feed \(feedIndex)",
                    link: "https://example.invalid/seed/\(feedIndex)/\(articleIndex)",
                    articleDescription: "<p>Seeded <em>HTML</em> summary for article \(articleIndex) "
                        + "with entities &amp; &#8220;quotes&#8221; so stripping cost is realistic.</p>",
                    content: articleIndex % 3 == 0
                        ? String(repeating: "<p>Body paragraph.</p>", count: 20)
                        : nil,
                    publishedDate: published,
                    author: "Seed Author",
                    guid: "seed-\(feedIndex)-\(articleIndex)",
                    feed: feed
                )
                // Vary read/favorite so count aggregates have something to count.
                article.isRead = articleIndex % 4 == 0
                article.isFavorite = articleIndex % 25 == 0
                if articleIndex % 50 == 0 {
                    article.audioUrl = "https://example.invalid/seed/\(feedIndex)/\(articleIndex).mp3"
                    article.audioType = "audio/mpeg"
                }
                context.insert(article)
                inserted += 1
            }

            // Save per feed to keep peak memory bounded while seeding.
            try? context.save()
        }

        let elapsed = Date().timeIntervalSince(start)
        print("🌱 [Debug] Seeded \(feedCount) feeds / \(inserted) articles in \(String(format: "%.1f", elapsed))s")
    }
    #endif
}

// MARK: - Default Feed Setup

/// Insert default feeds on a fresh install, using a background ModelContext to avoid blocking
/// the main thread. The feed-count check runs on the main actor; inserts run off it.
///
/// Note: if this completes after the 1500ms launch sync fires, the sync will see zero feeds
/// and be a no-op. The next background refresh will pick up the defaults. This is acceptable
/// on first install.
private func addDefaultFeedsIfNeeded(container: ModelContainer) async {
    let interval = Perf.begin(.defaultFeedSetup)
    defer { Perf.end(interval) }

    // Check feed count on the main actor (mainContext is @MainActor-bound)
    let isEmpty = await MainActor.run {
        let fetchDescriptor = FetchDescriptor<Feed>()
        let existing = try? container.mainContext.fetch(fetchDescriptor)
        return existing?.isEmpty ?? true
    }

    guard isEmpty else { return }

    let defaultFeeds: [(String, String, String)] = [
        ("Jake Spurlock", "https://jakespurlock.com/feed/", "personal"),
        ("Matt Mullenweg", "https://ma.tt/feed/", "personal"),
        ("XKCD", "https://xkcd.com/rss.xml", "comics"),
        ("TechCrunch", "https://techcrunch.com/feed/", "technology"),
        ("The Verge", "https://www.theverge.com/rss/index.xml", "technology"),
        ("Hacker News", "https://news.ycombinator.com/rss", "technology"),
        ("Ars Technica", "https://feeds.arstechnica.com/arstechnica/index", "technology"),
        ("Daring Fireball", "https://daringfireball.net/feeds/main", "technology"),
        ("The New York Times", "https://rss.nytimes.com/services/xml/rss/nyt/Technology.xml", "news"),
        ("NPR", "https://feeds.npr.org/1001/rss.xml", "news"),
        ("r/politics", "https://www.reddit.com/r/politics/.json", "news"),
        ("r/TodayRSS", "https://www.reddit.com/r/TodayRSS/.json", "tech"),
        ("r/itookapicture", "https://www.reddit.com/r/itookapicture/.json", "social"),
        ("r/astrophotography", "https://www.reddit.com/r/astrophotography/.json", "social"),
    ]

    // Insert and save on a background context — avoids blocking the main thread
    let context = ModelContext(container)
    for (title, url, category) in defaultFeeds {
        let feed = Feed(title: title, url: url, category: category)
        context.insert(feed)
    }
    try? context.save()

    // Kick off initial sync after default feeds are inserted
    await BackgroundSyncManager.shared.triggerManualSync()
}
