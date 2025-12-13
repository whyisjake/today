//
//  ChapterGenerationService.swift
//  Today
//
//  AI-powered chapter generation from podcast transcriptions using Apple Intelligence
//

import Foundation
import SwiftData
import Combine

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Service for generating AI chapters from podcast transcriptions
@available(iOS 26.0, *)
@MainActor
final class ChapterGenerationService: ObservableObject {
    static let shared = ChapterGenerationService()

    // MARK: - Published State

    @Published var isGenerating = false
    @Published var currentProgress: Double = 0.0

    // MARK: - Private Properties

    private var modelContext: ModelContext?

    // MARK: - Initialization

    private init() {}

    func configure(with modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Public API

    /// Check if chapter generation is available (requires Apple Intelligence)
    var isAvailable: Bool {
        #if canImport(FoundationModels)
        return SystemLanguageModel.default.isAvailable
        #else
        return false
        #endif
    }

    /// Generate AI chapters from a podcast transcription
    func generateChapters(for download: PodcastDownload) async throws {
        guard let transcription = download.transcription, !transcription.isEmpty else {
            throw ChapterGenerationError.noTranscription
        }

        guard isAvailable else {
            throw ChapterGenerationError.aiNotAvailable
        }

        let audioDuration = download.article?.audioDuration ?? 0

        // Update status
        isGenerating = true
        currentProgress = 0.0
        download.chapterGenerationStatus = .inProgress

        defer {
            isGenerating = false
        }

        print("✨ Starting chapter generation...")
        print("✨ Transcription length: \(transcription.count) characters, ~\(transcription.split(separator: " ").count) words")

        do {
            #if canImport(FoundationModels)
            let chapters = try await generateChaptersWithAI(
                transcription: transcription,
                audioDuration: audioDuration
            )

            // Save chapters to download
            download.aiChapters = chapters
            download.chapterGenerationStatus = .completed
            download.chaptersGeneratedAt = Date()
            currentProgress = 1.0

            print("✨ Generated \(chapters.count) chapters")
            for chapter in chapters {
                print("  📍 \(formatTime(chapter.startTime)) - \(chapter.title)")
            }
            #else
            throw ChapterGenerationError.aiNotAvailable
            #endif
        } catch {
            print("✨ ❌ Chapter generation failed: \(error)")
            download.chapterGenerationStatus = .failed
            currentProgress = 0.0
            throw error
        }
    }

    // MARK: - AI Generation

    #if canImport(FoundationModels)
    private func generateChaptersWithAI(transcription: String, audioDuration: TimeInterval) async throws -> [AIChapterData] {
        let session = LanguageModelSession()

        // Split transcription into manageable chunks if too long
        let words = transcription.split(separator: " ")
        let wordCount = words.count

        // Estimate words per second for timestamp calculation
        let wordsPerSecond = audioDuration > 0 ? Double(wordCount) / audioDuration : 2.5

        print("✨ Words: \(wordCount), Duration: \(formatTime(audioDuration)), WPS: \(String(format: "%.2f", wordsPerSecond))")

        // For very long transcriptions, we need to chunk and process
        let maxWordsPerChunk = 3000 // ~15 minutes of content at 200 WPM
        var allChapters: [AIChapterData] = []

        if wordCount <= maxWordsPerChunk {
            // Process entire transcription at once
            currentProgress = 0.3
            let chapters = try await identifyChapters(
                text: transcription,
                startWordIndex: 0,
                totalWords: wordCount,
                wordsPerSecond: wordsPerSecond,
                session: session
            )
            allChapters = chapters
        } else {
            // Process in chunks with overlap for context
            let chunkSize = maxWordsPerChunk
            let overlap = 200 // Words of overlap between chunks
            var currentIndex = 0
            var chunkNumber = 0
            let totalChunks = (wordCount + chunkSize - overlap - 1) / (chunkSize - overlap)

            while currentIndex < wordCount {
                let endIndex = min(currentIndex + chunkSize, wordCount)
                let chunkWords = Array(words[currentIndex..<endIndex])
                let chunkText = chunkWords.joined(separator: " ")

                currentProgress = Double(chunkNumber) / Double(totalChunks) * 0.8

                let chapters = try await identifyChapters(
                    text: chunkText,
                    startWordIndex: currentIndex,
                    totalWords: wordCount,
                    wordsPerSecond: wordsPerSecond,
                    session: session
                )

                allChapters.append(contentsOf: chapters)
                chunkNumber += 1
                currentIndex += chunkSize - overlap
            }

            // Merge overlapping chapters from different chunks
            allChapters = mergeOverlappingChapters(allChapters)
        }

        currentProgress = 0.9

        // Ensure we have at least one chapter at the start
        if allChapters.isEmpty || allChapters.first?.startTime ?? 0 > 30 {
            let introChapter = AIChapterData(
                title: "Introduction",
                summary: "Episode opening",
                startTime: 0,
                keywords: []
            )
            allChapters.insert(introChapter, at: 0)
        }

        // Calculate end times based on next chapter's start
        var chaptersWithEndTimes: [AIChapterData] = []
        for (index, chapter) in allChapters.enumerated() {
            let endTime: TimeInterval?
            if index < allChapters.count - 1 {
                endTime = allChapters[index + 1].startTime
            } else {
                endTime = audioDuration
            }

            chaptersWithEndTimes.append(AIChapterData(
                id: chapter.id,
                title: chapter.title,
                summary: chapter.summary,
                startTime: chapter.startTime,
                endTime: endTime,
                keywords: chapter.keywords
            ))
        }

        return chaptersWithEndTimes
    }

    private func identifyChapters(
        text: String,
        startWordIndex: Int,
        totalWords: Int,
        wordsPerSecond: Double,
        session: LanguageModelSession
    ) async throws -> [AIChapterData] {

        let prompt = """
        Analyze this podcast transcript and identify 3-8 distinct topic segments or chapters.

        For each chapter, provide:
        1. A concise title (2-5 words)
        2. A brief summary (1 sentence)
        3. The approximate word position where it starts (as a number)
        4. 2-3 relevant keywords

        TRANSCRIPT:
        \(text.prefix(8000))

        FORMAT YOUR RESPONSE EXACTLY LIKE THIS:
        CHAPTER 1
        TITLE: [title]
        SUMMARY: [summary]
        WORD_POSITION: [number]
        KEYWORDS: [keyword1], [keyword2], [keyword3]

        CHAPTER 2
        TITLE: [title]
        ...

        Focus on identifying clear topic shifts, new subjects, or segment transitions.
        Word positions should be relative to the start of this transcript (starting at 0).
        """

        let response = try await session.respond(to: prompt)
        let content = response.content

        // Parse the response
        var chapters: [AIChapterData] = []
        let chapterBlocks = content.components(separatedBy: "CHAPTER")

        for block in chapterBlocks where !block.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if let chapter = parseChapterBlock(
                block,
                startWordIndex: startWordIndex,
                totalWords: totalWords,
                wordsPerSecond: wordsPerSecond
            ) {
                chapters.append(chapter)
            }
        }

        return chapters.sorted { $0.startTime < $1.startTime }
    }

