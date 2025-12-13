//
//  PodcastDownloadManager.swift
//  Today
//
//  Manages podcast episode downloads with background support
//

import Foundation
import SwiftData
import UIKit
import Combine

/// Manages podcast episode downloads with background transfer support
@MainActor
final class PodcastDownloadManager: NSObject, ObservableObject {
    static let shared = PodcastDownloadManager()

    // MARK: - Published State

    @Published var activeDownloads: [String: URLSessionDownloadTask] = [:]
    @Published var downloadProgress: [String: Double] = [:]

    // MARK: - Private Properties

    private var modelContext: ModelContext?
    private var downloadCompletionHandlers: [String: (URL?, URLResponse?, Error?) -> Void] = [:]

    private lazy var backgroundSession: URLSession = {
        let config = URLSessionConfiguration.background(withIdentifier: "com.today.podcastDownload")
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        config.allowsExpensiveNetworkAccess = true
        config.allowsConstrainedNetworkAccess = true
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    // MARK: - Storage Location

    private var downloadsDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let downloadsDir = appSupport.appendingPathComponent("PodcastDownloads", isDirectory: true)

        if !FileManager.default.fileExists(atPath: downloadsDir.path) {
            try? FileManager.default.createDirectory(at: downloadsDir, withIntermediateDirectories: true)
        }

        return downloadsDir
    }

    // MARK: - Initialization

    private override init() {
        super.init()
    }

