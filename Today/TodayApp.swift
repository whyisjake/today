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
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    init() {
        #if os(iOS)
        // Configure audio session to mix with other audio (music, podcasts, etc.)
        // This allows animated GIFs and videos to play without interrupting user's audio
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Failed to set audio session category: \(error)")
        }

        // Register background tasks (nonisolated - safe to call from init)
        BackgroundSyncManager.shared.registerBackgroundTasks()
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

                    // Add default feeds on first launch
                    addDefaultFeedsIfNeeded()

                    // Run database migrations
                    Task {
                        await DatabaseMigration.shared.runMigrations(modelContext: sharedModelContainer.mainContext)
                    }

                    // Check if we need to sync on launch (content older than 2 hours)
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
        #endif
    }

    @MainActor
    private func checkAndSyncIfNeeded() {
        guard FeedManager.needsSync() else { return }

        // Delay sync slightly to let UI render first, then run entirely in background
        Task.detached(priority: .utility) {
            try? await Task.sleep(for: .milliseconds(500))
            await BackgroundSyncManager.shared.triggerManualSync()
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

        // Sync the feeds to get initial articles (delay to let UI render first)
        Task.detached(priority: .utility) {
            try? await Task.sleep(for: .milliseconds(500))
            // Use BackgroundSyncManager for off-main-thread sync
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
}
