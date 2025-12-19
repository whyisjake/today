//
//  PodcastDownloadControls.swift
//  Today
//
//  Download, transcription, and chapter generation controls for podcast episodes
//

import SwiftUI
import SwiftData
import NaturalLanguage

struct PodcastDownloadControls: View {
    let article: Article
    @Environment(\.modelContext) private var modelContext
    @StateObject private var downloadManager = PodcastDownloadManager.shared
    @AppStorage("accentColor") private var accentColor: AccentColorOption = .orange
    @State private var transcriptionError: String?
    @State private var showingTranscriptionError = false
    @State private var isTranscribing = false
    @State private var transcriptionProgress: Double = 0.0
    @State private var chapterError: String?
    @State private var showingChapterError = false
    @State private var isGeneratingChapters = false
    @State private var chapterProgress: Double = 0.0

    // Transcription mode selection (stored as string for iOS version compatibility)
    @State private var selectedTranscriptionModeRaw: String = "accurate"

    // Timer for polling progress during operations
    @State private var progressTimer: Timer?

    var body: some View {
        VStack(spacing: 12) {
            // Download section
            downloadSection

            // Transcription section (only if downloaded and iOS 26+)
            if #available(iOS 26.0, *) {
                if let download = article.podcastDownload,
                   download.downloadStatus == .completed {
                    transcriptionSection(download: download)
                }

                // Chapter generation section (only if transcribed)
                if let download = article.podcastDownload,
                   download.transcriptionStatus == .completed {
                    chapterSection(download: download)
                }
            }
        }
        .onAppear {
            downloadManager.configure(with: modelContext)
            if #available(iOS 26.0, *) {
                TranscriptionService.shared.configure(with: modelContext)
                ChapterGenerationService.shared.configure(with: modelContext)
            }
        }
        .alert("Transcription Error", isPresented: $showingTranscriptionError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(transcriptionError ?? "An unknown error occurred")
        }
        .alert("Chapter Generation Error", isPresented: $showingChapterError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(chapterError ?? "An unknown error occurred")
        }
    }

    // MARK: - Download Section

    @ViewBuilder
    private var downloadSection: some View {
        if let download = article.podcastDownload {
            switch download.downloadStatus {
            case .notStarted:
                downloadButton

            case .downloading:
                downloadingView(progress: downloadManager.downloadProgress[article.audioUrl ?? ""] ?? download.downloadProgress)

            case .paused:
                pausedView

            case .completed:
                downloadedView(download: download)

            case .failed:
                failedView
            }
        } else {
            downloadButton
        }
    }

    private var downloadButton: some View {
        Button {
            Task {
                try? await downloadManager.downloadEpisode(for: article)
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "arrow.down.circle")
                Text("Download Episode")
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color.accentColor)
            .cornerRadius(10)
        }
    }

    private func downloadingView(progress: Double) -> some View {
        VStack(spacing: 8) {
            HStack {
                Text("Downloading...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(progress * 100))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: progress)
                .tint(.accentColor)

            HStack(spacing: 12) {
                Button {
                    downloadManager.pauseDownload(for: article)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "pause.circle")
                        Text("Pause")
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }

                Button {
                    downloadManager.cancelDownload(for: article)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "xmark.circle")
                        Text("Cancel")
                    }
                    .font(.subheadline)
                    .foregroundStyle(.red)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }

    private var pausedView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Download Paused")
                    .font(.subheadline.weight(.medium))
                if let progress = article.podcastDownload?.downloadProgress {
                    Text("\(Int(progress * 100))% complete")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button {
                downloadManager.resumeDownload(for: article)
            } label: {
                Image(systemName: "play.circle.fill")
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
            }

            Button {
                downloadManager.cancelDownload(for: article)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }

    private func downloadedView(download: PodcastDownload) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Downloaded")
                        .font(.subheadline.weight(.medium))
                }

                if let fileSize = download.fileSize {
                    Text(ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button {
                downloadManager.deleteDownload(for: download)
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
                    .padding(8)
                    .background(Color(.systemGray5))
                    .cornerRadius(8)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }

    private var failedView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(.red)
                    Text("Download Failed")
                        .font(.subheadline.weight(.medium))
                }
            }

            Spacer()

            Button {
                Task {
                    try? await downloadManager.downloadEpisode(for: article)
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.clockwise")
                    Text("Retry")
                }
                .font(.subheadline)
                .foregroundStyle(Color.accentColor)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }

    // MARK: - Transcription Section

    @available(iOS 26.0, *)
    @ViewBuilder
    private func transcriptionSection(download: PodcastDownload) -> some View {
        switch download.transcriptionStatus {
        case .notStarted:
            transcribeButton(download: download)

        case .inProgress:
            transcribingView(progress: transcriptionProgress > 0 ? transcriptionProgress : download.transcriptionProgress)

        case .completed:
            transcribedView(download: download)

        case .failed:
            transcriptionFailedView(download: download)
        }
    }

    @available(iOS 26.0, *)
    private func transcribeButton(download: PodcastDownload) -> some View {
        let selectedMode = TranscriptionMode(rawValue: selectedTranscriptionModeRaw) ?? .accurate

        return VStack(spacing: 8) {
            // Mode selector
            HStack {
                Text("Mode:")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker("Mode", selection: $selectedTranscriptionModeRaw) {
                    Text("Accurate").tag("accurate")
                    Text("Fast").tag("fast")
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 200)

                Spacer()
            }
            .padding(.horizontal, 4)

            Button {
                Task {
                    isTranscribing = true
                    transcriptionProgress = 0.0
                    startProgressPolling(for: .transcription)
                    do {
                        try await TranscriptionService.shared.transcribe(download: download, mode: selectedMode)
                    } catch {
                        transcriptionError = error.localizedDescription
                        showingTranscriptionError = true
                    }
                    stopProgressPolling()
                    isTranscribing = false
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "waveform")
                    Text("Transcribe Episode")
                    if selectedMode == .fast {
                        Text("(Fast)")
                            .font(.caption)
                    }
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.accentColor)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.accentColor.opacity(0.1))
                .cornerRadius(10)
            }
        }
    }

    @available(iOS 26.0, *)
    private func transcribingView(progress: Double) -> some View {
        let phase = TranscriptionService.shared.currentPhase

        return VStack(spacing: 8) {
            HStack {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.8)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Transcribing...")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if !phase.isEmpty {
                            Text(phase)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                Spacer()
                if progress > 0 {
                    Text("\(Int(progress * 100))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                // Cancel button - allows resetting hung transcriptions
                Button {
                    resetTranscription()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }

            if progress > 0 {
                ProgressView(value: progress)
                    .tint(.accentColor)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }

    private func resetTranscription() {
        // Cancel ongoing transcription in the service
        if #available(iOS 26.0, *) {
            TranscriptionService.shared.cancelTranscription()
        }

        // Reset the download's transcription status
        if let download = article.podcastDownload {
            download.resetTranscription()
        }

        isTranscribing = false
        transcriptionProgress = 0.0
        print("🎙️ Transcription reset by user")
    }

    private func transcribedView(download: PodcastDownload) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Transcribed")
                        .font(.subheadline.weight(.medium))
                }

                if let transcription = download.transcription {
                    Text("\(transcription.split(separator: " ").count) words")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            NavigationLink {
                TranscriptionView(download: download)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "doc.text")
                    Text("View")
                }
                .font(.subheadline)
                .foregroundStyle(Color.accentColor)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }

    @available(iOS 26.0, *)
    private func transcriptionFailedView(download: PodcastDownload) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(.red)
                    Text("Transcription Failed")
                        .font(.subheadline.weight(.medium))
                }
            }

            Spacer()

            Button {
                Task {
                    isTranscribing = true
                    transcriptionProgress = 0.0
                    startProgressPolling(for: .transcription)
                    do {
                        try await TranscriptionService.shared.transcribe(download: download)
                    } catch {
                        transcriptionError = error.localizedDescription
                        showingTranscriptionError = true
                    }
                    stopProgressPolling()
                    isTranscribing = false
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.clockwise")
                    Text("Retry")
                }
                .font(.subheadline)
                .foregroundStyle(Color.accentColor)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }

    // MARK: - Chapter Section

    @available(iOS 26.0, *)
    @ViewBuilder
    private func chapterSection(download: PodcastDownload) -> some View {
        switch download.chapterGenerationStatus {
        case .notStarted:
            generateChaptersButton(download: download)

        case .inProgress:
            generatingChaptersView

        case .completed:
            chaptersGeneratedView(download: download)

        case .failed:
            chapterGenerationFailedView(download: download)
        }
    }

    @available(iOS 26.0, *)
    private func generateChaptersButton(download: PodcastDownload) -> some View {
        Button {
            Task {
                isGeneratingChapters = true
                chapterProgress = 0.0
                startProgressPolling(for: .chapterGeneration)
                do {
                    try await ChapterGenerationService.shared.generateChapters(for: download)
                } catch {
                    chapterError = error.localizedDescription
                    showingChapterError = true
                }
                stopProgressPolling()
                isGeneratingChapters = false
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                Text("Generate AI Chapters")
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(accentColor.color)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(accentColor.color.opacity(0.1))
            .cornerRadius(10)
        }
        .disabled(!ChapterGenerationService.shared.isAvailable)
    }

    private var generatingChaptersView: some View {
        VStack(spacing: 8) {
            HStack {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Generating chapters...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if chapterProgress > 0 {
                    Text("\(Int(chapterProgress * 100))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            if chapterProgress > 0 {
                ProgressView(value: chapterProgress)
                    .tint(.accentColor)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }

    private func chaptersGeneratedView(download: PodcastDownload) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("AI Chapters Ready")
                        .font(.subheadline.weight(.medium))
                }

                if let chapters = download.aiChapters {
                    Text("\(chapters.count) chapters")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            HStack(spacing: 12) {
                // Regenerate button
                Button {
                    download.resetChapterGeneration()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                // View chapters
                NavigationLink {
                    FullChapterListView(download: download)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "list.bullet")
                        Text("View")
                    }
                    .font(.subheadline)
                    .foregroundStyle(accentColor.color)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }

    @available(iOS 26.0, *)
    private func chapterGenerationFailedView(download: PodcastDownload) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(.red)
                    Text("Chapter Generation Failed")
                        .font(.subheadline.weight(.medium))
                }
            }

            Spacer()

            Button {
                Task {
                    isGeneratingChapters = true
                    chapterProgress = 0.0
                    download.resetChapterGeneration()
                    startProgressPolling(for: .chapterGeneration)
                    do {
                        try await ChapterGenerationService.shared.generateChapters(for: download)
                    } catch {
                        chapterError = error.localizedDescription
                        showingChapterError = true
                    }
                    stopProgressPolling()
                    isGeneratingChapters = false
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.clockwise")
                    Text("Retry")
                }
                .font(.subheadline)
                .foregroundStyle(Color.accentColor)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }

    // MARK: - Progress Polling

    private enum ProgressType {
        case transcription
        case chapterGeneration
    }

    @available(iOS 26.0, *)
    private func startProgressPolling(for type: ProgressType) {
        stopProgressPolling()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [self] _ in
            Task { @MainActor in
                switch type {
                case .transcription:
                    self.transcriptionProgress = TranscriptionService.shared.currentProgress
                case .chapterGeneration:
                    self.chapterProgress = ChapterGenerationService.shared.currentProgress
                }
            }
        }
    }

    private func stopProgressPolling() {
        progressTimer?.invalidate()
        progressTimer = nil
    }
}

// MARK: - Transcription View

struct TranscriptionView: View {
    let download: PodcastDownload
    @StateObject private var podcastPlayer = PodcastAudioPlayer.shared
    @State private var sections: [TranscriptSection] = []
    @State private var searchText = ""
    @State private var isSearching = false
    @AppStorage("transcriptFontSize") private var fontSize: Double = 17

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if let transcription = download.transcription {
                    LazyVStack(alignment: .leading, spacing: 24) {
                        // Episode info header
                        transcriptHeader

                        // Search results indicator
                        if !searchText.isEmpty {
                            searchResultsHeader
                        }

                        // Formatted sections
                        ForEach(filteredSections) { section in
                            TranscriptSectionView(
                                section: section,
                                searchText: searchText,
                                fontSize: fontSize
                            )
                            .id(section.id)
                        }
                    }
                    .padding()
                } else {
                    ContentUnavailableView(
                        "No Transcription",
                        systemImage: "doc.text",
                        description: Text("This episode hasn't been transcribed yet.")
                    )
                }
            }
        }
        .navigationTitle("Transcription")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, isPresented: $isSearching, prompt: "Search transcript")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    // Font size controls
                    Menu {
                        Button {
                            fontSize = max(14, fontSize - 2)
                        } label: {
                            Label("Smaller", systemImage: "textformat.size.smaller")
                        }
                        Button {
                            fontSize = min(24, fontSize + 2)
                        } label: {
                            Label("Larger", systemImage: "textformat.size.larger")
                        }
                        Button {
                            fontSize = 17
                        } label: {
                            Label("Reset", systemImage: "arrow.counterclockwise")
                        }
                    } label: {
                        Label("Text Size", systemImage: "textformat.size")
                    }

                    Divider()

                    // Share
                    if let transcription = download.transcription {
                        ShareLink(item: transcription) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .onAppear {
            parseTranscription()
        }
    }

    private var transcriptHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let articleTitle = download.article?.title {
                Text(articleTitle)
                    .font(.headline)
                    .foregroundStyle(.primary)
            }

            HStack(spacing: 16) {
                if let wordCount = download.transcription?.split(separator: " ").count {
                    Label("\(wordCount.formatted()) words", systemImage: "text.word.spacing")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Label("\(sections.count) sections", systemImage: "list.bullet")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let duration = download.article?.audioDuration, duration > 0 {
                    Label(formatDuration(duration), systemImage: "clock")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()
        }
    }

    private var searchResultsHeader: some View {
        let matchCount = filteredSections.reduce(0) { count, section in
            count + section.paragraphs.filter { paragraph in
                paragraph.localizedCaseInsensitiveContains(searchText)
            }.count
        }

        return HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            Text("\(matchCount) matches found")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }

    private var filteredSections: [TranscriptSection] {
        guard !searchText.isEmpty else { return sections }

        return sections.filter { section in
            section.title.localizedCaseInsensitiveContains(searchText) ||
            section.paragraphs.contains { $0.localizedCaseInsensitiveContains(searchText) }
        }
    }

    private func parseTranscription() {
        guard let transcription = download.transcription else { return }

        // Parse into sections using NLP-based detection
        sections = TranscriptParser.parse(transcription)
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes) min"
        }
    }
}

