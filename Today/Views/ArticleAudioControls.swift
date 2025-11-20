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
            // Progress bar
            if audioPlayer.isPlaying || audioPlayer.isPaused,
               audioPlayer.currentArticle?.id == article.id {
                ProgressView(value: audioPlayer.progress)
                    .tint(.accentColor)
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
                        Text(isCurrentlyPlaying ? "Pause" : "Listen")
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
                        Text(String(format: "%.1fx", audioPlayer.playbackRate))
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

    private let speeds: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0]

    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(speeds.enumerated()), id: \.offset) { _, speed in
                    Button {
                        audioPlayer.setPlaybackRate(speed)
                        dismiss()
                    } label: {
                        HStack {
                            Text(String(format: "%.2fx", speed as CVarArg))
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
            .navigationTitle("Playback Speed")
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
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        if let article = audioPlayer.currentArticle,
           audioPlayer.isPlaying || audioPlayer.isPaused {
            VStack(spacing: 0) {
                Divider()

                HStack(spacing: 12) {
                    // Article info
                    VStack(alignment: .leading, spacing: 4) {
                        Text(article.title)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                        Text(article.feed?.title ?? "Today")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    // Play/Pause button
                    Button {
                        audioPlayer.togglePlayPause()
                    } label: {
                        Image(systemName: audioPlayer.isPaused ? "play.circle.fill" : "pause.circle.fill")
                            .font(.title2)
                            .foregroundStyle(Color.accentColor)
                    }

                    // Stop button
                    Button {
                        audioPlayer.stop()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
                .background(Color(.systemBackground))
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}
