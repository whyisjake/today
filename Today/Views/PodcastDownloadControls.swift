//
//  PodcastDownloadControls.swift
//  Today
//
//  Download, transcription, and chapter generation controls for podcast episodes
//

import SwiftUI
import SwiftData

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
            HStack(spacing: 8) {
                Image(systemName: "waveform")
                Text("Transcribe Episode")
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(Color.accentColor)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color.accentColor.opacity(0.1))
            .cornerRadius(10)
        }
    }

    private func transcribingView(progress: Double) -> some View {
        VStack(spacing: 8) {
            HStack {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Transcribing...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
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

    var body: some View {
        ScrollView {
            if let transcription = download.transcription {
                Text(transcription)
                    .font(.body)
                    .padding()
            } else {
                ContentUnavailableView(
                    "No Transcription",
                    systemImage: "doc.text",
                    description: Text("This episode hasn't been transcribed yet.")
                )
            }
        }
        .navigationTitle("Transcription")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if let transcription = download.transcription {
                    ShareLink(item: transcription) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
        }
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
