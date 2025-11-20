//
//  BackgroundSyncManager.swift
//  Today
//
//  Manages background fetching of RSS feeds
//

import Foundation
import BackgroundTasks
import SwiftData

class BackgroundSyncManager {
    static let shared = BackgroundSyncManager()

    private let syncTaskIdentifier = "com.today.feedsync"

    private init() {}

    /// Register background task on app launch
    func registerBackgroundTasks() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: syncTaskIdentifier, using: nil) { task in
            self.handleBackgroundSync(task: task as! BGAppRefreshTask)
        }
    }

    /// Schedule the next background sync
    func scheduleBackgroundSync() {
        let request = BGAppRefreshTaskRequest(identifier: syncTaskIdentifier)
        // Schedule for 1 hour from now (minimum is 15 minutes for BGAppRefreshTask)
        let scheduledDate = Date(timeIntervalSinceNow: 60 * 60)
        request.earliestBeginDate = scheduledDate

        do {
            try BGTaskScheduler.shared.submit(request)
            print("⏰ Background sync scheduled for \(scheduledDate.formatted(date: .omitted, time: .standard))")
        } catch {
            print("⚠️ Failed to schedule background sync: \(error.localizedDescription)")
            // Background sync not available (needs Info.plist configuration)
            // This is optional, so we silently ignore the error
        }
    }

    /// Handle background sync task
    private func handleBackgroundSync(task: BGAppRefreshTask) {
        print("🔔 Background sync task triggered by iOS")

        // Schedule the next sync
        scheduleBackgroundSync()

        // Create a task to perform the sync
        let syncTask = Task {
            await performBackgroundSync()
        }

        // Handle task expiration
        task.expirationHandler = {
            print("⏱️ Background sync task expired (iOS terminated it)")
            syncTask.cancel()
        }

        // Mark task as complete when done
        Task {
            await syncTask.value
            task.setTaskCompleted(success: true)
            print("✅ Background sync task completed successfully")
        }
    }

    /// Perform the actual background sync
    @MainActor
    private func performBackgroundSync() async {
        print("🔄 Performing background sync...")

        // Create a temporary model container for background work
        let schema = Schema([
            Feed.self,
            Article.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        guard let modelContainer = try? ModelContainer(for: schema, configurations: [modelConfiguration]) else {
            print("❌ Failed to create model container for background sync")
            return
        }

        let modelContext = ModelContext(modelContainer)
        let feedManager = FeedManager(modelContext: modelContext)

        // Sync all feeds (FeedManager.syncAllFeeds has detailed logging)
        await feedManager.syncAllFeeds()
    }

    /// Manually trigger a sync (useful for testing)
    func triggerManualSync() {
        Task {
            await performBackgroundSync()
        }
    }
}

// MARK: - App Extension for Background Fetch

extension BackgroundSyncManager {
    /// Enable background fetch when user opens the app
    func enableBackgroundFetch() {
        scheduleBackgroundSync()
    }
}
