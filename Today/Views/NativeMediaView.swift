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
                            .onAppear {
                                print("✅ NativeMediaView: GIF loaded successfully")
                            }
                    case .failure(let error):
                        mediaErrorView
                            .onAppear {
                                print("❌ NativeMediaView: GIF load failed - \(error)")
                            }
                    case .empty:
                        mediaLoadingView
                            .onAppear {
                                print("⏳ NativeMediaView: Loading GIF from \(media.url)")
                            }
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
                            print("▶️ NativeMediaView: Playing video")
                            player.play()
                        }
                        .onDisappear {
                            print("⏸️ NativeMediaView: Pausing video")
                            player.pause()
                        }
                } else if loadError {
                    mediaErrorView
                        .onAppear {
                            print("❌ NativeMediaView: Video player error")
                        }
                } else {
                    mediaLoadingView
                        .onAppear {
                            print("⏳ NativeMediaView: Initializing video player")
                        }
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
            print("⏭️ NativeMediaView: Skipping video load for non-video media type")
            return
        }

        print("🎬 NativeMediaView: Loading video from \(media.url)")

        // Create AVPlayer for video
        let playerItem = AVPlayerItem(url: media.url)
        let newPlayer = AVPlayer(playerItem: playerItem)

        // Observe player item status
        let statusObserver = playerItem.observe(\.status, options: [.new]) { item, _ in
            print("🎬 NativeMediaView: Player status changed: \(item.status.rawValue)")
            switch item.status {
            case .unknown:
                print("⏳ NativeMediaView: Status - Unknown")
            case .readyToPlay:
                print("✅ NativeMediaView: Status - Ready to play")
            case .failed:
                if let error = item.error {
                    print("❌ NativeMediaView: Status - Failed with error: \(error)")
                    print("   Error domain: \((error as NSError).domain)")
                    print("   Error code: \((error as NSError).code)")
                    print("   Error description: \(error.localizedDescription)")
                }
                Task { @MainActor in
                    self.loadError = true
                }
            @unknown default:
                print("⚠️ NativeMediaView: Status - Unknown status value")
            }
        }

        // Keep the observer alive
        withUnsafePointer(to: statusObserver) { _ in }

        // Enable looping
        newPlayer.actionAtItemEnd = .none
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { _ in
            print("🔄 NativeMediaView: Video ended, looping...")
            newPlayer.seek(to: .zero)
            newPlayer.play()
        }

        // Mute audio for autoplay (many Reddit videos are just GIFs with sound)
        newPlayer.isMuted = true
        print("🔇 NativeMediaView: Video muted for autoplay")

        await MainActor.run {
            self.player = newPlayer
            self.isLoading = false
            print("✅ NativeMediaView: Player initialized")
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
