//
//  FeedListView.swift
//  Today
//
//  View for managing RSS feed subscriptions
//

import SwiftUI
import SwiftData

struct FeedListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Feed.title) private var feeds: [Feed]
    @StateObject private var feedManager: FeedManager

    @State private var showingAddFeed = false
    @State private var newFeedURL = ""
    @State private var newFeedCategory = "general"
    @State private var isAddingFeed = false
    @State private var addFeedError: String?

    init(modelContext: ModelContext) {
        _feedManager = StateObject(wrappedValue: FeedManager(modelContext: modelContext))
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(feeds) { feed in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(feed.title)
                            .font(.headline)
                        Text(feed.url)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack {
                            Text(feed.category)
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.2))
                                .cornerRadius(4)

                            if let lastFetched = feed.lastFetched {
                                Text("Last synced: \(lastFetched, style: .relative) ago")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            deleteFeed(feed)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle("RSS Feeds")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingAddFeed = true
                    } label: {
                        Label("Add Feed", systemImage: "plus")
                    }
                }

                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button {
                            Task {
                                await feedManager.syncAllFeeds()
                            }
                        } label: {
                            Label("Sync All Feeds", systemImage: "arrow.clockwise")
                        }
                        .disabled(feedManager.isSyncing)

                        Divider()

                        Button(role: .destructive) {
                            clearAllData()
                        } label: {
                            Label("Clear All Data", systemImage: "trash")
                        }
                    } label: {
                        Label("Menu", systemImage: "ellipsis.circle")
                    }
                }
            }
            .overlay {
                if feedManager.isSyncing {
                    VStack {
                        ProgressView("Syncing feeds...")
                            .padding()
                            .background(.regularMaterial)
                            .cornerRadius(10)
                    }
                }
            }
            .sheet(isPresented: $showingAddFeed) {
                NavigationStack {
                    Form {
                        Section("Feed Details") {
                            TextField("RSS Feed URL", text: $newFeedURL)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()

                            Picker("Category", selection: $newFeedCategory) {
                                Text("General").tag("general")
                                Text("Work").tag("work")
                                Text("Social").tag("social")
                                Text("Tech").tag("tech")
                                Text("News").tag("news")
                            }
                        }

                        if let error = addFeedError {
                            Section {
                                Text(error)
                                    .foregroundStyle(.red)
                                    .font(.caption)
                            }
                        }
                    }
                    .navigationTitle("Add RSS Feed")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") {
                                showingAddFeed = false
                                resetAddFeedForm()
                            }
                        }

                        ToolbarItem(placement: .confirmationAction) {
                            Button("Add") {
                                addFeed()
                            }
                            .disabled(newFeedURL.isEmpty || isAddingFeed)
                        }
                    }
                    .overlay {
                        if isAddingFeed {
                            ProgressView("Adding feed...")
                                .padding()
                                .background(.regularMaterial)
                                .cornerRadius(10)
                        }
                    }
                }
            }
        }
    }

    private func addFeed() {
        isAddingFeed = true
        addFeedError = nil

        Task {
            do {
                _ = try await feedManager.addFeed(url: newFeedURL, category: newFeedCategory)
                showingAddFeed = false
                resetAddFeedForm()
            } catch {
                addFeedError = error.localizedDescription
            }
            isAddingFeed = false
        }
    }

    private func deleteFeed(_ feed: Feed) {
        do {
            try feedManager.deleteFeed(feed)
        } catch {
            print("Error deleting feed: \(error.localizedDescription)")
        }
    }

    private func resetAddFeedForm() {
        newFeedURL = ""
        newFeedCategory = "general"
        addFeedError = nil
    }

    private func clearAllData() {
        do {
            try modelContext.clearAllData()
        } catch {
            print("Error clearing data: \(error.localizedDescription)")
        }
    }
}