    func configure(with modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Public API

    /// Download a podcast episode
    func downloadEpisode(for article: Article) async throws {
        guard let audioUrl = article.audioUrl, let url = URL(string: audioUrl) else {
            throw DownloadError.invalidURL
        }

        // Check if already downloading
        if activeDownloads[audioUrl] != nil {
            return
        }

        // Create or get existing PodcastDownload
        let download = getOrCreateDownload(for: article, audioUrl: audioUrl)
        download.downloadStatus = .downloading
        download.downloadProgress = 0.0

        // Start download task
        let task = backgroundSession.downloadTask(with: url)
        task.taskDescription = audioUrl
        activeDownloads[audioUrl] = task
        downloadProgress[audioUrl] = 0.0

        task.resume()
    }

    /// Pause an active download
    func pauseDownload(for article: Article) {
        guard let audioUrl = article.audioUrl,
              let task = activeDownloads[audioUrl] else { return }

        task.cancel { [weak self] resumeData in
            // Must dispatch to MainActor to update model and state
            Task { @MainActor [audioUrl] in
                guard let self = self else { return }

                // Fetch download from modelContext to avoid Sendable capture
                let descriptor = FetchDescriptor<PodcastDownload>(
                    predicate: #Predicate<PodcastDownload> { $0.audioUrl == audioUrl }
                )

                if let modelContext = self.modelContext,
                   let download = try? modelContext.fetch(descriptor).first {
                    download.resumeData = resumeData
                    download.downloadStatus = .paused
                }

                self.activeDownloads.removeValue(forKey: audioUrl)
            }
        }
    }

    /// Resume a paused download
    func resumeDownload(for article: Article) {
        guard let audioUrl = article.audioUrl,
              let download = article.podcastDownload,
              download.downloadStatus == .paused else { return }

        let task: URLSessionDownloadTask
        if let resumeData = download.resumeData {
            task = backgroundSession.downloadTask(withResumeData: resumeData)
        } else if let url = URL(string: audioUrl) {
            task = backgroundSession.downloadTask(with: url)
        } else {
            return
        }

        task.taskDescription = audioUrl
        activeDownloads[audioUrl] = task
        download.downloadStatus = .downloading
        download.resumeData = nil

        task.resume()
    }

    /// Cancel a download
    func cancelDownload(for article: Article) {
        guard let audioUrl = article.audioUrl else { return }

        activeDownloads[audioUrl]?.cancel()
        activeDownloads.removeValue(forKey: audioUrl)
        downloadProgress.removeValue(forKey: audioUrl)

        if let download = article.podcastDownload {
            download.downloadStatus = .notStarted
            download.downloadProgress = 0.0
            download.resumeData = nil
        }
    }

    /// Delete a downloaded episode
    func deleteDownload(for download: PodcastDownload) {
        if let localPath = download.localFilePath {
            let fileURL = downloadsDirectory.appendingPathComponent(localPath)
            try? FileManager.default.removeItem(at: fileURL)
        }

        download.localFilePath = nil
        download.downloadStatus = .notStarted
        download.downloadProgress = 0.0
        download.downloadedAt = nil
        download.fileSize = nil

        // Also reset transcription and chapters
        download.transcription = nil
        download.transcriptionStatus = .notStarted
        download.transcriptionProgress = 0.0
        download.aiChapters = nil
        download.chapterGenerationStatus = .notStarted
    }

    /// Get local file URL for a download
    func getLocalFileURL(for download: PodcastDownload) -> URL? {
        guard let localPath = download.localFilePath,
              download.downloadStatus == .completed else { return nil }
        return downloadsDirectory.appendingPathComponent(localPath)
    }

    // MARK: - Storage Management

    // MARK: - Episode Limit Enforcement

    /// Enforce episode limits for a feed after a download completes
    func enforceEpisodeLimits(for feed: Feed, modelContext: ModelContext) {
        // Get the effective limit (feed-specific or global default)
        let globalDefault = UserDefaults.standard.integer(forKey: "defaultEpisodeLimit")
        let effectiveLimit: Int

        if let feedLimit = feed.downloadEpisodeLimit {
            // Feed has a specific setting
            if feedLimit == 0 {
                // 0 means unlimited for this feed
                return
            }
            effectiveLimit = feedLimit
        } else {
            // Use global default
            if globalDefault == 0 {
                // Global default is unlimited
                return
            }
            effectiveLimit = globalDefault
        }

        // Get all completed downloads for this feed, sorted by download date (newest first)
        guard let articles = feed.articles else { return }

        let completedDownloads = articles
            .compactMap { $0.podcastDownload }
            .filter { $0.downloadStatus == .completed }
            .sorted { ($0.downloadedAt ?? .distantPast) > ($1.downloadedAt ?? .distantPast) }

        // If we're over the limit, delete the oldest downloads
        if completedDownloads.count > effectiveLimit {
            let downloadsToRemove = completedDownloads.dropFirst(effectiveLimit)
            for download in downloadsToRemove {
                deleteDownload(for: download)
                print("🗑️ Auto-deleted episode to stay within limit: \(download.article?.title ?? "Unknown")")
            }
        }
    }

    /// Calculate total size of downloaded episodes
    func totalDownloadedSize() -> Int64 {
        var totalSize: Int64 = 0

        if let contents = try? FileManager.default.contentsOfDirectory(at: downloadsDirectory, includingPropertiesForKeys: [.fileSizeKey]) {
            for fileURL in contents {
                if let resourceValues = try? fileURL.resourceValues(forKeys: [.fileSizeKey]),
                   let fileSize = resourceValues.fileSize {
                    totalSize += Int64(fileSize)
                }
            }
        }

        return totalSize
    }

    /// Format size for display
    func formattedTotalSize() -> String {
        let size = totalDownloadedSize()
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    /// Clean up old downloads
    func cleanupOldDownloads(olderThan days: Int, modelContext: ModelContext) async {
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()

        let descriptor = FetchDescriptor<PodcastDownload>(
            predicate: #Predicate<PodcastDownload> { download in
                download.downloadedAt != nil && download.downloadedAt! < cutoffDate
            }
        )

        if let oldDownloads = try? modelContext.fetch(descriptor) {
            for download in oldDownloads {
                deleteDownload(for: download)
            }
        }
    }

    // MARK: - Private Helpers

    private func getOrCreateDownload(for article: Article, audioUrl: String) -> PodcastDownload {
        if let existing = article.podcastDownload {
            return existing
        }

        let download = PodcastDownload(audioUrl: audioUrl, article: article)
        article.podcastDownload = download
        return download
    }

    private func generateLocalFileName(for url: String) -> String {
        let uuid = UUID().uuidString
        let ext = URL(string: url)?.pathExtension ?? "mp3"
        return "\(uuid).\(ext)"
    }
}

// MARK: - URLSessionDownloadDelegate

extension PodcastDownloadManager: URLSessionDownloadDelegate {
    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let audioUrl = downloadTask.taskDescription else { return }

        // Generate local file name
        let fileName = UUID().uuidString + "." + (URL(string: audioUrl)?.pathExtension ?? "mp3")

        // IMPORTANT: Must move the file synchronously within this callback!
        // The temp file at 'location' is deleted after this method returns.

