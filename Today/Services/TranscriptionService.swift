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

    /// Find a supported locale, preferring the device's current locale, then en_US
    func findSupportedLocale(preferring languageCode: String) async throws -> Locale {
        let supported = await SpeechTranscriber.supportedLocales

        print("🎙️ Available locales: \(supported.map { $0.identifier })")

        // Check if running in simulator (no locales available)
        if supported.isEmpty {
            print("🎙️ No supported locales available - SpeechTranscriber requires a physical device")
            throw TranscriptionError.notAvailableInSimulator
        }

        // 1. First try the device's current locale
        let deviceLocale = Locale.current
        if let deviceMatch = supported.first(where: {
            $0.identifier == deviceLocale.identifier ||
            $0.identifier(.bcp47) == deviceLocale.identifier(.bcp47)
        }) {
            print("🎙️ Using device locale: \(deviceMatch.identifier)")
            return deviceMatch
        }

        // 2. For English, prefer en_US specifically
        if languageCode == "en" {
            if let enUS = supported.first(where: { $0.identifier.hasPrefix("en_US") || $0.identifier(.bcp47) == "en-US" }) {
                print("🎙️ Using en_US locale: \(enUS.identifier)")
                return enUS
            }
        }

        // 3. Fall back to any locale matching the preferred language
        if let langMatch = supported.first(where: { $0.language.languageCode?.identifier == languageCode }) {
            print("🎙️ Found locale for language '\(languageCode)': \(langMatch.identifier)")
            return langMatch
        }

        // 4. Last resort: first available locale
        guard let fallback = supported.first else {
            print("🎙️ No supported locales available!")
            throw TranscriptionError.localeNotSupported
        }

        print("🎙️ Using fallback locale: \(fallback.identifier)")
        return fallback
    }

    /// Download the model for a locale if needed
    func ensureModelAvailable(for locale: Locale) async throws {
        // Check if locale is supported
        let supported = await SpeechTranscriber.supportedLocales

        // Debug: print supported locales
        print("🎙️ Supported locales: \(supported.map { $0.identifier })")
        print("🎙️ Looking for locale: \(locale.identifier)")

        // Try to find a matching locale (be flexible with format)
        let targetIdentifier = locale.identifier
        let matchingLocale = supported.first { supportedLocale in
            // Check various identifier formats
            supportedLocale.identifier == targetIdentifier ||
            supportedLocale.identifier(.bcp47) == locale.identifier(.bcp47) ||
            supportedLocale.language.languageCode == locale.language.languageCode
        }

        guard let actualLocale = matchingLocale else {
            print("🎙️ No matching locale found for \(targetIdentifier)")
            throw TranscriptionError.localeNotSupported
        }

        print("🎙️ Using locale: \(actualLocale.identifier)")

        // Check if already installed
        let installed = await SpeechTranscriber.installedLocales
        let isInstalled = installed.contains { $0.identifier == actualLocale.identifier }

        if isInstalled {
            print("🎙️ Model already installed")
            return
        }

        print("🎙️ Downloading model...")

        // Create transcriber for download
        let transcriber = SpeechTranscriber(locale: actualLocale, preset: .transcription)

        // Download the model
        if let downloader = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await downloader.downloadAndInstall()
            print("🎙️ Model download complete")
        }
    }

    /// Transcribe a downloaded podcast episode
    /// For episodes longer than 15 minutes, schedules a background processing task
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

        // Get audio duration for metrics
        let audioDuration = download.article?.audioDuration ?? 0

        // Check episode duration - schedule background task for long episodes
        if audioDuration > 900 {
            // Episodes > 15 minutes - schedule background processing in case app goes to background
            print("🎙️ Long episode detected (\(Int(audioDuration / 60)) min) - scheduling background task")
            BackgroundSyncManager.shared.scheduleTranscriptionTask(for: download.audioUrl)
        }

        // Start timing
        let transcriptionStartTime = Date()
        print("🎙️ ⏱️ Starting transcription at \(transcriptionStartTime.formatted(date: .omitted, time: .standard))")
        if audioDuration > 0 {
            print("🎙️ ⏱️ Audio duration: \(formatDuration(audioDuration))")
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
            // Find a supported English locale
            let transcriptionLocale = try await findSupportedLocale(preferring: "en")

            // Ensure model is available
            try await ensureModelAvailable(for: transcriptionLocale)

            // Create transcriber for offline file transcription
            let transcriber = SpeechTranscriber(locale: transcriptionLocale, preset: .transcription)

            // Create analyzer with the transcriber module
            let analyzer = SpeechAnalyzer(modules: [transcriber])

            // Load the audio file
            let audioFile = try AVAudioFile(forReading: fileURL)

            // Time the analysis phase
            let analysisStartTime = Date()

            // Analyze the audio file
            if let lastSample = try await analyzer.analyzeSequence(from: audioFile) {
                try await analyzer.finalizeAndFinish(through: lastSample)
            }

            let analysisEndTime = Date()
            let analysisDuration = analysisEndTime.timeIntervalSince(analysisStartTime)
            print("🎙️ ⏱️ Audio analysis completed in \(formatDuration(analysisDuration))")

            // Collect transcription results
            var finalTranscription = ""
            var processedSegments = 0
            let resultsStartTime = Date()

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

            let resultsEndTime = Date()
            let resultsDuration = resultsEndTime.timeIntervalSince(resultsStartTime)
            print("🎙️ ⏱️ Results collection completed in \(formatDuration(resultsDuration))")

            // Clean up and finalize
            let cleanedTranscription = finalTranscription.trimmingCharacters(in: .whitespacesAndNewlines)

            // Calculate final metrics
            let transcriptionEndTime = Date()
            let totalDuration = transcriptionEndTime.timeIntervalSince(transcriptionStartTime)
            let wordCount = cleanedTranscription.split(separator: " ").count

            // Log comprehensive metrics
            print("🎙️ ✅ Transcription completed!")
            print("🎙️ ⏱️ Total time: \(formatDuration(totalDuration))")
            if audioDuration > 0 {
                let realtimeFactor = audioDuration / totalDuration
                print("🎙️ ⏱️ Realtime factor: \(String(format: "%.1fx", realtimeFactor)) (audio/transcription time)")
            }
            print("🎙️ ⏱️ Words transcribed: \(wordCount)")
            if totalDuration > 0 {
                let wordsPerSecond = Double(wordCount) / totalDuration
                print("🎙️ ⏱️ Processing rate: \(String(format: "%.1f", wordsPerSecond)) words/sec")
            }
            print("🎙️ ⏱️ Segments processed: \(processedSegments)")

            // Update download with transcription
            download.transcription = cleanedTranscription
            download.transcriptionStatus = .completed
            download.transcriptionProgress = 1.0
            download.transcriptionDuration = totalDuration
            download.transcribedAt = Date()

            currentProgress = 1.0

            print("🎙️ Preview: \(cleanedTranscription.prefix(100))...")

        } catch {
            let failTime = Date()
            let elapsedTime = failTime.timeIntervalSince(transcriptionStartTime)
            print("🎙️ ❌ Transcription failed after \(formatDuration(elapsedTime)): \(error)")
            download.transcriptionStatus = .failed
            download.transcriptionProgress = 0.0
            throw error
        }
    }

    /// Format duration as human-readable string
    private func formatDuration(_ seconds: TimeInterval) -> String {
        if seconds < 60 {
            return String(format: "%.1f sec", seconds)
        } else if seconds < 3600 {
            let minutes = Int(seconds) / 60
            let secs = Int(seconds) % 60
            return "\(minutes)m \(secs)s"
        } else {
            let hours = Int(seconds) / 3600
            let minutes = (Int(seconds) % 3600) / 60
            let secs = Int(seconds) % 60
            return "\(hours)h \(minutes)m \(secs)s"
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
    case notAvailableInSimulator
    case localeNotSupported
    case noLocalFile
    case fileNotFound
    case transcriptionFailed
    case modelDownloadFailed

    var errorDescription: String? {
        switch self {
        case .notAvailable:
            return "Transcription is not available on this device"
        case .notAvailableInSimulator:
            return "Transcription requires a physical device. SpeechTranscriber is not available in the iOS Simulator."
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
