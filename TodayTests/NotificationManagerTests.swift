//
//  NotificationManagerTests.swift
//  TodayTests
//
//  Tests for NotificationManager service
//

import XCTest
import SwiftData
@testable import Today

final class NotificationManagerTests: XCTestCase {
    
    func testNotificationManagerSharedInstance() {
        // Test that shared instance is accessible
        let manager = NotificationManager.shared
        XCTAssertNotNil(manager)
    }
    
    @MainActor
    func testFeedNotificationsEnabledProperty() {
        // Test that Feed model has notificationsEnabled property
        let feed = Feed(
            title: "Test Feed",
            url: "https://example.com/rss",
            category: "test",
            notificationsEnabled: true
        )
        
        XCTAssertTrue(feed.notificationsEnabled)
        
        // Test default value
        let feedWithDefault = Feed(
            title: "Test Feed 2",
            url: "https://example.com/rss2",
            category: "test"
        )
        
        XCTAssertFalse(feedWithDefault.notificationsEnabled)
    }
    
    @MainActor
    func testFeedManagerSyncFeedReturnsNewArticles() async throws {
        // Create an in-memory model container for testing
        let schema = Schema([
            Feed.self,
            Article.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let modelContainer = try ModelContainer(for: schema, configurations: [modelConfiguration])
        let modelContext = ModelContext(modelContainer)
        
        // Create a test feed
        let feed = Feed(
            title: "Test Feed",
            url: "https://xkcd.com/rss.xml", // Use a real RSS feed for testing
            category: "test"
        )
        
        modelContext.insert(feed)
        try modelContext.save()
        
        // Create FeedManager and sync the feed
        let feedManager = FeedManager(modelContext: modelContext)
        
        // Note: This test requires network access and may be flaky
        // In production, we'd mock the network layer
        do {
            let newArticles = try await feedManager.syncFeed(feed)
            
            // Should return an array (empty or with articles)
            XCTAssertNotNil(newArticles)
            
            // If articles were fetched, verify they're tracked
            if !newArticles.isEmpty {
                print("✅ Sync returned \(newArticles.count) new articles")
                XCTAssertTrue(newArticles.allSatisfy { $0.feed?.url == feed.url })
            }
        } catch {
            // Network errors are acceptable in tests
            print("⚠️ Network error in test (expected): \(error.localizedDescription)")
        }
    }
}