        // Get downloads directory (can't use self.downloadsDirectory since we're nonisolated)
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let downloadsDir = appSupport.appendingPathComponent("PodcastDownloads", isDirectory: true)

        // Create directory if needed
        if !FileManager.default.fileExists(atPath: downloadsDir.path) {
            do {
                try FileManager.default.createDirectory(at: downloadsDir, withIntermediateDirectories: true)
            } catch {
                print("Failed to create downloads directory: \(error)")
                Task { @MainActor in
                    self.handleDownloadFailure(audioUrl: audioUrl)
                }
                return
            }
        }

        let destinationURL = downloadsDir.appendingPathComponent(fileName)

        // Move file synchronously - must happen before delegate method returns
        let fileSize: Int64
        do {
            try FileManager.default.moveItem(at: location, to: destinationURL)
            let attributes = try FileManager.default.attributesOfItem(atPath: destinationURL.path)
            fileSize = attributes[.size] as? Int64 ?? 0
        } catch {
            print("Failed to move downloaded file: \(error)")
            Task { @MainActor in
                self.handleDownloadFailure(audioUrl: audioUrl)
            }
            return
        }

        // File moved successfully, now update model on MainActor
        Task { @MainActor [fileSize] in
            let descriptor = FetchDescriptor<PodcastDownload>(
                predicate: #Predicate<PodcastDownload> { $0.audioUrl == audioUrl }
            )

            if let modelContext = self.modelContext,
               let download = try? modelContext.fetch(descriptor).first {
                download.localFilePath = fileName
                download.downloadStatus = .completed
                download.downloadProgress = 1.0
                download.downloadedAt = Date()
                download.fileSize = fileSize
                download.resumeData = nil

                // Enforce episode limits for this feed
                if let feed = download.article?.feed {
                    self.enforceEpisodeLimits(for: feed, modelContext: modelContext)
                }
            }

            self.activeDownloads.removeValue(forKey: audioUrl)
            self.downloadProgress[audioUrl] = 1.0
        }
    }

    /// Helper to handle download failures on MainActor
    private func handleDownloadFailure(audioUrl: String) {
        let descriptor = FetchDescriptor<PodcastDownload>(
            predicate: #Predicate<PodcastDownload> { $0.audioUrl == audioUrl }
        )

        if let modelContext = self.modelContext,
           let download = try? modelContext.fetch(descriptor).first {
            download.downloadStatus = .failed
        }

        self.activeDownloads.removeValue(forKey: audioUrl)
    }

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let audioUrl = downloadTask.taskDescription else { return }

        let progress = totalBytesExpectedToWrite > 0
            ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
            : 0.0

        Task { @MainActor in
            self.downloadProgress[audioUrl] = progress

            let descriptor = FetchDescriptor<PodcastDownload>(
                predicate: #Predicate<PodcastDownload> { $0.audioUrl == audioUrl }
            )

            if let modelContext = self.modelContext,
               let download = try? modelContext.fetch(descriptor).first {
                download.downloadProgress = progress
            }
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let downloadTask = task as? URLSessionDownloadTask,
              let audioUrl = downloadTask.taskDescription,
              let error = error else { return }

        Task { @MainActor in
            self.activeDownloads.removeValue(forKey: audioUrl)

            let descriptor = FetchDescriptor<PodcastDownload>(
                predicate: #Predicate<PodcastDownload> { $0.audioUrl == audioUrl }
            )

            if let modelContext = self.modelContext,
               let download = try? modelContext.fetch(descriptor).first {
                // Check if user cancelled
                let nsError = error as NSError
                if nsError.code == NSURLErrorCancelled {
                    // Already handled in pauseDownload/cancelDownload
                    return
                }
                download.downloadStatus = .failed
            }
        }
    }

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didResumeAtOffset fileOffset: Int64, expectedTotalBytes: Int64) {
        // Handle resume notification if needed
    }

    // Handle background session events
    nonisolated func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        // Background session events completed
        // In SwiftUI, background URL session completion is handled via scene phase changes
        // For full background download support, implement UIApplicationDelegate or use BGTaskScheduler
    }
}

// MARK: - Errors

enum DownloadError: LocalizedError {
    case invalidURL
    case downloadFailed
    case fileMoveFailed

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid audio URL"
        case .downloadFailed:
            return "Download failed"
        case .fileMoveFailed:
            return "Failed to save downloaded file"
        }
    }
}
