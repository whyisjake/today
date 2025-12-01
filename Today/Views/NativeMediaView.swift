//
//  NativeMediaView.swift
//  Today
//
//  Native media player for GIFs and videos (Giphy, Redgifs, etc.)
//  Replaces iframe embeds with native playback
//

import SwiftUI
import AVKit

struct NativeMediaView: View {
    let media: ExtractedMedia
    @State private var player: AVPlayer?
    @State private var isLoading = true
    @State private var loadError = false

    var body: some View {
        Group {
            switch media.type {
            case .gif:
                // Use AsyncImage for GIFs
                AsyncImage(url: media.url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    case .failure:
                        mediaErrorView
                    case .empty:
                        mediaLoadingView
                    @unknown default:
                        EmptyView()
                    }
                }

            case .video, .image:
                // Use AVPlayer for videos
                if let player = player {
                    VideoPlayer(player: player)
                        .aspectRatio(contentMode: .fit)
                        .onAppear {
                            player.play()
                        }
                        .onDisappear {
                            player.pause()
                        }
                } else if loadError {
                    mediaErrorView
                } else {
                    mediaLoadingView
                }
            }
        }
        .task {
            await loadMedia()
        }
    }

    private var mediaLoadingView: some View {
        ZStack {
            Rectangle()
                .fill(Color.gray.opacity(0.2))
                .aspectRatio(16/9, contentMode: .fit)

            ProgressView()
        }
    }

    private var mediaErrorView: some View {
        ZStack {
            Rectangle()
                .fill(Color.gray.opacity(0.2))
                .aspectRatio(16/9, contentMode: .fit)

            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text("Failed to load media")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func loadMedia() async {
        guard media.type == .video || media.type == .image else {
            return
        }

        // Create AVPlayer for video
        let playerItem = AVPlayerItem(url: media.url)
        let newPlayer = AVPlayer(playerItem: playerItem)

        // Enable looping
        newPlayer.actionAtItemEnd = .none
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { _ in
            newPlayer.seek(to: .zero)
            newPlayer.play()
        }

        // Mute audio for autoplay (many Reddit videos are just GIFs with sound)
        newPlayer.isMuted = true

        await MainActor.run {
            self.player = newPlayer
            self.isLoading = false
        }
    }
}

// Preview
#Preview {
    VStack {
        Text("Giphy GIF")
        NativeMediaView(
            media: ExtractedMedia(
                url: URL(string: "https://i.giphy.com/media/3o7btPCcdNniyf0ArS/giphy.gif")!,
                type: .gif,
                width: nil,
                height: nil
            )
        )
        .frame(height: 200)
    }
}