// MARK: - Transcript Section Model

struct TranscriptSection: Identifiable {
    let id = UUID()
    let title: String
    let paragraphs: [String]
    let sectionNumber: Int
}

// MARK: - Transcript Section View

struct TranscriptSectionView: View {
    let section: TranscriptSection
    let searchText: String
    let fontSize: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section header
            HStack(spacing: 8) {
                Text("Section \(section.sectionNumber)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.accentColor)
                    .cornerRadius(4)

                Text(section.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
            }

            // Paragraphs
            ForEach(Array(section.paragraphs.enumerated()), id: \.offset) { _, paragraph in
                if searchText.isEmpty {
                    Text(paragraph)
                        .font(.system(size: fontSize))
                        .lineSpacing(4)
                        .foregroundStyle(.primary.opacity(0.9))
                } else {
                    HighlightedText(text: paragraph, searchText: searchText, fontSize: fontSize)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
    }
}

// MARK: - Highlighted Text for Search

struct HighlightedText: View {
    let text: String
    let searchText: String
    let fontSize: Double

    var body: some View {
        let attributedString = createHighlightedText()
        Text(attributedString)
            .font(.system(size: fontSize))
            .lineSpacing(4)
    }

    private func createHighlightedText() -> AttributedString {
        var attributedString = AttributedString(text)

        guard !searchText.isEmpty else { return attributedString }

        // Find all ranges of the search text (case insensitive)
        var searchStartIndex = text.startIndex
        while let range = text.range(of: searchText, options: .caseInsensitive, range: searchStartIndex..<text.endIndex) {
            // Convert String.Index range to AttributedString range
            if let attrRange = Range(NSRange(range, in: text), in: attributedString) {
                attributedString[attrRange].backgroundColor = .yellow.opacity(0.4)
                attributedString[attrRange].foregroundColor = .black
            }
            searchStartIndex = range.upperBound
        }

        return attributedString
    }
}

// MARK: - Transcript Parser

struct TranscriptParser {
    /// Parse raw transcription text into logical sections
    static func parse(_ text: String) -> [TranscriptSection] {
        // Clean and normalize the text
        let cleanedText = text
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Split into sentences
        let sentences = splitIntoSentences(cleanedText)

        guard !sentences.isEmpty else { return [] }

        // Group sentences into paragraphs (roughly 3-5 sentences each)
        let paragraphs = groupIntoParagraphs(sentences)

        // Detect topic boundaries and create sections
        let sections = detectSections(paragraphs)

        return sections
    }

    private static func splitIntoSentences(_ text: String) -> [String] {
        var sentences: [String] = []

        // Use NaturalLanguage framework for sentence detection
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text

        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let sentence = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !sentence.isEmpty {
                sentences.append(sentence)
            }
            return true
        }

        // Fallback if NL framework returns nothing
        if sentences.isEmpty {
            // Simple regex-based sentence splitting
            let pattern = "[^.!?]+[.!?]+"
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                let nsText = text as NSString
                let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsText.length))
                sentences = matches.map { nsText.substring(with: $0.range).trimmingCharacters(in: .whitespacesAndNewlines) }
            }
        }

