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
    
    // Mini player height including padding
    private static let miniPlayerHeight: CGFloat = 120

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
            .padding(.bottom, (audioPlayer.isPlaying || audioPlayer.isPaused) ? Self.miniPlayerHeight : 0)
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