    private func parseChapterBlock(
        _ block: String,
        startWordIndex: Int,
        totalWords: Int,
        wordsPerSecond: Double
    ) -> AIChapterData? {
        var title = ""
        var summary = ""
        var wordPosition = 0
        var keywords: [String] = []

        let lines = block.components(separatedBy: "\n")

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.uppercased().hasPrefix("TITLE:") {
                title = trimmed.replacingOccurrences(of: "TITLE:", with: "", options: .caseInsensitive)
                    .trimmingCharacters(in: .whitespaces)
                    .replacingOccurrences(of: "**", with: "")
            } else if trimmed.uppercased().hasPrefix("SUMMARY:") {
                summary = trimmed.replacingOccurrences(of: "SUMMARY:", with: "", options: .caseInsensitive)
                    .trimmingCharacters(in: .whitespaces)
            } else if trimmed.uppercased().hasPrefix("WORD_POSITION:") {
                let posStr = trimmed.replacingOccurrences(of: "WORD_POSITION:", with: "", options: .caseInsensitive)
                    .trimmingCharacters(in: .whitespaces)
                    .components(separatedBy: CharacterSet.decimalDigits.inverted)
                    .joined()
                wordPosition = Int(posStr) ?? 0
            } else if trimmed.uppercased().hasPrefix("KEYWORDS:") {
                let keywordStr = trimmed.replacingOccurrences(of: "KEYWORDS:", with: "", options: .caseInsensitive)
                    .trimmingCharacters(in: .whitespaces)
                keywords = keywordStr.components(separatedBy: ",").map {
                    $0.trimmingCharacters(in: .whitespaces)
                }
            }
        }

        guard !title.isEmpty else { return nil }

        // Calculate timestamp from word position
        let absoluteWordPosition = startWordIndex + wordPosition
        let startTime = Double(absoluteWordPosition) / wordsPerSecond

        return AIChapterData(
            title: title,
            summary: summary.isEmpty ? "Chapter segment" : summary,
            startTime: startTime,
            keywords: keywords
        )
    }

    private func mergeOverlappingChapters(_ chapters: [AIChapterData]) -> [AIChapterData] {
        guard chapters.count > 1 else { return chapters }

        var merged: [AIChapterData] = []
        let sorted = chapters.sorted { $0.startTime < $1.startTime }

        for chapter in sorted {
            // Check if this chapter is too close to the previous one (within 30 seconds)
            if let last = merged.last, chapter.startTime - last.startTime < 30 {
                // Skip if titles are similar or keep the one with more keywords
                if chapter.keywords.count <= last.keywords.count {
                    continue
                } else {
                    // Replace with the better chapter
                    merged.removeLast()
                }
            }
            merged.append(chapter)
        }

        return merged
    }
    #endif

    // MARK: - Helpers

    private func formatTime(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

// MARK: - Errors

enum ChapterGenerationError: LocalizedError {
    case noTranscription
    case aiNotAvailable
    case generationFailed
    case parsingFailed

    var errorDescription: String? {
        switch self {
        case .noTranscription:
            return "No transcription available. Transcribe the episode first."
        case .aiNotAvailable:
            return "Apple Intelligence is not available on this device."
        case .generationFailed:
            return "Failed to generate chapters."
        case .parsingFailed:
            return "Failed to parse AI response."
        }
    }
}
