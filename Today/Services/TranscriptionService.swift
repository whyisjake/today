//
//  TranscriptionService.swift
//  Today
//
//  Transcription service using iOS 26 SpeechAnalyzer/SpeechTranscriber
//

import Foundation
import Speech
import SwiftData
import Combine
import AVFoundation

/// Service for transcribing podcast episodes using on-device speech recognition
@available(iOS 26.0, *)
@MainActor
final class TranscriptionService: NSObject, ObservableObject {
    static let shared = TranscriptionService()

    // MARK: - Published State

    @Published var isTranscribing = false
    @Published var currentProgress: Double = 0.0
    @Published var currentArticleId: String?

    // MARK: - Private Properties

    private var modelContext: ModelContext?

    // MARK: - Initialization

    private override init() {
        super.init()
    }

    func configure(with modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Public API

    /// Check if transcription is available on this device
    func isAvailable() async -> Bool {
        let supported = await SpeechTranscriber.supportedLocales
        return !supported.isEmpty
    }

    /// Get the list of supported locales
    func supportedLocales() async -> [Locale] {
        return await SpeechTranscriber.supportedLocales
    }

    /// Check if a locale's model is installed
    func isModelInstalled(for locale: Locale) async -> Bool {
        let installed = await SpeechTranscriber.installedLocales
        return installed.map { $0.identifier(.bcp47) }.contains(locale.identifier(.bcp47))
    }

    /// Download the model for a locale if needed
    func ensureModelAvailable(for locale: Locale) async throws {
        // Check if locale is supported
        let supported = await SpeechTranscriber.supportedLocales
        guard supported.map({ $0.identifier(.bcp47) }).contains(locale.identifier(.bcp47)) else {
            throw TranscriptionError.localeNotSupported
        }

        // Check if already installed
        if await isModelInstalled(for: locale) {
            return
        }

        // Create transcriber for download
        let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)

        // Download the model
        if let downloader = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await downloader.downloadAndInstall()
        }
    }

    /// Transcribe a downloaded podcast episode
    func transcribe(download: PodcastDownload) async throws {
        guard let localPath = download.localFilePath else {
            throw TranscriptionError.noLocalFile
        }

        // Get the local file URL
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let downloadsDir = appSupport.appendingPathComponent("PodcastDownloads", isDirectory: true)
        let fileURL = downloadsDir.appendingPathComponent(localPath)

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw TranscriptionError.fileNotFound
        }

        // Update status
        isTranscribing = true
        currentProgress = 0.0
        currentArticleId = download.article?.guid
        download.transcriptionStatus = .inProgress
        download.transcriptionProgress = 0.0

        defer {
            isTranscribing = false
            currentArticleId = nil
        }

        do {
            // Use English locale by default, could be made configurable
            let locale = Locale(identifier: "en-US")

            // Ensure model is available
            try await ensureModelAvailable(for: locale)

            // Create transcriber for offline file transcription
            let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)

            // Create analyzer with the transcriber module
            let analyzer = SpeechAnalyzer(modules: [transcriber])

            // Load the audio file
            let audioFile = try AVAudioFile(forReading: fileURL)

            // Analyze the audio file
            if let lastSample = try await analyzer.analyzeSequence(from: audioFile) {
                try await analyzer.finalizeAndFinish(through: lastSample)
            }

            // Collect transcription results
            var finalTranscription = ""
            var processedSegments = 0

            for try await result in transcriber.results {
                if result.isFinal {
                    finalTranscription += String(result.text.characters)
                    finalTranscription += " "
                    processedSegments += 1

                    // Update progress (estimate based on segments)
                    let progress = min(Double(processedSegments) / 100.0, 0.95)
                    await MainActor.run {
                        self.currentProgress = progress
                        download.transcriptionProgress = progress
                    }
                }
            }

            // Clean up and finalize
            let cleanedTranscription = finalTranscription.trimmingCharacters(in: .whitespacesAndNewlines)

            // Update download with transcription
            download.transcription = cleanedTranscription
            download.transcriptionStatus = .completed
            download.transcriptionProgress = 1.0

            currentProgress = 1.0

            print("Transcription completed: \(cleanedTranscription.prefix(100))...")

        } catch {
            print("Transcription failed: \(error)")
            download.transcriptionStatus = .failed
            download.transcriptionProgress = 0.0
            throw error
        }
    }

    /// Cancel ongoing transcription
    func cancelTranscription() {
        isTranscribing = false
        currentProgress = 0.0
        currentArticleId = nil
    }
}

// MARK: - Errors

enum TranscriptionError: LocalizedError {
    case notAvailable
    case localeNotSupported
    case noLocalFile
    case fileNotFound
    case transcriptionFailed
    case modelDownloadFailed

    var errorDescription: String? {
        switch self {
        case .notAvailable:
            return "Transcription is not available on this device"
        case .localeNotSupported:
            return "The selected language is not supported"
        case .noLocalFile:
            return "Episode must be downloaded before transcribing"
        case .fileNotFound:
            return "Downloaded file not found"
        case .transcriptionFailed:
            return "Transcription failed"
        case .modelDownloadFailed:
            return "Failed to download speech recognition model"
        }
    }
}
