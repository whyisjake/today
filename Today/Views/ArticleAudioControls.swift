//
//  ArticleAudioControls.swift
//  Today
//
//  Audio player controls for text-to-speech article reading
//

import SwiftUI

struct ArticleAudioControls: View {
    let article: Article
    @StateObject private var audioPlayer = ArticleAudioPlayer.shared
    @State private var showSpeedPicker = false

    var body: some View {
        VStack(spacing: 12) {
            // Scrubber slider (only show when audio is active)
            if audioPlayer.isPlaying || audioPlayer.isPaused,
               audioPlayer.currentArticle?.id == article.id {
                VStack(spacing: 4) {
                    Slider(value: Binding(
                        get: { audioPlayer.progress },
                        set: { newValue in
                            audioPlayer.seek(to: newValue)
                        }
                    ), in: 0...1)
                    .tint(.accentColor)

                    HStack {
                        Text((audioPlayer.progress * audioPlayer.estimatedDuration).formatted())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(audioPlayer.estimatedDuration.formatted())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            HStack(spacing: 20) {
                // Play/Pause button
                Button {
                    if audioPlayer.currentArticle?.id == article.id {
                        audioPlayer.togglePlayPause()
                    } else {
                        audioPlayer.play(article: article)
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: isCurrentlyPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.title2)
                        Text(isCurrentlyPlaying ? String(localized: "Pause") : String(localized: "Listen"))
                            .font(.subheadline.weight(.semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.accentColor)
                    .cornerRadius(12)
                }

                // Stop button (only show when playing)
                if audioPlayer.currentArticle?.id == article.id,
                   (audioPlayer.isPlaying || audioPlayer.isPaused) {
                    Button {
                        audioPlayer.stop()
                    } label: {
                        Image(systemName: "stop.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                            .frame(width: 44, height: 44)
                            .background(Color(.systemGray6))
                            .cornerRadius(12)
                    }
                }

                // Speed control button
                Button {
                    showSpeedPicker.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "gauge.with.dots.needle.50percent")
                        Text(ArticleAudioPlayer.formatSpeed(audioPlayer.playbackRate))
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 60)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 12)
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .sheet(isPresented: $showSpeedPicker) {
            SpeedPickerView(audioPlayer: audioPlayer)
                .presentationDetents([.height(300)])
        }
    }

    private var isCurrentlyPlaying: Bool {
        audioPlayer.currentArticle?.id == article.id &&
        audioPlayer.isPlaying &&
        !audioPlayer.isPaused
    }
}

// MARK: - Speed Picker

struct SpeedPickerView: View {
    @ObservedObject var audioPlayer: ArticleAudioPlayer
    @Environment(\.dismiss) private var dismiss

    // Actual AVSpeech rates (0.5 = "1x" normal speed)
    private let speeds: [Float] = [0.25, 0.375, 0.5, 0.625, 0.75, 0.875, 1.0]

    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(speeds.enumerated()), id: \.offset) { _, speed in
                    Button {
                        audioPlayer.setPlaybackRate(speed)
                        dismiss()
                    } label: {
                        HStack {
                            Text(ArticleAudioPlayer.formatSpeed(speed))
                                .foregroundStyle(.primary)
                            Spacer()
                            if abs(audioPlayer.playbackRate - speed) < 0.01 {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                }
            }
            .navigationTitle(String(localized: "Playback Speed"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Mini Player (Global)

struct MiniAudioPlayer: View {
    @StateObject private var audioPlayer = ArticleAudioPlayer.shared
    @StateObject private var podcastPlayer = PodcastAudioPlayer.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showTTSSpeedPicker = false
    @State private var showPodcastSpeedPicker = false
    @State private var showNowPlaying = false
    @AppStorage("accentColor") private var accentColor: AccentColorOption = .orange

    private var isTTSActive: Bool {
        audioPlayer.currentArticle != nil && (audioPlayer.isPlaying || audioPlayer.isPaused)
    }

    private var isPodcastActive: Bool {
        podcastPlayer.currentArticle != nil && (podcastPlayer.isPlaying || podcastPlayer.isPaused)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Show TTS mini player
            if let article = audioPlayer.currentArticle,
               audioPlayer.isPlaying || audioPlayer.isPaused {
                miniPlayerView(
                    article: article,
                    progress: audioPlayer.progress,
                    isPaused: audioPlayer.isPaused,
                    playbackRate: ArticleAudioPlayer.formatSpeed(audioPlayer.playbackRate),
                    currentTimeText: AudioFormatters.formatDuration(audioPlayer.progress * audioPlayer.estimatedDuration),
                    onSeek: { newValue in audioPlayer.seek(to: newValue) },
                    onTogglePlayPause: { audioPlayer.togglePlayPause() },
                    onStop: { audioPlayer.stop() },
                    onShowSpeedPicker: { showTTSSpeedPicker = true },
                    onTapContent: { }, // TTS doesn't have a full Now Playing view yet
                    isPodcast: false
                )
            }

            // Show podcast mini player (can show alongside TTS)
            if let article = podcastPlayer.currentArticle,
               podcastPlayer.isPlaying || podcastPlayer.isPaused {
                miniPlayerView(
                    article: article,
                    progress: podcastPlayer.progress,
                    isPaused: podcastPlayer.isPaused,
                    playbackRate: AudioFormatters.formatSpeed(podcastPlayer.playbackRate),
                    currentTimeText: formatDuration(podcastPlayer.currentTime),
                    onSeek: { newValue in podcastPlayer.seek(to: newValue) },
                    onTogglePlayPause: { podcastPlayer.togglePlayPause() },
                    onStop: { podcastPlayer.stop() },
                    onShowSpeedPicker: { showPodcastSpeedPicker = true },
                    onTapContent: { showNowPlaying = true },
                    isPodcast: true
                )
            }
        }
        .sheet(isPresented: $showTTSSpeedPicker) {
            SpeedPickerView(audioPlayer: audioPlayer)
                .presentationDetents([.height(300)])
        }
        .sheet(isPresented: $showPodcastSpeedPicker) {
            PodcastSpeedPickerView(podcastPlayer: podcastPlayer)
                .presentationDetents([.height(300)])
        }
        .fullScreenCover(isPresented: $showNowPlaying) {
            NowPlayingView()
        }
    }
    
    @ViewBuilder
    private func miniPlayerView(
        article: Article,
        progress: Double,
        isPaused: Bool,
        playbackRate: String,
        currentTimeText: String,
        onSeek: @escaping (Double) -> Void,
        onTogglePlayPause: @escaping () -> Void,
        onStop: @escaping () -> Void,
        onShowSpeedPicker: @escaping () -> Void,
        onTapContent: @escaping () -> Void,
        isPodcast: Bool
    ) -> some View {
        VStack(spacing: 0) {
            Divider()

            VStack(spacing: 8) {
                // Progress scrubber
                Slider(value: Binding(
                    get: { progress },
                    set: { newValue in onSeek(newValue) }
                ), in: 0...1)
                .tint(accentColor.color)

                HStack(spacing: 12) {
                    // Tappable content area (thumbnail + info)
                    Button {
                        onTapContent()
                    } label: {
                        HStack(spacing: 12) {
                            // Article thumbnail
                            if let imageUrl = article.imageUrl {
                                // Convert HTTP to HTTPS for ATS compliance
                                let secureUrl = imageUrl.hasPrefix("http://")
                                    ? imageUrl.replacingOccurrences(of: "http://", with: "https://")
                                    : imageUrl
                                AsyncImage(url: URL(string: secureUrl)) { image in
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                } placeholder: {
                                    Rectangle()
                                        .fill(Color(.systemGray5))
                                }
                                .frame(width: 48, height: 48)
                                .cornerRadius(6)
                            }

                            // Article info
                            VStack(alignment: .leading, spacing: 4) {
                                Text(article.title)
                                    .font(.subheadline.weight(.medium))
                                    .lineLimit(1)
                                    .foregroundStyle(.primary)
                                HStack(spacing: 4) {
                                    // Feed name - Author (if available)
                                    if let author = article.author {
                                        Text("\(article.feed?.title ?? "Today") - \(author)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    } else {
                                        Text(article.feed?.title ?? "Today")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Text("•")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(currentTimeText)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    // Speed control button
                    Button {
                        onShowSpeedPicker()
                    } label: {
                        Text(playbackRate)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(accentColor.color)
                            .frame(minWidth: 36)
                    }

                    // Play/Pause button
                    Button {
                        onTogglePlayPause()
                    } label: {
                        Image(systemName: isPaused ? "play.circle.fill" : "pause.circle.fill")
                            .font(.title2)
                            .foregroundStyle(accentColor.color)
                    }

                    // Stop button
                    Button {
                        onStop()
                    } label: {
                        Image(systemName: "xmark.circle")
                            .font(.title3)
                            .foregroundStyle(accentColor.color)
                    }
                }
            }
            .padding()
            .background(
                accentColor.color.opacity(0.05)
                    .overlay(Color(.systemBackground).opacity(0.95))
            )
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        AudioFormatters.formatDuration(duration)
    }
}

// MARK: - Podcast Audio Controls

struct PodcastAudioControls: View {
    let article: Article
    @StateObject private var podcastPlayer = PodcastAudioPlayer.shared
    @State private var showSpeedPicker = false

    var body: some View {
        VStack(spacing: 12) {
            // Show duration info if available
            if let duration = article.audioDuration {
                HStack {
                    Image(systemName: "waveform")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(formatDuration(duration))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }
            
            // Scrubber slider (only show when audio is active)
            if podcastPlayer.isPlaying || podcastPlayer.isPaused,
               podcastPlayer.currentArticle?.id == article.id {
                VStack(spacing: 4) {
                    Slider(value: Binding(
                        get: { podcastPlayer.progress },
                        set: { newValue in
                            podcastPlayer.seek(to: newValue)
                        }
                    ), in: 0...1)
                    .tint(.accentColor)

                    HStack {
                        Text(formatDuration(podcastPlayer.currentTime))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(formatDuration(podcastPlayer.duration))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            HStack(spacing: 12) {
                // Play/Pause button
                Button {
                    if podcastPlayer.currentArticle?.id == article.id {
                        podcastPlayer.togglePlayPause()
                    } else {
                        podcastPlayer.play(article: article)
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: isCurrentlyPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.title2)
                        Text(isCurrentlyPlaying ? String(localized: "Pause") : String(localized: "Play Podcast"))
                            .font(.subheadline.weight(.semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.accentColor)
                    .cornerRadius(10)
                }

                // Stop button (only show when playing)
                if podcastPlayer.currentArticle?.id == article.id,
                   (podcastPlayer.isPlaying || podcastPlayer.isPaused) {
                    Button {
                        podcastPlayer.stop()
                    } label: {
                        Image(systemName: "stop.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                            .frame(width: 44, height: 44)
                            .background(Color(.systemGray6))
                            .cornerRadius(10)
                    }
                }

                // Speed control button
                Button {
                    showSpeedPicker.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "gauge.with.dots.needle.50percent")
                        Text(AudioFormatters.formatSpeed(podcastPlayer.playbackRate))
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.accentColor)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 12)
                    .background(Color.accentColor.opacity(0.1))
                    .cornerRadius(10)
                }
            }
        }
        .sheet(isPresented: $showSpeedPicker) {
            PodcastSpeedPickerView(podcastPlayer: podcastPlayer)
                .presentationDetents([.height(300)])
        }
        .onAppear {
            // Prefetch chapters in the background so they're ready when playback starts
            podcastPlayer.prefetchChapters(for: article)
        }
    }

    private var isCurrentlyPlaying: Bool {
        podcastPlayer.currentArticle?.id == article.id && podcastPlayer.isPlaying
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        AudioFormatters.formatDuration(duration)
    }
}

// MARK: - Podcast Speed Picker

struct PodcastSpeedPickerView: View {
    @ObservedObject var podcastPlayer: PodcastAudioPlayer
    @Environment(\.dismiss) private var dismiss

    private let speeds: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0]

    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(speeds.enumerated()), id: \.offset) { _, speed in
                    Button {
                        podcastPlayer.setPlaybackRate(speed)
                        dismiss()
                    } label: {
                        HStack {
                            Text(AudioFormatters.formatSpeed(speed))
                                .foregroundStyle(.primary)
                            Spacer()
                            if abs(podcastPlayer.playbackRate - speed) < 0.01 {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                }
            }
            .navigationTitle(String(localized: "Playback Speed"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}
