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

            let contentChapters = chapters.filter { !$0.isAd }
            let adChapters = chapters.filter { $0.isAd }
            print("✨ Generated \(chapters.count) chapters (\(contentChapters.count) content, \(adChapters.count) ads)")
            for chapter in chapters {
                let adIcon = chapter.isAd ? "📢" : "📍"
                print("  \(adIcon) \(formatTime(chapter.startTime)) - \(chapter.title)")
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
        // Note: We create a NEW session for each chunk because context is cumulative
        // Each prompt+response adds to the running token count until session is reset

        // Split transcription into manageable chunks if too long
        let words = transcription.split(separator: " ")
        let wordCount = words.count

        // Estimate words per second for timestamp calculation
        let wordsPerSecond = audioDuration > 0 ? Double(wordCount) / audioDuration : 2.5

        print("✨ Words: \(wordCount), Duration: \(formatTime(audioDuration)), WPS: \(String(format: "%.2f", wordsPerSecond))")

        // For very long transcriptions, we need to chunk and process
        // Apple Intelligence has a 4096 token limit, so keep chunks small
        let maxWordsPerChunk = 1200 // ~6 minutes of content at 200 WPM
        var allChapters: [AIChapterData] = []

        if wordCount <= maxWordsPerChunk {
            // Process entire transcription at once
            currentProgress = 0.3
            let chapters = try await identifyChapters(
                text: transcription,
                startWordIndex: 0,
                totalWords: wordCount,
                wordsPerSecond: wordsPerSecond
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

                print("✨ Processing chunk \(chunkNumber + 1)/\(totalChunks)...")

                let chapters = try await identifyChapters(
                    text: chunkText,
                    startWordIndex: currentIndex,
                    totalWords: wordCount,
                    wordsPerSecond: wordsPerSecond
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
                keywords: [],
                isAd: false
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
                keywords: chapter.keywords,
                isAd: chapter.isAd
            ))
        }

        return chaptersWithEndTimes
    }

    /// Estimate token count for a string
    /// Apple Intelligence: 1 token ≈ 3-4 characters (using 3 to be safe)
    private func estimateTokens(_ text: String) -> Int {
        return (text.count + 2) / 3  // Round up: chars / 3
    }

    private func identifyChapters(
        text: String,
        startWordIndex: Int,
        totalWords: Int,
        wordsPerSecond: Double
    ) async throws -> [AIChapterData] {

        // Create a FRESH session for each call - context is cumulative within a session
        let session = LanguageModelSession()

        let promptTemplate = """
        Analyze this podcast transcript. Identify ONLY major topic changes (3-5 chapters max).
        Also flag any advertisements or sponsor reads.

        For each segment:
        CHAPTER N
        TYPE: content OR ad
        TITLE: 2-5 word title
        SUMMARY: one sentence
        WORD_POSITION: number (word count from start)
        KEYWORDS: 2-3 words

        Rules:
        - Only create chapters for MAJOR topic shifts, not minor transitions
        - Mark sponsor reads, product promotions, promo codes as TYPE: ad
        - Prefer fewer, broader chapters over many small ones

        TRANSCRIPT:
        """

        // Calculate how much text we can fit
        let maxTokens = 4096
        let responseBuffer = 800  // Reserve tokens for AI response
        let promptTokens = estimateTokens(promptTemplate)
        let availableTokens = maxTokens - responseBuffer - promptTokens

        // Convert available tokens to character limit (1 token ≈ 3 chars)
        let maxChars = availableTokens * 3

        // Truncate text to fit
        let truncatedText = String(text.prefix(maxChars))

        // Log token estimation
        let estimatedTotal = promptTokens + estimateTokens(truncatedText)
        print("✨ Token estimate: ~\(estimatedTotal) (prompt: \(promptTokens), text: \(estimateTokens(truncatedText)), max: \(maxTokens - responseBuffer))")

        let prompt = promptTemplate + truncatedText

        let response = try await session.respond(to: prompt)
        let content = response.content

        // Debug: log the AI response
        print("✨ AI Response (\(content.count) chars):")
        print(content.prefix(500))
        if content.count > 500 {
            print("... (truncated)")
        }

        // Parse the response
        var chapters: [AIChapterData] = []
        let chapterBlocks = content.components(separatedBy: "CHAPTER")

        print("✨ Found \(chapterBlocks.count) chapter blocks")

        for (index, block) in chapterBlocks.enumerated() where !block.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if let chapter = parseChapterBlock(
                block,
                startWordIndex: startWordIndex,
                totalWords: totalWords,
                wordsPerSecond: wordsPerSecond,
                chunkIndex: index  // Pass index for fallback positioning
            ) {
                print("✨ Parsed chapter: \(chapter.title) @ word \(Int(chapter.startTime * wordsPerSecond))")
                chapters.append(chapter)
            } else {
                // Debug: show first 100 chars of block that failed to parse
                let preview = block.prefix(100).replacingOccurrences(of: "\n", with: " ")
                print("✨ Failed to parse block \(index): \(preview)...")
            }
        }

        return chapters.sorted { $0.startTime < $1.startTime }
    }

    private func parseChapterBlock(
        _ block: String,
        startWordIndex: Int,
        totalWords: Int,
        wordsPerSecond: Double,
        chunkIndex: Int = 0
    ) -> AIChapterData? {
        var title = ""
        var summary = ""
        var wordPosition: Int? = nil  // nil means we'll use fallback
        var keywords: [String] = []
        var isAd = false

        let lines = block.components(separatedBy: "\n")

        for line in lines {
            // Strip markdown formatting and bullet points before parsing
            var cleaned = line
                .trimmingCharacters(in: .whitespaces)
                .replacingOccurrences(of: "**", with: "")
                .replacingOccurrences(of: "###", with: "")
                .replacingOccurrences(of: "##", with: "")
                .replacingOccurrences(of: "#", with: "")
                .trimmingCharacters(in: .whitespaces)

            // Remove leading bullet points (-, *, •)
            while cleaned.hasPrefix("-") || cleaned.hasPrefix("*") || cleaned.hasPrefix("•") {
                cleaned = String(cleaned.dropFirst()).trimmingCharacters(in: .whitespaces)
            }

            // Check for TYPE (ad vs content)
            if cleaned.uppercased().hasPrefix("TYPE:") {
                let typeStr = cleaned.replacingOccurrences(of: "TYPE:", with: "", options: .caseInsensitive)
                    .trimmingCharacters(in: .whitespaces)
                    .lowercased()
                isAd = typeStr.contains("ad") || typeStr.contains("sponsor") || typeStr.contains("promo")
            }
            // Check for title in various formats
            else if cleaned.uppercased().hasPrefix("TITLE:") {
                title = cleaned.replacingOccurrences(of: "TITLE:", with: "", options: .caseInsensitive)
                    .trimmingCharacters(in: .whitespaces)
                    .replacingOccurrences(of: "\"", with: "")
            }
            // Handle "1: Title Name" format from chapter header
            else if title.isEmpty, let colonRange = cleaned.range(of: ":"),
                    cleaned.prefix(upTo: colonRange.lowerBound).allSatisfy({ $0.isNumber || $0.isWhitespace }) {
                title = String(cleaned.suffix(from: colonRange.upperBound))
                    .trimmingCharacters(in: .whitespaces)
            }
            // Summary
            else if cleaned.uppercased().hasPrefix("SUMMARY:") {
                summary = cleaned.replacingOccurrences(of: "SUMMARY:", with: "", options: .caseInsensitive)
                    .trimmingCharacters(in: .whitespaces)
            }
            // Word position - extract first number
            else if cleaned.uppercased().hasPrefix("WORD_POSITION:") {
                let posStr = cleaned.replacingOccurrences(of: "WORD_POSITION:", with: "", options: .caseInsensitive)
                    .trimmingCharacters(in: .whitespaces)
                // Extract just the first number (handles "22 (from start)" or "0-140" formats)
                if let firstNumber = posStr.components(separatedBy: CharacterSet.decimalDigits.inverted)
                    .first(where: { !$0.isEmpty }),
                   let pos = Int(firstNumber) {
                    wordPosition = pos
                }
            }
            // Keywords
            else if cleaned.uppercased().hasPrefix("KEYWORDS:") {
                let keywordStr = cleaned.replacingOccurrences(of: "KEYWORDS:", with: "", options: .caseInsensitive)
                    .trimmingCharacters(in: .whitespaces)
                keywords = keywordStr.components(separatedBy: ",").map {
                    $0.trimmingCharacters(in: .whitespaces)
                        .replacingOccurrences(of: "\"", with: "")
                }
            }
        }

        guard !title.isEmpty else { return nil }

        // Calculate timestamp from word position
        // Use parsed position if available, otherwise use chunk index as fallback
        let effectiveWordPosition = wordPosition ?? (chunkIndex * 50)  // ~10 sec spacing fallback
        let absoluteWordPosition = startWordIndex + effectiveWordPosition
        let startTime = Double(absoluteWordPosition) / wordsPerSecond

        return AIChapterData(
            title: title,
            summary: summary.isEmpty ? (isAd ? "Advertisement" : "Chapter segment") : summary,
            startTime: startTime,
            keywords: keywords,
            isAd: isAd
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
