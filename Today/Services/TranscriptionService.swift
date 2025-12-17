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

/// Transcription speed mode
@available(iOS 26.0, *)
enum TranscriptionMode: String, CaseIterable {
    case accurate = "accurate"      // .transcription preset - slower, more accurate
    case fast = "fast"              // .progressiveTranscription preset - faster, may be less accurate

    var preset: SpeechTranscriber.Preset {
        switch self {
        case .accurate:
            return .transcription
        case .fast:
            return .progressiveTranscription
        }
    }

    var displayName: String {
        switch self {
        case .accurate:
            return "Accurate"
        case .fast:
            return "Fast"
        }
    }
}

/// Service for transcribing podcast episodes using on-device speech recognition
@available(iOS 26.0, *)
@MainActor
final class TranscriptionService: NSObject, ObservableObject {
    static let shared = TranscriptionService()

    // MARK: - Published State

    @Published var isTranscribing = false
    @Published var currentProgress: Double = 0.0
    @Published var currentArticleId: String?
    @Published var currentPhase: String = ""

    // MARK: - Private Properties

    private var modelContext: ModelContext?

    // MARK: - Progress Constants (based on real-world testing)

    /// Analysis phase takes roughly 1 second per minute of audio
    private let analysisSecondsPerMinute: Double = 1.0
    /// Results phase processes at roughly 5x realtime
    private let resultsRealtimeFactor: Double = 5.0
    /// Analysis phase represents 10% of total progress
    private let analysisProgressWeight: Double = 0.10

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
        print("🎙️ Ensuring model available for: \(locale.identifier)")

        // Check if already installed - use exact match
        let installed = await SpeechTranscriber.installedLocales
        let isInstalled = installed.contains {
            $0.identifier == locale.identifier ||
            $0.identifier(.bcp47) == locale.identifier(.bcp47)
        }

        if isInstalled {
            print("🎙️ Model already installed for \(locale.identifier)")
            return
        }

        print("🎙️ Downloading model for \(locale.identifier)...")

