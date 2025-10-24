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

    var body: some View {
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
        .preferredColorScheme(appearanceMode.colorScheme)
        .onAppear {
            // Pre-warm WebView pool for faster article loading
            _ = WebViewPool.shared
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Feed.self, inMemory: true)
}
