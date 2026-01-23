//
//  BackgroundSyncManager.swift
//  Today
//
//  Manages background fetching of RSS feeds
//

import Foundation
import BackgroundTasks
import SwiftData
import Combine

@MainActor
class BackgroundSyncManager: ObservableObject {
    static let shared = BackgroundSyncManager()

    private let syncTaskIdentifier = "com.today.feedsync"

    /// Shared ModelContainer for background sync operations
    /// Set by TodayApp on launch
    var modelContainer: ModelContainer?

    /// Track whether a sync is currently in progress
    @Published var isSyncInProgress = false

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
    /// Parsing runs in background, inserts run on main thread in chunks
    private func performBackgroundSync() async {
        // Prevent concurrent syncs
        guard !isSyncInProgress else {
            print("⚠️ Sync already in progress, skipping")
            return
        }

        isSyncInProgress = true
        defer { isSyncInProgress = false }

        print("🔄 Performing background sync...")

        guard let container = modelContainer else {
            print("❌ ModelContainer not set - cannot perform background sync")
            return
        }

        // Use BackgroundFeedSync which parses in background
        // and inserts on main thread in small chunks with yields
        // Since this class is @MainActor, we can access mainContext directly
        let context = container.mainContext
        await BackgroundFeedSync.syncAllFeeds(modelContext: context)
    }

    /// Manually trigger a sync (useful for testing and launch sync)
    /// Note: This is safe to call multiple times - isSyncInProgress guard in performBackgroundSync prevents overlaps
    func triggerManualSync() {
        Task {
            await self.performBackgroundSync()
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