        return sentences
    }

    private static func groupIntoParagraphs(_ sentences: [String]) -> [String] {
        var paragraphs: [String] = []
        var currentParagraph: [String] = []
        let sentencesPerParagraph = 4

        for sentence in sentences {
            currentParagraph.append(sentence)

            if currentParagraph.count >= sentencesPerParagraph {
                paragraphs.append(currentParagraph.joined(separator: " "))
                currentParagraph = []
            }
        }

        // Don't forget remaining sentences
        if !currentParagraph.isEmpty {
            paragraphs.append(currentParagraph.joined(separator: " "))
        }

        return paragraphs
    }

    private static func detectSections(_ paragraphs: [String]) -> [TranscriptSection] {
        guard !paragraphs.isEmpty else { return [] }

        var sections: [TranscriptSection] = []
        var currentSectionParagraphs: [String] = []
        var sectionNumber = 1

        // Target ~5-8 paragraphs per section
        let paragraphsPerSection = 6

        for (index, paragraph) in paragraphs.enumerated() {
            currentSectionParagraphs.append(paragraph)

            let shouldCreateSection = currentSectionParagraphs.count >= paragraphsPerSection ||
                                     index == paragraphs.count - 1 ||
                                     detectTopicShift(from: paragraph, to: paragraphs[safe: index + 1])

            if shouldCreateSection && !currentSectionParagraphs.isEmpty {
                let title = generateSectionTitle(for: currentSectionParagraphs, sectionNumber: sectionNumber)
                sections.append(TranscriptSection(
                    title: title,
                    paragraphs: currentSectionParagraphs,
                    sectionNumber: sectionNumber
                ))
                currentSectionParagraphs = []
                sectionNumber += 1
            }
        }

        return sections
    }

    private static func detectTopicShift(from current: String, to next: String?) -> Bool {
        guard let next = next else { return false }

        // Simple heuristic: look for transition words or significant keyword changes
        let transitionIndicators = [
            "now let's", "moving on", "next", "another thing", "speaking of",
            "that brings us to", "let's talk about", "on a different note",
            "but first", "before we", "anyway", "so basically"
        ]

        let nextLower = next.lowercased()
        return transitionIndicators.contains { nextLower.hasPrefix($0) }
    }

    private static func generateSectionTitle(for paragraphs: [String], sectionNumber: Int) -> String {
        guard let firstParagraph = paragraphs.first else {
            return "Part \(sectionNumber)"
        }

        // Extract key topics using NLTagger
        let tagger = NLTagger(tagSchemes: [.nameType, .lexicalClass])
        tagger.string = firstParagraph

        var nouns: [String] = []
        let options: NLTagger.Options = [.omitWhitespace, .omitPunctuation]

        tagger.enumerateTags(in: firstParagraph.startIndex..<firstParagraph.endIndex,
                           unit: .word,
                           scheme: .lexicalClass,
                           options: options) { tag, tokenRange in
            if let tag = tag, tag == .noun {
                let word = String(firstParagraph[tokenRange])
                if word.count > 3 && !commonWords.contains(word.lowercased()) {
                    nouns.append(word.capitalized)
                }
            }
            return true
        }

        // Take top 2-3 unique nouns for the title
        let uniqueNouns = Array(Set(nouns)).prefix(3)

        if uniqueNouns.isEmpty {
            return "Discussion Part \(sectionNumber)"
        } else {
            return uniqueNouns.joined(separator: ", ")
        }
    }

    // Common words to filter out from section titles
    private static let commonWords: Set<String> = [
        "thing", "things", "way", "ways", "time", "times", "people", "person",
        "year", "years", "day", "days", "week", "weeks", "lot", "kind", "part",
        "something", "anything", "nothing", "everything", "someone", "anyone",
        "stuff", "fact", "point", "case", "place", "world", "life", "work"
    ]
}

// Safe array subscript extension
private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Preview

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Article.self, PodcastDownload.self, configurations: config)

    let article = Article(
        title: "Test Podcast Episode",
        link: "https://example.com",
        publishedDate: Date(),
        guid: "test-guid",
        audioUrl: "https://example.com/audio.mp3",
        audioDuration: 3600,
        audioType: "audio/mpeg"
    )

    return NavigationStack {
        ScrollView {
            PodcastDownloadControls(article: article)
                .padding()
        }
    }
    .modelContainer(container)
}