        // Create transcriber for download using the exact locale passed in
        let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)

        // Download the model
        if let downloader = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await downloader.downloadAndInstall()
            print("🎙️ Model download complete")
        }
    }

    /// Transcribe a downloaded podcast episode
    /// For episodes longer than 15 minutes, schedules a background processing task
    /// - Parameters:
    ///   - download: The podcast download to transcribe
    ///   - mode: Transcription mode (.accurate or .fast)
    func transcribe(download: PodcastDownload, mode: TranscriptionMode = .accurate) async throws {
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
        let audioDurationMinutes = audioDuration / 60.0

        // Check episode duration - schedule background task for long episodes
        if audioDuration > 900 {
            // Episodes > 15 minutes - schedule background processing in case app goes to background
            print("🎙️ Long episode detected (\(Int(audioDurationMinutes)) min) - scheduling background task")
            BackgroundSyncManager.shared.scheduleTranscriptionTask(for: download.audioUrl)
        }

        // Calculate estimated times for progress tracking
        let estimatedAnalysisTime = audioDurationMinutes * analysisSecondsPerMinute
        let estimatedResultsTime = audioDuration / resultsRealtimeFactor
        let estimatedTotalTime = estimatedAnalysisTime + estimatedResultsTime

        // Start timing
        let transcriptionStartTime = Date()
        print("🎙️ ⏱️ Starting transcription at \(transcriptionStartTime.formatted(date: .omitted, time: .standard))")
        print("🎙️ ⚙️ Mode: \(mode.displayName) (preset: \(mode == .accurate ? ".transcription" : ".progressiveTranscription"))")
        if audioDuration > 0 {
            print("🎙️ ⏱️ Audio duration: \(formatDuration(audioDuration))")
            print("🎙️ ⏱️ Estimated total time: \(formatDuration(estimatedTotalTime))")
        }

        // Update status
        isTranscribing = true
        currentProgress = 0.0
        currentPhase = "Preparing..."
        currentArticleId = download.article?.guid
        download.transcriptionStatus = .inProgress
        download.transcriptionProgress = 0.0

        defer {
            isTranscribing = false
            currentArticleId = nil
            currentPhase = ""
        }

        do {
            // Find a supported English locale
            let transcriptionLocale = try await findSupportedLocale(preferring: "en")

            // Ensure model is available
            try await ensureModelAvailable(for: transcriptionLocale)

            // Create transcriber with selected preset
            let transcriber = SpeechTranscriber(locale: transcriptionLocale, preset: mode.preset)

            // Create analyzer with the transcriber module
            let analyzer = SpeechAnalyzer(modules: [transcriber])

            // Load the audio file
            let audioFile = try AVAudioFile(forReading: fileURL)

            // PHASE 1: Audio Analysis (0% - 10%)
            currentPhase = "Analyzing audio..."
            let analysisStartTime = Date()

            // Update progress during analysis phase using time-based estimation
            let analysisProgressTask = Task {
                while !Task.isCancelled {
                    let elapsed = Date().timeIntervalSince(analysisStartTime)
                    let analysisProgress = min(elapsed / max(estimatedAnalysisTime, 1), 1.0)
                    let totalProgress = analysisProgress * analysisProgressWeight

                    await MainActor.run {
                        self.currentProgress = totalProgress
                        download.transcriptionProgress = totalProgress
                    }

                    try await Task.sleep(for: .milliseconds(500))
                }
            }

            // Analyze the audio file
            if let lastSample = try await analyzer.analyzeSequence(from: audioFile) {
                try await analyzer.finalizeAndFinish(through: lastSample)
            }

            analysisProgressTask.cancel()

            let analysisEndTime = Date()
            let analysisDuration = analysisEndTime.timeIntervalSince(analysisStartTime)
            print("🎙️ ⏱️ Audio analysis completed in \(formatDuration(analysisDuration))")

            // Set progress to 10% (end of analysis phase)
            currentProgress = analysisProgressWeight
            download.transcriptionProgress = analysisProgressWeight

            // PHASE 2: Results Collection (10% - 100%)
            currentPhase = "Transcribing..."
            var finalTranscription = ""
            var processedSegments = 0
            let resultsStartTime = Date()
            var lastProgressLog = Date()

            print("🎙️ 📝 Starting results collection...")

            for try await result in transcriber.results {
                if result.isFinal {
                    finalTranscription += String(result.text.characters)
                    finalTranscription += " "
                    processedSegments += 1

                    // Calculate progress based on elapsed time vs estimated results time
                    let resultsElapsed = Date().timeIntervalSince(resultsStartTime)
                    let resultsProgress = min(resultsElapsed / max(estimatedResultsTime, 1), 1.0)
                    let totalProgress = analysisProgressWeight + (resultsProgress * (1.0 - analysisProgressWeight))

                    // Log progress every 10 seconds
                    let now = Date()
                    if now.timeIntervalSince(lastProgressLog) >= 10 {
                        let estimatedRemaining = max(estimatedResultsTime - resultsElapsed, 0)
                        print("🎙️ 📝 Progress: \(Int(totalProgress * 100))% - \(processedSegments) segments - ETA: \(formatDuration(estimatedRemaining))")
                        lastProgressLog = now
                    }

                    await MainActor.run {
                        self.currentProgress = min(totalProgress, 0.99)
                        download.transcriptionProgress = min(totalProgress, 0.99)
                    }
                }
            }

            let resultsEndTime = Date()
            let resultsDuration = resultsEndTime.timeIntervalSince(resultsStartTime)
            print("🎙️ ⏱️ Results collection completed in \(formatDuration(resultsDuration)) (\(processedSegments) segments)")

            // Clean up and finalize
            let cleanedTranscription = finalTranscription.trimmingCharacters(in: .whitespacesAndNewlines)

            // Calculate final metrics
            let transcriptionEndTime = Date()
            let totalDuration = transcriptionEndTime.timeIntervalSince(transcriptionStartTime)
            let wordCount = cleanedTranscription.split(separator: " ").count

            // Log comprehensive metrics
            print("🎙️ ✅ Transcription completed!")
            print("🎙️ ⚙️ Mode used: \(mode.displayName)")
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
            currentPhase = "Complete"

            print("🎙️ Preview: \(cleanedTranscription.prefix(100))...")

        } catch {
            let failTime = Date()
            let elapsedTime = failTime.timeIntervalSince(transcriptionStartTime)
            print("🎙️ ❌ Transcription failed after \(formatDuration(elapsedTime)): \(error)")
            download.transcriptionStatus = .failed
            download.transcriptionProgress = 0.0
            currentPhase = "Failed"
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
