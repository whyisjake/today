//
//  BackgroundSyncManager.swift
//  Today
//
//  Manages background fetching of RSS feeds and transcription processing
//

import Foundation
import BackgroundTasks
import SwiftData

class BackgroundSyncManager {
    static let shared = BackgroundSyncManager()

    private let syncTaskIdentifier = "com.today.feedsync"
    private let transcriptionTaskIdentifier = "com.today.transcription"

    // Track pending transcriptions for background processing
    private var pendingTranscriptionDownloadId: String?

    private init() {}

    /// Register background task on app launch
    func registerBackgroundTasks() {
        // Register feed sync task (BGAppRefreshTask)
        BGTaskScheduler.shared.register(forTaskWithIdentifier: syncTaskIdentifier, using: nil) { task in
            self.handleBackgroundSync(task: task as! BGAppRefreshTask)
        }

        // Register transcription processing task (BGProcessingTask - allows longer execution)
        BGTaskScheduler.shared.register(forTaskWithIdentifier: transcriptionTaskIdentifier, using: nil) { task in
            self.handleTranscriptionTask(task: task as! BGProcessingTask)
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
            PodcastDownload.self,
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

    // MARK: - Transcription Background Processing

    /// Schedule a background processing task for transcription
    func scheduleTranscriptionTask(for audioUrl: String) {
        pendingTranscriptionDownloadId = audioUrl

        let request = BGProcessingTaskRequest(identifier: transcriptionTaskIdentifier)
        // Transcription requires significant CPU time
        request.requiresNetworkConnectivity = false  // Already downloaded
        request.requiresExternalPower = false  // Can run on battery, but prefer plugged in

        do {
            try BGTaskScheduler.shared.submit(request)
            print("🎙️ Background transcription task scheduled for: \(audioUrl)")
        } catch {
            print("⚠️ Failed to schedule background transcription: \(error.localizedDescription)")
        }
    }

    /// Handle background transcription task
    private func handleTranscriptionTask(task: BGProcessingTask) {
        print("🎙️ Background transcription task triggered by iOS")

        guard let audioUrl = pendingTranscriptionDownloadId else {
            print("⚠️ No pending transcription found")
            task.setTaskCompleted(success: true)
            return
        }

        // Create a task to perform transcription
        let transcriptionTask = Task {
            await performBackgroundTranscription(audioUrl: audioUrl)
        }

        // Handle task expiration - save progress
        task.expirationHandler = {
            print("⏱️ Background transcription task expired (iOS terminated it)")
            transcriptionTask.cancel()
            // Note: TranscriptionService should handle partial saves
        }

        // Mark task as complete when done
        Task {
            await transcriptionTask.value
            pendingTranscriptionDownloadId = nil
            task.setTaskCompleted(success: true)
            print("✅ Background transcription task completed")
        }
    }

    /// Perform transcription in the background
    @MainActor
    private func performBackgroundTranscription(audioUrl: String) async {
        guard #available(iOS 26.0, *) else {
            print("❌ Transcription requires iOS 26+")
            return
        }

        print("🎙️ Starting background transcription...")

        // Create model container for background work
        let schema = Schema([
            Feed.self,
            Article.self,
            PodcastDownload.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        guard let modelContainer = try? ModelContainer(for: schema, configurations: [modelConfiguration]) else {
            print("❌ Failed to create model container for transcription")
            return
        }

        let modelContext = ModelContext(modelContainer)

        // Find the download
        let descriptor = FetchDescriptor<PodcastDownload>(
            predicate: #Predicate<PodcastDownload> { $0.audioUrl == audioUrl }
        )

        guard let download = try? modelContext.fetch(descriptor).first else {
            print("❌ Download not found for transcription: \(audioUrl)")
            return
        }

        // Configure transcription service
        TranscriptionService.shared.configure(with: modelContext)

        // Perform transcription
        do {
            try await TranscriptionService.shared.transcribe(download: download)
            try? modelContext.save()
            print("✅ Background transcription completed successfully")
        } catch {
            print("❌ Background transcription failed: \(error)")
        }
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
