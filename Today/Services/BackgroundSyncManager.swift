//
//  BackgroundSyncManager.swift
//  Today
//
//  Manages background fetching of RSS feeds
//

import Foundation
#if os(iOS)
import BackgroundTasks
#endif
import SwiftData
import Combine

class BackgroundSyncManager: ObservableObject {
    static let shared = BackgroundSyncManager()

    #if os(iOS)
    private let syncTaskIdentifier = "com.today.feedsync"
    #elseif os(macOS)
    private var syncTimer: Timer?
    private let syncInterval: TimeInterval = 3600 // 1 hour
    #endif

    /// Shared ModelContainer for background sync operations
    /// Set by TodayApp on launch
    var modelContainer: ModelContainer?

    /// Track whether a sync is currently in progress.
    /// Always read and written on the main actor to avoid data races.
    @MainActor @Published var isSyncInProgress = false

    private init() {}

    // MARK: - iOS Background Tasks

    #if os(iOS)
    /// Register background task on app launch
    nonisolated func registerBackgroundTasks() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: syncTaskIdentifier, using: nil) { task in
            // handleBackgroundSync is not @MainActor, so no cross-actor call needed
            Task {
                await self.handleBackgroundSync(task: task as! BGAppRefreshTask)
            }
        }
    }

    /// Schedule the next background sync
    nonisolated func scheduleBackgroundSync() {
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
    private func handleBackgroundSync(task: BGAppRefreshTask) async {
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

        // Wait for sync to complete, then mark the BGTask done
        await syncTask.value
        task.setTaskCompleted(success: true)
        print("✅ Background sync task completed successfully")
    }
    #endif

    // MARK: - macOS Timer-based Sync

    #if os(macOS)
    /// Start timer-based background sync for macOS
    @MainActor
    func startBackgroundSync() {
        stopBackgroundSync()

        syncTimer = Timer.scheduledTimer(withTimeInterval: syncInterval, repeats: true) { [weak self] _ in
            self?.triggerManualSync()
        }
        print("⏰ macOS background sync timer started (interval: \(Int(syncInterval / 60)) minutes)")
    }

    /// Stop the background sync timer
    @MainActor
    func stopBackgroundSync() {
        syncTimer?.invalidate()
        syncTimer = nil
    }
    #endif

    /// Perform the actual background sync
    /// Parsing and insertion run entirely off the main thread via BackgroundFeedSync
    private func performBackgroundSync() async {
        // Read isSyncInProgress safely from the main actor before proceeding
        let alreadyInProgress = await MainActor.run { isSyncInProgress }
        guard !alreadyInProgress else { return }

        await MainActor.run { isSyncInProgress = true }
        defer {
            Task { await MainActor.run { self.isSyncInProgress = false } }
        }

        guard let container = modelContainer else { return }

        // BackgroundFeedSync runs parsing and insertion entirely off the main thread
        await BackgroundFeedSync.syncAllFeeds(container: container)

        // OPML sync requires FeedManager (@MainActor); run it on the main actor
        await syncOPMLSubscriptions(container: container)
    }

    /// Sync OPML subscriptions on the main actor (FeedManager requires mainContext)
    @MainActor
    private func syncOPMLSubscriptions(container: ModelContainer) async {
        let context = container.mainContext
        let feedManager = FeedManager(modelContext: context)
        let opmlManager = OPMLSubscriptionManager(modelContext: context, feedManager: feedManager)
        await opmlManager.syncAllSubscriptions()
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
    #if os(iOS)
    nonisolated func enableBackgroundFetch() {
        scheduleBackgroundSync()
    }
    #elseif os(macOS)
    @MainActor
    func enableBackgroundFetch() {
        startBackgroundSync()
    }
    #endif
}
