//
//  TodayApp.swift
//  Today
//
//  Created by Jake Spurlock on 10/22/25.
//

import SwiftUI
import SwiftData

@main
struct TodayApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Feed.self,
            Article.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    init() {
        // Register background tasks
        BackgroundSyncManager.shared.registerBackgroundTasks()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    // Schedule background sync when app launches
                    BackgroundSyncManager.shared.enableBackgroundFetch()
                }
        }
        .modelContainer(sharedModelContainer)
    }
}
