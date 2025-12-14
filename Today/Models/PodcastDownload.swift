//
//  PodcastDownload.swift
//  Today
//
//  Model for tracking podcast episode downloads, transcriptions, and AI-generated chapters
//

import Foundation
import SwiftData

/// Status of podcast episode download
enum DownloadStatus: String, Codable {
    case notStarted
    case downloading
    case paused
    case completed
    case failed
}

/// Status of transcription processing
enum TranscriptionStatus: String, Codable {
    case notStarted
    case inProgress
    case completed
    case failed
}

/// Status of AI chapter generation
enum ChapterGenerationStatus: String, Codable {
    case notStarted
    case inProgress
    case completed
    case failed
}

/// AI-generated chapter data
struct AIChapterData: Codable, Identifiable, Equatable {
    let id: UUID
    let title: String
    let summary: String
    let startTime: TimeInterval
    let endTime: TimeInterval?
    let keywords: [String]
    let isAd: Bool  // True if this segment is an advertisement

    init(id: UUID = UUID(), title: String, summary: String, startTime: TimeInterval, endTime: TimeInterval? = nil, keywords: [String] = [], isAd: Bool = false) {
        self.id = id
        self.title = title
        self.summary = summary
        self.startTime = startTime
        self.endTime = endTime
        self.keywords = keywords
        self.isAd = isAd
    }
}

@Model
final class PodcastDownload {
    // Core reference
    @Relationship(inverse: \Article.podcastDownload)
    var article: Article?
    var audioUrl: String

    // Download state
    var localFilePath: String?
    var downloadProgress: Double
    var downloadStatusRaw: String
    var downloadedAt: Date?
    var fileSize: Int64?
    var resumeData: Data? // For pause/resume support

    // Transcription
    var transcription: String?
    var transcriptionStatusRaw: String
    var transcriptionProgress: Double
    var transcribedAt: Date?
    var transcriptionDuration: TimeInterval? // How long transcription took (for metrics)

    // AI-generated chapters (stored as JSON Data)
    var aiChaptersData: Data?
    var chapterGenerationStatusRaw: String
    var chaptersGeneratedAt: Date?

    // Computed properties for enums
    var downloadStatus: DownloadStatus {
        get { DownloadStatus(rawValue: downloadStatusRaw) ?? .notStarted }
        set { downloadStatusRaw = newValue.rawValue }
    }

    var transcriptionStatus: TranscriptionStatus {
        get { TranscriptionStatus(rawValue: transcriptionStatusRaw) ?? .notStarted }
        set { transcriptionStatusRaw = newValue.rawValue }
    }

    var chapterGenerationStatus: ChapterGenerationStatus {
        get { ChapterGenerationStatus(rawValue: chapterGenerationStatusRaw) ?? .notStarted }
        set { chapterGenerationStatusRaw = newValue.rawValue }
    }

    // Computed property for AI chapters
    var aiChapters: [AIChapterData]? {
        get {
            guard let data = aiChaptersData else { return nil }
            return try? JSONDecoder().decode([AIChapterData].self, from: data)
        }
        set {
            aiChaptersData = try? JSONEncoder().encode(newValue)
        }
    }

    init(audioUrl: String, article: Article? = nil) {
        self.audioUrl = audioUrl
        self.article = article
        self.localFilePath = nil
        self.downloadProgress = 0.0
        self.downloadStatusRaw = DownloadStatus.notStarted.rawValue
        self.downloadedAt = nil
        self.fileSize = nil
        self.resumeData = nil
        self.transcription = nil
        self.transcriptionStatusRaw = TranscriptionStatus.notStarted.rawValue
        self.transcriptionProgress = 0.0
        self.transcribedAt = nil
        self.transcriptionDuration = nil
        self.aiChaptersData = nil
        self.chapterGenerationStatusRaw = ChapterGenerationStatus.notStarted.rawValue
        self.chaptersGeneratedAt = nil
    }

    /// Check if episode is ready for transcription
    var canTranscribe: Bool {
        downloadStatus == .completed && transcriptionStatus == .notStarted
    }

    /// Check if episode is ready for chapter generation
    var canGenerateChapters: Bool {
        transcriptionStatus == .completed && chapterGenerationStatus == .notStarted
    }

    /// Check if all processing is complete
    var isFullyProcessed: Bool {
        downloadStatus == .completed &&
        transcriptionStatus == .completed &&
        chapterGenerationStatus == .completed
    }

    /// Check if transcription appears stuck (in progress but no recent updates)
    /// This can happen if the app was terminated during transcription
    var isTranscriptionStuck: Bool {
        transcriptionStatus == .inProgress
    }

    /// Reset transcription state to allow retry
    func resetTranscription() {
        transcriptionStatus = .notStarted
        transcriptionProgress = 0.0
        transcription = nil
        transcribedAt = nil
        transcriptionDuration = nil
    }

    /// Reset chapter generation state to allow retry
    func resetChapterGeneration() {
        chapterGenerationStatus = .notStarted
        aiChaptersData = nil
        chaptersGeneratedAt = nil
    }
}
