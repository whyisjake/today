//
//  NowPlayingView.swift
//  Today
//
//  Full-screen Now Playing view for podcasts with chapter support
//

import SwiftUI

struct NowPlayingView: View {
    @StateObject private var podcastPlayer = PodcastAudioPlayer.shared
    @Environment(\.dismiss) private var dismiss
    @AppStorage("accentColor") private var accentColor: AccentColorOption = .orange
    @State private var showChapterList = false
    @State private var showSpeedPicker = false

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ScrollView {
                    VStack(spacing: 24) {
                        // Artwork - ensure size is never negative
                        artworkView(size: max(100, min(geometry.size.width - 64, 320)))

                        // Track info
                        trackInfoView

                        // Chapter indicator (if chapters exist)
                        if !podcastPlayer.chapters.isEmpty {
                            chapterIndicatorView
                        }

                        // Progress bar
                        progressView

                        // Playback controls
                        playbackControls

                        // Additional controls
                        additionalControls

                        // Chapter list (expandable)
                        if !podcastPlayer.chapters.isEmpty {
                            chapterListSection
                        }

                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 32)
                    .padding(.top, 20)
                }
            }
            .background(
                // Gradient background based on accent color
                LinearGradient(
                    colors: [
                        accentColor.color.opacity(0.15),
                        Color(.systemBackground)
                    ],
                    startPoint: .top,
                    endPoint: .center
                )
                .ignoresSafeArea()
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.title3.weight(.semibold))
                    }
                }

                ToolbarItem(placement: .principal) {
                    VStack(spacing: 2) {
                        Text("Now Playing")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(podcastPlayer.currentArticle?.feed?.title ?? "Podcast")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .sheet(isPresented: $showSpeedPicker) {
                PodcastSpeedPickerView(podcastPlayer: podcastPlayer)
                    .presentationDetents([.height(300)])
            }
        }
    }

    // MARK: - Artwork View

    @ViewBuilder
    private func artworkView(size: CGFloat) -> some View {
        // Priority: 1. Chapter artwork, 2. Article/podcast artwork, 3. Placeholder
        if let chapterImage = podcastPlayer.currentChapter?.image {
            // Use chapter-specific artwork
            Image(uiImage: chapterImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
        } else if let imageUrl = podcastPlayer.currentArticle?.imageUrl {
            // Convert HTTP to HTTPS for ATS compliance
            let secureUrl = imageUrl.hasPrefix("http://")
                ? imageUrl.replacingOccurrences(of: "http://", with: "https://")
                : imageUrl
            AsyncImage(url: URL(string: secureUrl)) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                case .failure:
                    artworkPlaceholder
                case .empty:
                    artworkPlaceholder
                        .overlay {
                            ProgressView()
                        }
                @unknown default:
                    artworkPlaceholder
                }
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
        } else {
            artworkPlaceholder
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
        }
    }

    private var artworkPlaceholder: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [accentColor.color, accentColor.color.opacity(0.7)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                Image(systemName: "waveform")
                    .font(.system(size: 80))
                    .foregroundStyle(.white.opacity(0.8))
            }
    }

    // MARK: - Track Info

    private var trackInfoView: some View {
        VStack(spacing: 8) {
            Text(podcastPlayer.currentArticle?.title ?? "Unknown Episode")
                .font(.title2.weight(.bold))
                .multilineTextAlignment(.center)
                .lineLimit(2)

            if let author = podcastPlayer.currentArticle?.author {
                Text(author)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Chapter Indicator

    private var chapterIndicatorView: some View {
        Button {
            withAnimation {
                showChapterList.toggle()
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "list.bullet")
                    .font(.caption)

                if let chapter = podcastPlayer.currentChapter {
                    Text(chapter.title)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                } else {
                    Text("No chapters")
                        .font(.subheadline)
                }

                Spacer()

                if let currentIndex = currentChapterIndex {
                    Text("\(currentIndex + 1) of \(podcastPlayer.chapters.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Image(systemName: showChapterList ? "chevron.up" : "chevron.down")
                    .font(.caption)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(.secondarySystemBackground))
            .cornerRadius(10)
        }
        .buttonStyle(.plain)
    }

    private var currentChapterIndex: Int? {
        guard let current = podcastPlayer.currentChapter else { return nil }
        return podcastPlayer.chapters.firstIndex { $0.id == current.id }
    }

    // MARK: - Progress View

    private var progressView: some View {
        VStack(spacing: 8) {
            Slider(
                value: Binding(
                    get: { podcastPlayer.progress },
                    set: { podcastPlayer.seek(to: $0) }
                ),
                in: 0...1
            )
            .tint(accentColor.color)

            HStack {
                Text(AudioFormatters.formatDuration(podcastPlayer.currentTime))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)

                Spacer()

                Text("-" + AudioFormatters.formatDuration(podcastPlayer.duration - podcastPlayer.currentTime))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Playback Controls

    private var playbackControls: some View {
        HStack(spacing: 40) {
            // Previous chapter / Skip back
            Button {
                if podcastPlayer.chapters.isEmpty {
                    // Skip back 15 seconds
                    let newProgress = (podcastPlayer.currentTime - 15) / podcastPlayer.duration
                    podcastPlayer.seek(to: max(0, newProgress))
                } else {
                    podcastPlayer.previousChapter()
                }
            } label: {
                Image(systemName: podcastPlayer.chapters.isEmpty ? "gobackward.15" : "backward.end.fill")
                    .font(.title)
                    .foregroundStyle(.primary)
            }

            // Play/Pause
            Button {
                podcastPlayer.togglePlayPause()
            } label: {
                Image(systemName: podcastPlayer.isPaused ? "play.circle.fill" : "pause.circle.fill")
                    .font(.system(size: 70))
                    .foregroundStyle(accentColor.color)
            }

            // Next chapter / Skip forward
            Button {
                if podcastPlayer.chapters.isEmpty {
                    // Skip forward 30 seconds
                    let newProgress = (podcastPlayer.currentTime + 30) / podcastPlayer.duration
                    podcastPlayer.seek(to: min(1, newProgress))
                } else {
                    podcastPlayer.nextChapter()
                }
            } label: {
                Image(systemName: podcastPlayer.chapters.isEmpty ? "goforward.30" : "forward.end.fill")
                    .font(.title)
                    .foregroundStyle(.primary)
            }
        }
    }

    // MARK: - Additional Controls

    private var additionalControls: some View {
        HStack(spacing: 32) {
            // Speed control
            Button {
                showSpeedPicker = true
            } label: {
                VStack(spacing: 4) {
                    Text(AudioFormatters.formatSpeed(podcastPlayer.playbackRate))
                        .font(.subheadline.weight(.semibold))
                    Text("Speed")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)

            Spacer()

            // Skip back 15s
            Button {
                let newProgress = (podcastPlayer.currentTime - 15) / podcastPlayer.duration
                podcastPlayer.seek(to: max(0, newProgress))
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "gobackward.15")
                        .font(.title3)
                    Text("-15s")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)

            // Skip forward 30s
            Button {
                let newProgress = (podcastPlayer.currentTime + 30) / podcastPlayer.duration
                podcastPlayer.seek(to: min(1, newProgress))
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "goforward.30")
                        .font(.title3)
                    Text("+30s")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)

            Spacer()

            // Stop
            Button {
                podcastPlayer.stop()
                dismiss()
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "stop.fill")
                        .font(.title3)
                    Text("Stop")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal)
    }

    // MARK: - Chapter List

    private var chapterListSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if showChapterList {
                Divider()

                Text("Chapters")
                    .font(.headline)
                    .padding(.top, 8)

                ForEach(podcastPlayer.chapters) { chapter in
                    ChapterRowView(
                        chapter: chapter,
                        isCurrentChapter: chapter.id == podcastPlayer.currentChapter?.id,
                        onTap: {
                            podcastPlayer.seekToChapter(chapter)
                        }
                    )
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showChapterList)
    }
}

// MARK: - Chapter Row View

struct ChapterRowView: View {
    let chapter: PodcastChapter
    let isCurrentChapter: Bool
    let onTap: () -> Void
    @AppStorage("accentColor") private var accentColor: AccentColorOption = .orange
    @Environment(\.openURL) private var openURL

    var body: some View {
        HStack(spacing: 12) {
            // Chapter artwork (if available)
            if let chapterImage = chapter.image {
                Image(uiImage: chapterImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                // Playing indicator or timestamp
                if isCurrentChapter {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.caption)
                        .foregroundStyle(accentColor.color)
                        .frame(width: 44)
                } else {
                    Text(chapter.formattedStartTime)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 44, alignment: .leading)
                }
            }

            // Chapter info
            VStack(alignment: .leading, spacing: 4) {
                // Chapter title with optional link
                if let urlString = chapter.url, let url = URL(string: urlString) {
                    // Tappable link title
                    Button {
                        openURL(url)
                    } label: {
                        HStack(spacing: 4) {
                            Text(chapter.title)
                                .font(.subheadline)
                                .foregroundStyle(accentColor.color)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                            Image(systemName: "arrow.up.right")
                                .font(.caption2)
                                .foregroundStyle(accentColor.color)
                        }
                    }
                    .buttonStyle(.plain)
                } else {
                    // Regular title (no link)
                    Text(chapter.title)
                        .font(.subheadline)
                        .foregroundStyle(isCurrentChapter ? accentColor.color : .primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }

                // Show timestamp below title when we have artwork
                if chapter.image != nil {
                    HStack(spacing: 8) {
                        Text(chapter.formattedStartTime)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)

                        if isCurrentChapter {
                            Image(systemName: "speaker.wave.2.fill")
                                .font(.caption2)
                                .foregroundStyle(accentColor.color)
                        }
                    }
                }
            }

            Spacer()

            // Duration
            if let endTime = chapter.endTime {
                let duration = endTime - chapter.startTime
                Text(AudioFormatters.formatDuration(duration))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(isCurrentChapter ? accentColor.color.opacity(0.1) : Color.clear)
        .cornerRadius(8)
        .onTapGesture {
            onTap()
        }
    }
}

#Preview {
    NowPlayingView()
}
