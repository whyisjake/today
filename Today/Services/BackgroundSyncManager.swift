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

@MainActor
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
    /// Track whether a sync is currently in progress
    @Published var isSyncInProgress = false

    private init() {}

    // MARK: - iOS Background Tasks

    #if os(iOS)
    /// Register background task on app launch
    nonisolated func registerBackgroundTasks() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: syncTaskIdentifier, using: nil) { task in
            Task { @MainActor in
                self.handleBackgroundSync(task: task as! BGAppRefreshTask)
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
    #endif

    // MARK: - macOS Timer-based Sync

    #if os(macOS)
    /// Start timer-based background sync for macOS
    func startBackgroundSync() {
        stopBackgroundSync()

        syncTimer = Timer.scheduledTimer(withTimeInterval: syncInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.triggerManualSync()
            }
        }
        print("⏰ macOS background sync timer started (interval: \(Int(syncInterval / 60)) minutes)")
    }

    /// Stop the background sync timer
    func stopBackgroundSync() {
        syncTimer?.invalidate()
        syncTimer = nil
    }
    #endif

    /// Perform the actual background sync
    /// Parsing runs in background, inserts run on main thread in chunks
    private func performBackgroundSync() async {
        // Prevent concurrent syncs
        guard !isSyncInProgress else { return }

        isSyncInProgress = true
        defer { isSyncInProgress = false }

        guard let container = modelContainer else { return }

        // Use BackgroundFeedSync which parses in background
        // and inserts on main thread in small chunks with yields
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
    #if os(iOS)
    nonisolated func enableBackgroundFetch() {
        scheduleBackgroundSync()
    }
    #elseif os(macOS)
    func enableBackgroundFetch() {
        startBackgroundSync()
    }
    #endif
}
