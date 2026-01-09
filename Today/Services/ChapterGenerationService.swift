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
        let wordCount = transcription.split(separator: " ").count
        let startTime = Date()

        // Update status
        isGenerating = true
        currentProgress = 0.0
        download.chapterGenerationStatus = .inProgress

        defer {
            isGenerating = false
        }

        print("✨ ════════════════════════════════════════════════")
        print("✨ CHAPTER GENERATION STARTED")
        print("✨ ════════════════════════════════════════════════")
        print("✨ Article: \(download.article?.title ?? "Unknown")")
        print("✨ Transcription: \(transcription.count) characters, ~\(wordCount) words")
        print("✨ Audio duration: \(formatTime(audioDuration))")
        print("✨ Started at: \(startTime.formatted(date: .omitted, time: .standard))")

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

            let endTime = Date()
            let totalDuration = endTime.timeIntervalSince(startTime)

            print("✨ ════════════════════════════════════════════════")
            print("✨ GENERATION COMPLETE")
            print("✨ ════════════════════════════════════════════════")
            print("✨ Generated \(chapters.count) chapters")
            print("✨ ⏱️ Total generation time: \(formatDuration(totalDuration))")
            print("✨ ════════════════════════════════════════════════")
            #else
            throw ChapterGenerationError.aiNotAvailable
            #endif
        } catch {
            let endTime = Date()
            let elapsedTime = endTime.timeIntervalSince(startTime)
            print("✨ ❌ Chapter generation failed after \(formatDuration(elapsedTime)): \(error)")
            download.chapterGenerationStatus = .failed
            currentProgress = 0.0
            throw error
        }
    }

    // MARK: - AI Chapter Generation

    #if canImport(FoundationModels)
    private func generateChaptersWithAI(transcription: String, audioDuration: TimeInterval) async throws -> [AIChapterData] {
        let startTime = Date()

        let words = transcription.split(separator: " ")
        let wordCount = words.count
        let wordsPerSecond = audioDuration > 0 ? Double(wordCount) / audioDuration : 2.5

        print("✨ Words: \(wordCount), Duration: \(formatTime(audioDuration)), WPS: \(String(format: "%.2f", wordsPerSecond))")
        print("✨ Analyzing content to find natural chapter breaks...")

        // For long transcripts, we need to chunk - but keep chunks large enough for context
        // Apple Intelligence can handle ~4000 tokens, roughly 3000 words
        let maxWordsPerChunk = 2500
        var allChapterSuggestions: [(title: String, summary: String, keywords: [String], startPhrase: String, chunkOffset: Int)] = []

        if wordCount <= maxWordsPerChunk {
            // Single chunk - analyze the whole thing
            let suggestions = try await analyzeChunkForChapters(
                text: transcription,
                words: words,
                chunkOffset: 0,
                audioDuration: audioDuration,
                wordsPerSecond: wordsPerSecond
            )
            allChapterSuggestions.append(contentsOf: suggestions)
        } else {
            // Multiple chunks with overlap
            let overlap = 200 // Words of overlap between chunks
            var chunkStart = 0

            while chunkStart < wordCount {
                let chunkEnd = min(chunkStart + maxWordsPerChunk, wordCount)
                let chunkWords = Array(words[chunkStart..<chunkEnd])
                let chunkText = chunkWords.joined(separator: " ")

                let chunkStartTime = Double(chunkStart) / wordsPerSecond
                let chunkEndTime = Double(chunkEnd) / wordsPerSecond
                print("\n✨ Analyzing chunk: \(formatTime(chunkStartTime)) - \(formatTime(chunkEndTime))")

                let suggestions = try await analyzeChunkForChapters(
                    text: chunkText,
                    words: chunkWords,
                    chunkOffset: chunkStart,
                    audioDuration: audioDuration,
                    wordsPerSecond: wordsPerSecond
                )
                allChapterSuggestions.append(contentsOf: suggestions)

                // Move to next chunk
                chunkStart = chunkEnd - overlap
                if chunkEnd >= wordCount { break }

                currentProgress = Double(chunkStart) / Double(wordCount) * 0.7
            }
        }

        print("\n✨ Found \(allChapterSuggestions.count) potential chapters")

        // Convert suggestions to chapters with precise timestamps
        var chapters: [AIChapterData] = []

        for suggestion in allChapterSuggestions {
            // Find the exact word position using the start phrase
            // Only include chapters where we can find the exact phrase
            guard !suggestion.startPhrase.isEmpty else {
                print("✨ Skipping '\(suggestion.title)' - no start phrase provided")
                continue
            }

            guard let phraseIndex = findPhraseWordIndex(phrase: suggestion.startPhrase, in: words, startingFrom: max(0, suggestion.chunkOffset - 100)) else {
                print("✨ Skipping '\(suggestion.title)' - phrase not found: \"\(suggestion.startPhrase)\"")
                continue
            }

            let startTime = Double(phraseIndex) / wordsPerSecond
            print("✨ Found '\(suggestion.title)' at \(formatTime(startTime))")

            chapters.append(AIChapterData(
                title: suggestion.title,
                summary: suggestion.summary,
                startTime: startTime,
                keywords: suggestion.keywords,
                isAd: false
            ))
        }

        // Sort and deduplicate chapters that are too close together
        chapters.sort { $0.startTime < $1.startTime }
        chapters = deduplicateChapters(chapters, minGap: 120) // At least 2 minutes between chapters

        // Calculate end times based on next chapter's start
        var chaptersWithEndTimes: [AIChapterData] = []
        for (index, chapter) in chapters.enumerated() {
            let endTime: TimeInterval
            if index < chapters.count - 1 {
                endTime = chapters[index + 1].startTime
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
                isAd: false
            ))
        }

        // Final timing
        let endTime = Date()
        let totalDuration = endTime.timeIntervalSince(startTime)

        print("\n✨ ════════════════════════════════════════════════")
        print("✨ CHAPTER GENERATION COMPLETE")
        print("✨ ════════════════════════════════════════════════")
        print("✨ Generated \(chaptersWithEndTimes.count) chapters:")
        for chapter in chaptersWithEndTimes {
            let endStr = chapter.endTime.map { formatTime($0) } ?? "?"
            print("  📍 \(formatTime(chapter.startTime))-\(endStr): \(chapter.title)")
        }
        print("")
        print("✨ ⏱️ Total time: \(formatDuration(totalDuration))")
        print("✨ ════════════════════════════════════════════════\n")

        return chaptersWithEndTimes
    }

    /// Analyze a chunk of transcript and identify natural chapter breaks
    private func analyzeChunkForChapters(
        text: String,
        words: [String.SubSequence],
        chunkOffset: Int,
        audioDuration: TimeInterval,
        wordsPerSecond: Double
    ) async throws -> [(title: String, summary: String, keywords: [String], startPhrase: String, chunkOffset: Int)] {

        let session = LanguageModelSession()

        let prompt = """
        Analyze this podcast transcript and identify the MAJOR TOPIC CHANGES.
        Find where the discussion shifts to a new subject or segment.

        TRANSCRIPT:
        \(text)

        For each major topic/segment you identify, return a block like this:
        ---
        TITLE: [2-5 word chapter title]
        SUMMARY: [One sentence description]
        KEYWORDS: [2-3 keywords]
        START_PHRASE: [Exact 4-6 word phrase where this topic BEGINS]
        ---

        Rules:
        - Only identify 3-6 major topic changes (not every minor point)
        - START_PHRASE must be EXACT words from the transcript
        - Focus on significant topic shifts, not small tangents
        - Titles should be specific and descriptive
        - Skip sponsor reads and ads
        """

        let response = try await session.respond(to: prompt)
        let content = response.content

        print("✨ AI identified topics:")
        print("────────────────────────────────────────")
        print(content)
        print("────────────────────────────────────────")

        // Parse the response into chapter suggestions
        // Handle multiple AI response formats: --- delimited, numbered lists, etc.
        var suggestions: [(title: String, summary: String, keywords: [String], startPhrase: String, chunkOffset: Int)] = []

        // Strategy: Find all START_PHRASE occurrences and work backwards to find associated fields
        let lines = content.components(separatedBy: "\n")
        var currentTitle = ""
        var currentSummary = ""
        var currentKeywords: [String] = []

        for line in lines {
            // Clean line: strip markdown formatting for reliable field detection
            let cleaned = stripMarkdown(line)

            // Check for title - can be "TITLE:" or detected from context
            if cleaned.uppercased().hasPrefix("TITLE:") {
                currentTitle = stripMarkdown(cleaned.replacingOccurrences(of: "TITLE:", with: "", options: .caseInsensitive))
                    .trimmingCharacters(in: CharacterSet(charactersIn: " \""))
            } else if !cleaned.contains(":") && cleaned.count < 60 && cleaned.count > 3 {
                // Could be a standalone title line (short, no field label)
                let potential = cleaned.trimmingCharacters(in: CharacterSet(charactersIn: " \""))
                if !potential.lowercased().contains("summary") &&
                   !potential.lowercased().contains("keyword") &&
                   !potential.lowercased().contains("start_phrase") &&
                   !potential.lowercased().hasPrefix("---") {
                    // Only set as title if we don't have one yet for this chapter
                    if currentTitle.isEmpty {
                        currentTitle = potential
                    }
                }
            }

            // Check for summary
            if cleaned.uppercased().hasPrefix("SUMMARY:") || cleaned.uppercased().hasPrefix("SUMMARY ") {
                currentSummary = stripMarkdown(cleaned.replacingOccurrences(of: "SUMMARY:", with: "", options: .caseInsensitive)
                    .replacingOccurrences(of: "Summary ", with: "", options: .caseInsensitive))
                    .trimmingCharacters(in: CharacterSet(charactersIn: " \""))
            }

            // Check for keywords
            if cleaned.uppercased().hasPrefix("KEYWORDS:") || cleaned.uppercased().hasPrefix("KEYWORDS ") {
                let kw = cleaned.replacingOccurrences(of: "KEYWORDS:", with: "", options: .caseInsensitive)
                    .replacingOccurrences(of: "Keywords ", with: "", options: .caseInsensitive)
                currentKeywords = kw.components(separatedBy: ",").map {
                    stripMarkdown($0).trimmingCharacters(in: CharacterSet(charactersIn: " \""))
                }.filter { !$0.isEmpty }
            }

            // Check for start phrase - this triggers saving the chapter
            if cleaned.uppercased().hasPrefix("START_PHRASE:") || cleaned.uppercased().hasPrefix("START_PHRASE ") {
                let startPhrase = stripMarkdown(cleaned.replacingOccurrences(of: "START_PHRASE:", with: "", options: .caseInsensitive)
                    .replacingOccurrences(of: "START_PHRASE ", with: "", options: .caseInsensitive))
                    .trimmingCharacters(in: CharacterSet(charactersIn: " \""))

                if !currentTitle.isEmpty && !startPhrase.isEmpty {
                    suggestions.append((
                        title: currentTitle,
                        summary: currentSummary.isEmpty ? "Chapter segment" : currentSummary,
                        keywords: currentKeywords,
                        startPhrase: startPhrase,
                        chunkOffset: chunkOffset
                    ))
                    print("✨ Parsed chapter: '\(currentTitle)' -> '\(startPhrase.prefix(40))...'")
                }

                // Reset for next chapter
                currentTitle = ""
                currentSummary = ""
                currentKeywords = []
            }
        }

        return suggestions
    }

    /// Strip common markdown formatting from text
    private func stripMarkdown(_ text: String) -> String {
        var result = text

        // Remove bold/italic markers: **text**, __text__, *text*, _text_
        // Process double markers first to avoid leaving singles behind
        result = result.replacingOccurrences(of: "**", with: "")
        result = result.replacingOccurrences(of: "__", with: "")
        result = result.replacingOccurrences(of: "*", with: "")
        // Don't strip underscores from middle of words (like START_PHRASE)
        // Only strip leading/trailing underscores used for emphasis
        if result.hasPrefix("_") { result = String(result.dropFirst()) }
        if result.hasSuffix("_") { result = String(result.dropLast()) }

        // Remove inline code markers: `text`
        result = result.replacingOccurrences(of: "`", with: "")

        // Remove markdown link syntax: [text](url) -> text
        let linkPattern = #"\[([^\]]+)\]\([^)]+\)"#
        if let regex = try? NSRegularExpression(pattern: linkPattern, options: []) {
            result = regex.stringByReplacingMatches(
                in: result,
                options: [],
                range: NSRange(result.startIndex..., in: result),
                withTemplate: "$1"
            )
        }

        // Remove leading markdown header markers: ### text -> text
        let headerPattern = #"^#{1,6}\s*"#
        if let regex = try? NSRegularExpression(pattern: headerPattern, options: []) {
            result = regex.stringByReplacingMatches(
                in: result,
                options: [],
                range: NSRange(result.startIndex..., in: result),
                withTemplate: ""
            )
        }

        // Remove leading list markers: - item, * item, + item, 1. item
        let listPattern = #"^[\-\*\+]\s+|^\d+\.\s+"#
        if let regex = try? NSRegularExpression(pattern: listPattern, options: []) {
            result = regex.stringByReplacingMatches(
                in: result,
                options: [],
                range: NSRange(result.startIndex..., in: result),
                withTemplate: ""
            )
        }

        return result.trimmingCharacters(in: .whitespaces)
    }

    /// Remove chapters that are too close together, keeping the first one
    private func deduplicateChapters(_ chapters: [AIChapterData], minGap: TimeInterval) -> [AIChapterData] {
        guard !chapters.isEmpty else { return chapters }

        var result: [AIChapterData] = [chapters[0]]

        for chapter in chapters.dropFirst() {
            if let lastChapter = result.last,
               chapter.startTime - lastChapter.startTime >= minGap {
                result.append(chapter)
            } else {
                print("✨ Skipping duplicate chapter '\(chapter.title)' (too close to previous)")
            }
        }

        return result
    }

    /// Find the word index of a phrase in the transcript
    private func findPhraseWordIndex(phrase: String, in words: [String.SubSequence], startingFrom: Int = 0) -> Int? {
        let phraseWords = phrase.lowercased().split(separator: " ")
        guard phraseWords.count >= 2 else { return nil }

        // Only use first few words to increase match likelihood
        let searchWords = Array(phraseWords.prefix(4))

        for i in startingFrom..<(words.count - searchWords.count + 1) {
            var matches = true
            for (j, phraseWord) in searchWords.enumerated() {
                let word = words[i + j].lowercased()
                // Strip punctuation for comparison
                let cleanWord = word.trimmingCharacters(in: .punctuationCharacters)
                let cleanPhrase = String(phraseWord).trimmingCharacters(in: .punctuationCharacters)
                if cleanWord != cleanPhrase {
                    matches = false
                    break
                }
            }
            if matches {
                return i
            }
        }
        return nil
    }
    #endif

    // MARK: - Helpers

    private func formatTime(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }

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
