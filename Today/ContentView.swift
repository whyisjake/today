//
//  ContentView.swift
//  Today
//
//  Main tab view for the app
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage("appearanceMode") private var appearanceMode: AppearanceMode = .system
    @AppStorage("accentColor") private var accentColor: AccentColorOption = .orange
    @StateObject private var audioPlayer = ArticleAudioPlayer.shared
    @StateObject private var podcastPlayer = PodcastAudioPlayer.shared

    // Mini player height including padding (per player)
    private static let miniPlayerHeight: CGFloat = 120

    private var isTTSActive: Bool {
        audioPlayer.isPlaying || audioPlayer.isPaused
    }

    private var isPodcastActive: Bool {
        podcastPlayer.isPlaying || podcastPlayer.isPaused
    }

    private var totalMiniPlayerHeight: CGFloat {
        var height: CGFloat = 0
        if isTTSActive { height += Self.miniPlayerHeight }
        if isPodcastActive { height += Self.miniPlayerHeight }
        return height
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView {
                TodayView()
                    .tabItem {
                        Label("Today", systemImage: "newspaper")
                    }

                FeedListView(modelContext: modelContext)
                    .tabItem {
                        Label("Feeds", systemImage: "list.bullet")
                    }

                AIChatView()
                    .tabItem {
                        Label("AI Summary", systemImage: "sparkles")
                    }

                SettingsView()
                    .tabItem {
                        Label("Settings", systemImage: "gear")
                    }
            }
            .padding(.bottom, totalMiniPlayerHeight)
            .preferredColorScheme(appearanceMode.colorScheme)
            .tint(accentColor.color)
            .onAppear {
                // Pre-warm WebView pool for faster article loading
                _ = WebViewPool.shared
            }

            // Global mini audio player (sits above tab bar)
            MiniAudioPlayer()
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Feed.self, inMemory: true)
}
