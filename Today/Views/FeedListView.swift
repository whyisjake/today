//
//  FeedListView.swift
//  Today
//
//  View for managing RSS feed subscriptions
//

import SwiftUI
import SwiftData

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

// MARK: - Feed Category
enum FeedCategory: String, CaseIterable {
    case general = "General"
    case work = "Work"
    case social = "Social"
    case tech = "Tech"
    case news = "News"
    case politics = "Politics"
    case personal = "Personal"
    case comics = "Comics"
    case technology = "Technology"

    var localizedName: String {
        switch self {
        case .general: return String(localized: "General")
        case .work: return String(localized: "Work")
        case .social: return String(localized: "Social")
        case .tech: return String(localized: "Tech")
        case .news: return String(localized: "News")
        case .politics: return String(localized: "Politics")
        case .personal: return String(localized: "Personal")
        case .comics: return String(localized: "Comics")
        case .technology: return String(localized: "Technology")
        }
    }

    /// Standard categories shown in pickers (excludes legacy/duplicate categories)
    /// Note: `.personal`, `.comics`, and `.technology` are legacy categories kept for backward compatibility.
    /// They are intentionally excluded from the picker and cannot be selected for new feeds,
    /// but may still appear for existing feeds created before this change.
    static var pickerCategories: [FeedCategory] {
        [.general, .work, .social, .tech, .news, .politics]
    }
}

struct FeedListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Feed.title) private var feeds: [Feed]
    @StateObject private var feedManager: FeedManager
    @ObservedObject private var categoryManager = CategoryManager.shared
    @ObservedObject private var syncManager = BackgroundSyncManager.shared
    @AppStorage("accentColor") private var accentColor: AccentColorOption = .orange

    @State private var showingAddFeed = false
    @State private var feedType: FeedType = .rss
    @State private var newFeedURL = ""
    @State private var subredditName = ""
    @State private var newFeedCategory = "General"
    @State private var customCategory = ""
    @State private var useCustomCategory = false
    @State private var isAddingFeed = false
    @State private var addFeedError: String?

    enum FeedType: String, CaseIterable {
        case rss = "RSS Feed"
        case reddit = "Reddit"
    }

    @State private var editingFeedID: PersistentIdentifier?

    private var showingEditFeed: Binding<Bool> {
        Binding(
            get: { editingFeedID != nil },
            set: { if !$0 { editingFeedID = nil } }
        )
    }

    @State private var newsletterFeedID: PersistentIdentifier?

    private var showingNewsletterSheet: Binding<Bool> {
        Binding(
            get: { newsletterFeedID != nil },
            set: { if !$0 { newsletterFeedID = nil } }
        )
    }

    @State private var showingImportOPML = false
    @State private var opmlText = ""
    @State private var isImporting = false
    @State private var importError: String?
    @State private var importProgress: String?
    @State private var showingExportConfirmation = false
    @AppStorage("showAltCategory") private var showAltFeeds = false // Global setting for Alt category visibility

    // OPML Subscription
    @Query(sort: \OPMLSubscription.title) private var opmlSubscriptions: [OPMLSubscription]
    @State private var showingSubscribeOPML = false
    @State private var subscribeOPMLURL = ""
    @State private var subscribeOPMLCategory = "General"
    @State private var isSubscribing = false
    @State private var subscribeError: String?
    @State private var opmlActionError: String?

    // For macOS: show feed articles in place and use parent's selectedArticle
    #if os(macOS)
    @State private var selectedFeedForArticles: Feed?
    @Binding var selectedArticle: Article?
    #endif

    #if os(macOS)
    init(modelContext: ModelContext, selectedArticle: Binding<Article?>) {
        _feedManager = StateObject(wrappedValue: FeedManager(modelContext: modelContext))
        _selectedArticle = selectedArticle
    }
    #else
    init(modelContext: ModelContext) {
        _feedManager = StateObject(wrappedValue: FeedManager(modelContext: modelContext))
    }
    #endif

    // Filter feeds based on Alt category visibility
    private var visibleFeeds: [Feed] {
        let filtered: [Feed]
        if showAltFeeds {
            // When showing Alt, only show Alt feeds
            filtered = feeds.filter { $0.category.lowercased() == "alt" }
        } else {
            // When not showing Alt, exclude Alt feeds
            filtered = feeds.filter { $0.category.lowercased() != "alt" }
        }
        // Sort case-insensitively (Aa-Zz)
        return filtered.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    // Check if there are any Alt feeds
    private var hasAltFeeds: Bool {
        feeds.contains { $0.category.lowercased() == "alt" }
    }

    var body: some View {
        NavigationStack {
            #if os(macOS)
            // macOS: swap views in place to avoid nested navigation
            if let feed = selectedFeedForArticles {
                FeedArticlesView(feed: feed, selectedArticle: $selectedArticle)
                    .navigationTitle(feed.title)
                    .toolbar {
                        ToolbarItem(placement: .navigation) {
                            Button {
                                selectedFeedForArticles = nil
                            } label: {
                                Label("Back to Feeds", systemImage: "chevron.left")
                            }
                        }
                    }
            } else {
                feedListContent
                    .navigationTitle("RSS Feeds")
                    .toolbar {
                        toolbarContent
                    }
                    .overlay {
                        syncingOverlay
                    }
            }
            #else
            feedListContent
                .navigationTitle("RSS Feeds")
                .toolbar {
                    toolbarContent
                }
                .overlay {
                    syncingOverlay
                }
            #endif
        }
        .sheet(isPresented: $showingAddFeed) {
            addFeedSheet
        }
        .sheet(isPresented: $showingImportOPML) {
            importOPMLSheet
        }
        .sheet(isPresented: showingEditFeed) {
            editFeedSheet
        }
        .sheet(isPresented: showingNewsletterSheet) {
            newsletterSheet
        }
        .sheet(isPresented: $showingSubscribeOPML) {
            subscribeOPMLSheet
        }
        .alert("OPML Exported", isPresented: $showingExportConfirmation) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Your OPML feed list has been copied to the clipboard.")
        }
        .alert("OPML Subscription Error", isPresented: Binding(
            get: { opmlActionError != nil },
            set: { if !$0 { opmlActionError = nil } }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(opmlActionError ?? "An unknown error occurred.")
        }
        .onAppear {
            // Sync custom categories from existing feeds
            categoryManager.syncCategories(from: feeds.map { $0.category })
        }
    }

    @ViewBuilder
    private var feedListContent: some View {
        List {
            // OPML Subscriptions section
            if !opmlSubscriptions.isEmpty {
                Section {
                    ForEach(opmlSubscriptions) { sub in
                        HStack {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                                .foregroundStyle(accentColor.color)
                                .font(.caption)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(sub.title)
                                    .font(.subheadline.weight(.medium))
                                HStack(spacing: 4) {
                                    Text(managedFeedCount(for: sub))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    if let lastFetched = sub.lastFetched {
                                        Text("·")
                                            .foregroundStyle(.tertiary)
                                        Text("Synced \(lastFetched, style: .relative) ago")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            Spacer()
                            if !sub.isActive {
                                Text("Paused")
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                            }
                        }
                        .contextMenu {
                            Button {
                                syncSingleSubscription(sub)
                            } label: {
                                Label("Sync Now", systemImage: "arrow.clockwise")
                            }

                            Button(role: .destructive) {
                                unsubscribeOPML(sub)
                            } label: {
                                Label("Unsubscribe", systemImage: "trash")
                            }
                        }
                    }
                } header: {
                    Text("OPML Subscriptions")
                }
            }

            ForEach(visibleFeeds) { feed in
                feedRow(for: feed)
            }

            // Show toggle button at bottom if Alt feeds exist
            if hasAltFeeds {
                Button {
                    toggleAltFeeds()
                } label: {
                    HStack {
                        Spacer()
                        Image(systemName: showAltFeeds ? "eye.slash" : "eye.fill")
                        Text(showAltFeeds ? "Hide Alt Feeds" : "Show Alt Feeds")
                            .font(.subheadline)
                        Spacer()
                    }
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 12)
                }
            }
        }
    }

    @ViewBuilder
    private func feedRow(for feed: Feed) -> some View {
        #if os(macOS)
        // macOS: Use button + sheet to avoid nested navigation issues
        Button {
            selectedFeedForArticles = feed
        } label: {
            HStack {
                feedRowLabel(for: feed)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            feedContextMenu(for: feed)
        }
        #else
        // iOS: Use NavigationLink for proper push navigation
        NavigationLink {
            FeedArticlesView(feed: feed)
        } label: {
            feedRowLabel(for: feed)
        }
        .contextMenu {
            feedContextMenu(for: feed)
        }
        .swipeActions(edge: .trailing) {
            feedSwipeActions(for: feed)
        }
        .swipeActions(edge: .leading) {
            Button {
                newsletterFeedID = feed.id
            } label: {
                Label("Newsletter", systemImage: "newspaper")
            }
            .tint(accentColor.color)
        }
        #endif
    }

    @ViewBuilder
    private func feedRowLabel(for feed: Feed) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(feed.title)
                    .font(.headline)
                Spacer()
                unreadBadge(for: feed)
            }
            Text(feed.url)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Text(FeedCategory(rawValue: feed.category)?.localizedName ?? feed.category)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(accentColor.color.opacity(0.2))
                    .cornerRadius(4)

                if feed.opmlSubscriptionURL != nil {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if let lastFetched = feed.lastFetched {
                    Text("Last synced: \(lastFetched, style: .relative) ago")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func feedContextMenu(for feed: Feed) -> some View {
        Button {
            editingFeedID = feed.id
        } label: {
            Label("Edit Feed", systemImage: "pencil")
        }

        Button(role: .destructive) {
            deleteFeed(feed)
        } label: {
            Label("Delete Feed", systemImage: "trash")
        }
    }

    @ViewBuilder
    private func feedSwipeActions(for feed: Feed) -> some View {
        Button(role: .destructive) {
            deleteFeed(feed)
        } label: {
            Label("Delete", systemImage: "trash")
        }

        Button {
            editingFeedID = feed.id
        } label: {
            Label("Edit", systemImage: "pencil")
        }
        .tint(.blue)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        #if os(iOS)
        ToolbarItem(placement: .topBarTrailing) {
            addFeedButton
        }
        ToolbarItem(placement: .topBarLeading) {
            feedMenu
        }
        #else
        ToolbarItem(placement: .primaryAction) {
            addFeedButton
        }
        ToolbarItem(placement: .automatic) {
            feedMenu
        }
        #endif
    }

    private var addFeedButton: some View {
        Button {
            showingAddFeed = true
        } label: {
            Label("Add Feed", systemImage: "plus")
        }
    }

    private var feedMenu: some View {
        Menu {
            Button {
                // Use BackgroundSyncManager for off-main-thread sync
                BackgroundSyncManager.shared.triggerManualSync()
            } label: {
                Label("Sync All Feeds", systemImage: "arrow.clockwise")
            }
            .disabled(syncManager.isSyncInProgress)

            Divider()

            Button {
                showingImportOPML = true
            } label: {
                Label("Import OPML", systemImage: "square.and.arrow.down")
            }

            Button {
                showingSubscribeOPML = true
            } label: {
                Label("Subscribe to OPML", systemImage: "antenna.radiowaves.left.and.right")
            }

            Button {
                exportOPML()
            } label: {
                Label("Export OPML", systemImage: "square.and.arrow.up")
            }

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

    @ViewBuilder
    private var syncingOverlay: some View {
        if feedManager.isSyncing {
            VStack(spacing: 8) {
                ProgressView()
                if let progress = feedManager.syncProgress {
                    Text(progress)
                        .font(.subheadline)
                } else {
                    Text("Syncing feeds...")
                        .font(.subheadline)
                }
            }
            .padding()
            .background(.regularMaterial)
            .cornerRadius(10)
        }
    }

    @ViewBuilder
    private var addFeedSheet: some View {
        #if os(macOS)
        macOSAddFeedSheet
        #else
        iOSAddFeedSheet
        #endif
    }

    #if os(macOS)
    @ViewBuilder
    private var macOSAddFeedSheet: some View {
        VStack(spacing: 0) {
            // Header with icon
            VStack(spacing: 8) {
                Image(systemName: feedType == .rss ? "dot.radiowaves.up.forward" : "globe")
                    .font(.system(size: 36))
                    .foregroundStyle(accentColor.color)
                    .frame(width: 56, height: 56)
                    .background(accentColor.color.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                Text(feedType == .rss ? "Add RSS Feed" : "Add Reddit Feed")
                    .font(.title2.weight(.semibold))

                Text(feedType == .rss ? "Subscribe to your favorite websites" : "Follow your favorite communities")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 24)
            .padding(.bottom, 20)

            // Content
            VStack(alignment: .leading, spacing: 20) {
                // Feed Type Picker
                Picker("", selection: $feedType) {
                    ForEach(FeedType.allCases, id: \.self) { type in
                        Label(type.rawValue, systemImage: type == .rss ? "dot.radiowaves.up.forward" : "globe")
                            .tag(type)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                // Feed URL/Subreddit
                VStack(alignment: .leading, spacing: 6) {
                    Label(feedType == .rss ? "Feed URL" : "Subreddit", systemImage: feedType == .rss ? "link" : "number")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)

                    if feedType == .rss {
                        TextField("https://example.com/feed.xml", text: $newFeedURL)
                            .textFieldStyle(.roundedBorder)
                            .autocorrectionDisabled()
                    } else {
                        HStack(spacing: 4) {
                            Text("r/")
                                .foregroundStyle(.secondary)
                                .font(.system(.body, design: .monospaced))
                            TextField("subreddit", text: $subredditName)
                                .textFieldStyle(.roundedBorder)
                                .autocorrectionDisabled()
                        }
                    }

                    if feedType == .reddit {
                        Text("Enter the subreddit name (e.g., technology, news)")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }

                // Category
                VStack(alignment: .leading, spacing: 6) {
                    Label("Category", systemImage: "folder")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)

                    Toggle("Use custom category", isOn: $useCustomCategory)
                        .toggleStyle(.checkbox)

                    if useCustomCategory {
                        TextField("Category name", text: $customCategory)
                            .textFieldStyle(.roundedBorder)
                    } else {
                        Picker("", selection: $newFeedCategory) {
                            ForEach(categoryManager.allCategories, id: \.self) { category in
                                Text(category).tag(category)
                            }
                        }
                        .labelsHidden()
                    }
                }

                // Error message
                if let error = addFeedError {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                        Text(error)
                            .font(.caption)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(8)
                }
            }
            .padding(.horizontal, 24)

            Spacer()

            // Footer buttons
            HStack {
                Button("Cancel") {
                    showingAddFeed = false
                    resetAddFeedForm()
                }
                .keyboardShortcut(.escape, modifiers: [])

                Spacer()

                Button {
                    addFeed()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle.fill")
                        Text("Add Feed")
                    }
                }
                .keyboardShortcut(.return, modifiers: [])
                .disabled(isFieldsInvalid() || isAddingFeed)
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .frame(width: 420, height: 440)
        .overlay {
            if isAddingFeed {
                ZStack {
                    Color.black.opacity(0.3)
                    VStack(spacing: 12) {
                        ProgressView()
                            .scaleEffect(1.2)
                        Text("Adding feed...")
                            .font(.subheadline)
                    }
                    .padding(24)
                    .background(.regularMaterial)
                    .cornerRadius(12)
                }
            }
        }
    }
    #endif

    #if os(iOS)
    @ViewBuilder
    private var iOSAddFeedSheet: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Type", selection: $feedType) {
                        ForEach(FeedType.allCases, id: \.self) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Feed Type")
                }

                Section {
                    if feedType == .rss {
                        TextField("RSS Feed URL", text: $newFeedURL)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.URL)
                            .autocorrectionDisabled()
                    } else {
                        HStack {
                            Text("r/")
                                .foregroundStyle(.secondary)
                            TextField("Subreddit Name", text: $subredditName)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }
                    }
                } header: {
                    Text("Feed Details")
                } footer: {
                    if feedType == .reddit {
                        Text("Enter the subreddit name without 'r/' (e.g., 'politics', 'technology')")
                            .font(.caption)
                    }
                }

                Section {
                    Toggle("Use Custom Category", isOn: $useCustomCategory)

                    if useCustomCategory {
                        TextField("Custom Category Name", text: $customCategory)
                            .textInputAutocapitalization(.never)
                    } else {
                        Picker("Category", selection: $newFeedCategory) {
                            ForEach(categoryManager.allCategories, id: \.self) { category in
                                Text(category).tag(category)
                            }
                        }
                    }
                } header: {
                    Text("Category")
                } footer: {
                    if useCustomCategory {
                        Text("Enter a custom category name for this feed")
                    } else {
                        Text("Select from predefined categories")
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
            .navigationTitle(feedType == .rss ? "Add RSS Feed" : "Add Reddit Feed")
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
                    .disabled(isFieldsInvalid() || isAddingFeed)
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
    #endif

    @ViewBuilder
    private var importOPMLSheet: some View {
        #if os(macOS)
        macOSImportOPMLSheet
        #else
        iOSImportOPMLSheet
        #endif
    }

    #if os(macOS)
    @ViewBuilder
    private var macOSImportOPMLSheet: some View {
        VStack(spacing: 0) {
            // Header with icon
            VStack(spacing: 8) {
                Image(systemName: "square.and.arrow.down")
                    .font(.system(size: 36))
                    .foregroundStyle(accentColor.color)
                    .frame(width: 56, height: 56)
                    .background(accentColor.color.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                Text("Import OPML")
                    .font(.title2.weight(.semibold))

                Text("Import feeds from another RSS reader")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 24)
            .padding(.bottom, 20)

            // Content
            VStack(alignment: .leading, spacing: 16) {
                // Instructions
                HStack(spacing: 12) {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(accentColor.color)
                    Text("Export an OPML file from your previous reader, then paste its contents below.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .background(accentColor.color.opacity(0.05))
                .cornerRadius(8)

                // Text editor
                VStack(alignment: .leading, spacing: 6) {
                    Label("OPML Content", systemImage: "doc.text")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)

                    TextEditor(text: $opmlText)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 180)
                        .padding(8)
                        .background(Color(NSColor.textBackgroundColor))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                        )
                }

                // Import result
                if let error = importError {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: error.contains("✅") ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(error.contains("✅") ? .green : .red)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(error)
                                .font(.caption)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(error, forType: .string)
                            } label: {
                                Label("Copy Summary", systemImage: "doc.on.doc")
                                    .font(.caption)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding(10)
                    .background(error.contains("✅") ? Color.green.opacity(0.1) : Color.red.opacity(0.1))
                    .cornerRadius(8)
                }
            }
            .padding(.horizontal, 24)

            Spacer()

            // Footer buttons
            HStack {
                Button("Cancel") {
                    showingImportOPML = false
                    opmlText = ""
                    importError = nil
                }
                .keyboardShortcut(.escape, modifiers: [])

                Spacer()

                Button {
                    importOPML()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "square.and.arrow.down")
                        Text("Import")
                    }
                }
                .keyboardShortcut(.return, modifiers: [])
                .disabled(opmlText.isEmpty || isImporting)
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .frame(width: 480, height: 520)
        .overlay {
            if isImporting {
                ZStack {
                    Color.black.opacity(0.3)
                    VStack(spacing: 12) {
                        ProgressView()
                            .scaleEffect(1.2)
                        Text(importProgress ?? "Importing feeds...")
                            .font(.subheadline)
                    }
                    .padding(24)
                    .background(.regularMaterial)
                    .cornerRadius(12)
                }
            }
        }
    }
    #endif

    #if os(iOS)
    @ViewBuilder
    private var iOSImportOPMLSheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $opmlText)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 200)
                } header: {
                    Text("Paste OPML Content")
                } footer: {
                    Text("Export an OPML file from your previous reader, then paste its contents above.")
                }

                if let error = importError {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(error)
                                .foregroundColor(error.contains("✅") ? .primary : .red)
                                .font(.caption)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            Button {
                                UIPasteboard.general.string = error
                            } label: {
                                HStack {
                                    Image(systemName: "doc.on.doc")
                                    Text("Copy Summary")
                                }
                                .font(.caption)
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                        }
                    } header: {
                        Text("Import Summary")
                    }
                }
            }
            .navigationTitle("Import OPML")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showingImportOPML = false
                        opmlText = ""
                        importError = nil
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Import") {
                        importOPML()
                    }
                    .disabled(opmlText.isEmpty || isImporting)
                }
            }
            .overlay {
                if isImporting {
                    VStack(spacing: 8) {
                        ProgressView()
                        Text(importProgress ?? "Importing feeds...")
                            .font(.subheadline)
                    }
                    .padding()
                    .background(.regularMaterial)
                    .cornerRadius(10)
                }
            }
        }
    }
    #endif

    @ViewBuilder
    private var editFeedSheet: some View {
        if let feedID = editingFeedID,
           let feed = feeds.first(where: { $0.id == feedID }) {
            NavigationStack {
                EditFeedView(feed: feed, modelContext: modelContext)
            }
        }
    }

    @ViewBuilder
    private var newsletterSheet: some View {
        if let feedID = newsletterFeedID,
           let feed = feeds.first(where: { $0.id == feedID }) {
            NavigationStack {
                FeedNewsletterView(feed: feed)
            }
        }
    }

    // MARK: - Subscribe to OPML Sheet

    @ViewBuilder
    private var subscribeOPMLSheet: some View {
        #if os(macOS)
        macOSSubscribeOPMLSheet
        #else
        iOSSubscribeOPMLSheet
        #endif
    }

    #if os(macOS)
    @ViewBuilder
    private var macOSSubscribeOPMLSheet: some View {
        VStack(spacing: 0) {
            // Header with icon
            VStack(spacing: 8) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 36))
                    .foregroundStyle(accentColor.color)
                    .frame(width: 56, height: 56)
                    .background(accentColor.color.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                Text("Subscribe to OPML")
                    .font(.title2.weight(.semibold))

                Text("Automatically sync feeds from a remote OPML file")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 24)
            .padding(.bottom, 20)

            // Content
            VStack(alignment: .leading, spacing: 16) {
                // URL field
                VStack(alignment: .leading, spacing: 6) {
                    Label("OPML URL", systemImage: "link")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)

                    TextField("https://example.com/feeds.opml", text: $subscribeOPMLURL)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                }

                // Category
                VStack(alignment: .leading, spacing: 6) {
                    Label("Default Category", systemImage: "folder")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)

                    Picker("", selection: $subscribeOPMLCategory) {
                        ForEach(categoryManager.allCategories, id: \.self) { category in
                            Text(category).tag(category)
                        }
                    }
                    .labelsHidden()

                    Text("New feeds from this OPML will be assigned this category")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                // Existing subscriptions
                if !opmlSubscriptions.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Active Subscriptions", systemImage: "list.bullet")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)

                        ForEach(opmlSubscriptions) { sub in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(sub.title)
                                        .font(.subheadline)
                                    if let lastFetched = sub.lastFetched {
                                        Text("Last synced: \(lastFetched, style: .relative) ago")
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                                Spacer()
                                Button(role: .destructive) {
                                    unsubscribeOPML(sub)
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.caption)
                                }
                                .buttonStyle(.borderless)
                            }
                            .padding(8)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(6)
                        }
                    }
                }

                // Error message
                if let error = subscribeError {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                        Text(error)
                            .font(.caption)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(8)
                }
            }
            .padding(.horizontal, 24)

            Spacer()

            // Footer buttons
            HStack {
                Button("Cancel") {
                    showingSubscribeOPML = false
                    resetSubscribeOPMLForm()
                }
                .keyboardShortcut(.escape, modifiers: [])

                Spacer()

                Button {
                    subscribeToOPML()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle.fill")
                        Text("Subscribe")
                    }
                }
                .keyboardShortcut(.return, modifiers: [])
                .disabled(subscribeOPMLURL.isEmpty || isSubscribing)
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .frame(width: 460, height: 520)
        .overlay {
            if isSubscribing {
                ZStack {
                    Color.black.opacity(0.3)
                    VStack(spacing: 12) {
                        ProgressView()
                            .scaleEffect(1.2)
                        Text("Subscribing...")
                            .font(.subheadline)
                    }
                    .padding(24)
                    .background(.regularMaterial)
                    .cornerRadius(12)
                }
            }
        }
    }
    #endif

    #if os(iOS)
    @ViewBuilder
    private var iOSSubscribeOPMLSheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("OPML URL", text: $subscribeOPMLURL)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                } header: {
                    Text("OPML URL")
                } footer: {
                    Text("Enter the URL of a remote OPML file. Feeds will be synced automatically.")
                }

                Section {
                    Picker("Default Category", selection: $subscribeOPMLCategory) {
                        ForEach(categoryManager.allCategories, id: \.self) { category in
                            Text(category).tag(category)
                        }
                    }
                } header: {
                    Text("Category")
                } footer: {
                    Text("New feeds from this OPML will be assigned this category.")
                }

                if !opmlSubscriptions.isEmpty {
                    Section {
                        ForEach(opmlSubscriptions) { sub in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(sub.title)
                                    .font(.subheadline)
                                if let lastFetched = sub.lastFetched {
                                    Text("Last synced: \(lastFetched, style: .relative) ago")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .onDelete { indexSet in
                            for index in indexSet {
                                unsubscribeOPML(opmlSubscriptions[index])
                            }
                        }
                    } header: {
                        Text("Active Subscriptions")
                    }
                }

                if let error = subscribeError {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Subscribe to OPML")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showingSubscribeOPML = false
                        resetSubscribeOPMLForm()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Subscribe") {
                        subscribeToOPML()
                    }
                    .disabled(subscribeOPMLURL.isEmpty || isSubscribing)
                }
            }
            .overlay {
                if isSubscribing {
                    ProgressView("Subscribing...")
                        .padding()
                        .background(.regularMaterial)
                        .cornerRadius(10)
                }
            }
        }
    }
    #endif

    @ViewBuilder
    private func unreadBadge(for feed: Feed) -> some View {
        if let articles = feed.articles {
            let unreadCount = articles.filter { !$0.isRead }.count
            if unreadCount > 0 {
                Text("\(unreadCount)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(accentColor.color)
                    .cornerRadius(10)
            }
        }
    }

    private func addFeed() {
        isAddingFeed = true
        addFeedError = nil

        Task {
            do {
                let category = useCustomCategory 
                    ? customCategory.trimmingCharacters(in: .whitespacesAndNewlines)
                    : newFeedCategory

                // Construct the URL based on feed type
                let feedURL: String
                if feedType == .reddit {
                    // Clean up the subreddit name (remove any leading r/ or /)
                    let cleanSubreddit = subredditName
                        .trimmingCharacters(in: .whitespaces)
                        .replacingOccurrences(of: "^r/", with: "", options: .regularExpression)
                        .replacingOccurrences(of: "^/", with: "", options: .regularExpression)
                    feedURL = "https://www.reddit.com/r/\(cleanSubreddit)/.json"
                } else {
                    feedURL = newFeedURL
                }

                _ = try await feedManager.addFeed(url: feedURL, category: category)

                // Save custom category to CategoryManager if it's a custom category
                if useCustomCategory {
                    _ = categoryManager.addCustomCategory(category)
                }

                showingAddFeed = false
                resetAddFeedForm()
            } catch {
                addFeedError = error.localizedDescription
            }
            isAddingFeed = false
        }
    }

    private func isFieldsInvalid() -> Bool {
        if feedType == .rss {
            return newFeedURL.isEmpty || (useCustomCategory && customCategory.isEmpty)
        } else {
            return subredditName.isEmpty || (useCustomCategory && customCategory.isEmpty)
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
        feedType = .rss
        newFeedURL = ""
        subredditName = ""
        newFeedCategory = "General"
        customCategory = ""
        useCustomCategory = false
        addFeedError = nil
    }

    private func clearAllData() {
        do {
            try modelContext.clearAllData()
        } catch {
            print("Error clearing data: \(error.localizedDescription)")
        }
    }

    private func exportOPML() {
        let opml = generateOPML(from: feeds)
        #if os(iOS)
        UIPasteboard.general.string = opml
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(opml, forType: .string)
        #endif
        showingExportConfirmation = true
    }

    private func generateOPML(from feeds: [Feed]) -> String {
        var opml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <opml version="2.0">
            <head>
                <title>Today RSS Feeds</title>
                <dateCreated>\(ISO8601DateFormatter().string(from: Date()))</dateCreated>
            </head>
            <body>

        """

        // Group feeds by category
        let feedsByCategory = Dictionary(grouping: feeds, by: { $0.category })

        for (category, categoryFeeds) in feedsByCategory.sorted(by: { $0.key < $1.key }) {
            opml += "        <outline text=\"\(category.capitalized)\" title=\"\(category.capitalized)\">\n"

            for feed in categoryFeeds {
                let escapedTitle = feed.title.replacingOccurrences(of: "&", with: "&amp;")
                    .replacingOccurrences(of: "\"", with: "&quot;")
                    .replacingOccurrences(of: "<", with: "&lt;")
                    .replacingOccurrences(of: ">", with: "&gt;")

                let escapedURL = feed.url.replacingOccurrences(of: "&", with: "&amp;")
                    .replacingOccurrences(of: "\"", with: "&quot;")

                opml += "            <outline type=\"rss\" text=\"\(escapedTitle)\" title=\"\(escapedTitle)\" xmlUrl=\"\(escapedURL)\" />\n"
            }

            opml += "        </outline>\n"
        }

        opml += """
            </body>
        </opml>
        """

        return opml
    }

    private func importOPML() {
        isImporting = true
        importError = nil
        importProgress = nil

        print("📥 OPML Import: Starting import process...")
        print("📥 OPML Import: Input length: \(opmlText.count) characters")

        Task {
            do {
                print("📥 OPML Import: Parsing OPML...")
                let parser = OPMLParser()
                let parsedFeeds = try parser.parse(opmlText)
                let feedsToImport = parsedFeeds.map { (url: $0.url, title: $0.title, category: $0.category) }
                let totalFeeds = feedsToImport.count

                print("📥 OPML Import: Found \(totalFeeds) feeds to import")

                // Log first few feeds for debugging
                for (index, (url, title, category)) in feedsToImport.prefix(5).enumerated() {
                    print("📥 OPML Import: Feed \(index + 1): \(title) | \(url) | \(category)")
                }

                await MainActor.run {
                    importProgress = "Found \(totalFeeds) feeds to import..."
                }

                var successCount = 0
                var failedCount = 0
                var skippedCount = 0
                var failedFeeds: [(String, String)] = [] // Track failed feeds with errors

                // Import each feed
                for (index, (url, title, category)) in feedsToImport.enumerated() {
                    // Update progress
                    await MainActor.run {
                        importProgress = "Importing \(index + 1) of \(totalFeeds): \(title)"
                    }

                    print("📥 OPML Import: [\(index + 1)/\(totalFeeds)] Processing: \(title)")

                    // Check if feed already exists
                    if feeds.contains(where: { $0.url == url }) {
                        skippedCount += 1
                        print("⏭️  OPML Import: Skipped (duplicate): \(title)")
                        continue
                    }

                    do {
                        print("📥 OPML Import: Adding feed: \(title)")
                        _ = try await feedManager.addFeed(url: url, category: category)
                        successCount += 1
                        print("✅ OPML Import: Success: \(title)")
                    } catch {
                        // Continue even if one feed fails
                        failedCount += 1
                        let errorMsg = error.localizedDescription
                        failedFeeds.append((title, errorMsg))
                        print("❌ OPML Import: Failed: \(title)")
                        print("   Error: \(errorMsg)")
                    }
                }

                print("📊 OPML Import: Complete - Success: \(successCount), Failed: \(failedCount), Skipped: \(skippedCount)")

                // Log failed feeds for debugging
                if !failedFeeds.isEmpty {
                    print("❌ Failed feeds:")
                    for (title, error) in failedFeeds.prefix(10) {
                        print("   - \(title): \(error)")
                    }
                }

                await MainActor.run {
                    showingImportOPML = false
                    opmlText = ""
                    isImporting = false
                    importProgress = nil

                    // Show detailed summary
                    var summary = "✅ Imported \(successCount) feeds"
                    if skippedCount > 0 {
                        summary += "\n⏭️  Skipped \(skippedCount) duplicates"
                    }

                    if failedCount > 0 {
                        summary += "\n\n❌ \(failedCount) feeds failed:"

                        // Show up to 10 failed feeds with reasons
                        for (title, error) in failedFeeds.prefix(10) {
                            // Simplify common error messages
                            let simplifiedError: String
                            if error.contains("Invalid RSS") || error.contains("not a valid RSS") {
                                simplifiedError = "Invalid RSS feed"
                            } else if error.contains("network") || error.contains("Network") {
                                simplifiedError = "Network error"
                            } else if error.contains("timeout") || error.contains("timed out") {
                                simplifiedError = "Connection timeout"
                            } else if error.contains("404") {
                                simplifiedError = "Feed not found"
                            } else if error.contains("403") || error.contains("401") {
                                simplifiedError = "Access denied"
                            } else if error.contains("500") {
                                simplifiedError = "Server error"
                            } else {
                                // Keep short error message (first 50 chars)
                                simplifiedError = String(error.prefix(50))
                            }
                            summary += "\n  • \(title): \(simplifiedError)"
                        }

                        if failedCount > 10 {
                            summary += "\n  ... and \(failedCount - 10) more"
                        }
                    }

                    // Always show summary
                    importError = summary
                    print("📥 OPML Import: Showing summary: \(summary)")
                }
            } catch {
                print("❌ OPML Import: Parse error: \(error.localizedDescription)")
                await MainActor.run {
                    importError = error.localizedDescription
                    isImporting = false
                    importProgress = nil
                }
            }
        }
    }

    private func toggleAltFeeds() {
        showAltFeeds.toggle()
    }

    // MARK: - OPML Subscription Actions

    private func subscribeToOPML() {
        isSubscribing = true
        subscribeError = nil

        Task {
            do {
                let manager = OPMLSubscriptionManager(modelContext: modelContext, feedManager: feedManager)
                _ = try await manager.addSubscription(
                    url: subscribeOPMLURL,
                    defaultCategory: subscribeOPMLCategory
                )
                showingSubscribeOPML = false
                resetSubscribeOPMLForm()
            } catch {
                subscribeError = error.localizedDescription
            }
            isSubscribing = false
        }
    }

    private func unsubscribeOPML(_ subscription: OPMLSubscription) {
        do {
            let manager = OPMLSubscriptionManager(modelContext: modelContext, feedManager: feedManager)
            try manager.removeSubscription(subscription, removeFeeds: false)
        } catch {
            opmlActionError = "Failed to unsubscribe: \(error.localizedDescription)"
        }
    }

    private func resetSubscribeOPMLForm() {
        subscribeOPMLURL = ""
        subscribeOPMLCategory = "General"
        subscribeError = nil
    }

    private var feedCountsBySubscriptionURL: [String: Int] {
        var counts: [String: Int] = [:]
        for feed in feeds {
            if let url = feed.opmlSubscriptionURL {
                counts[url, default: 0] += 1
            }
        }
        return counts
    }

    private func managedFeedCount(for subscription: OPMLSubscription) -> String {
        let count = feedCountsBySubscriptionURL[subscription.url] ?? 0
        return "\(count) feed\(count == 1 ? "" : "s")"
    }

    private func syncSingleSubscription(_ subscription: OPMLSubscription) {
        Task {
            do {
                let manager = OPMLSubscriptionManager(modelContext: modelContext, feedManager: feedManager)
                try await manager.syncSubscription(subscription)
            } catch {
                opmlActionError = "Failed to sync: \(error.localizedDescription)"
            }
        }
    }
}

// MARK: - Edit Feed View
struct EditFeedView: View {
    @Environment(\.dismiss) private var dismiss
    let feed: Feed
    let modelContext: ModelContext
    @ObservedObject private var categoryManager = CategoryManager.shared

    @State private var title: String
    @State private var url: String
    @State private var category: String
    @State private var useCustomCategory: Bool
    @AppStorage("accentColor") private var accentColor: AccentColorOption = .orange

    init(feed: Feed, modelContext: ModelContext) {
        self.feed = feed
        self.modelContext = modelContext
        _title = State(initialValue: feed.title)
        _url = State(initialValue: feed.url)
        _category = State(initialValue: feed.category)
        // Check if current category is a predefined one
        let isPredefined = FeedCategory(rawValue: feed.category) != nil
        _useCustomCategory = State(initialValue: !isPredefined)
    }

    var body: some View {
        #if os(macOS)
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Edit Feed")
                        .font(.headline)
                    Text(feed.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Content
            VStack(alignment: .leading, spacing: 16) {
                // Details section
                VStack(alignment: .leading, spacing: 8) {
                    Text("Feed Details")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 16, verticalSpacing: 14) {
                        GridRow {
                            Text("Title")
                                .frame(width: 90, alignment: .trailing)
                                .foregroundStyle(.secondary)
                            TextField("Feed Title", text: $title)
                                .textFieldStyle(.roundedBorder)
                        }
                        GridRow {
                            Text("URL")
                                .frame(width: 90, alignment: .trailing)
                                .foregroundStyle(.secondary)
                            TextField("RSS Feed URL", text: $url)
                                .textFieldStyle(.roundedBorder)
                                .autocorrectionDisabled()
                        }
                    }
                    .padding(.top, 4)
                    .padding(.leading, 4)
                }

                // Category section
                VStack(alignment: .leading, spacing: 8) {
                    Text("Category")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Toggle("Use Custom Category", isOn: $useCustomCategory)
                        .toggleStyle(.checkbox)

                    if useCustomCategory {
                        TextField("Custom Category Name", text: $category)
                            .textFieldStyle(.roundedBorder)
                    } else {
                        Picker("Category", selection: $category) {
                            ForEach(categoryManager.allCategories, id: \.self) { category in
                                Text(category).tag(category)
                            }
                        }
                        .labelsHidden()
                    }

                    Text(useCustomCategory ? "Enter a custom category name for this feed" : "Select from predefined categories")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(.top, 6)

                Spacer(minLength: 0)
            }
            .padding(20)

            Divider()

            // Footer
            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.escape, modifiers: [])

                Spacer()

                Button("Save") { saveFeed() }
                    .keyboardShortcut(.return, modifiers: [])
                    .disabled(title.isEmpty || url.isEmpty || category.isEmpty)
                    .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(NSColor.windowBackgroundColor))
        }
        .tint(accentColor.color)
        .frame(width: 440, height: 400)
        #else
        // iOS: keep the existing Form-based layout
        Form {
            Section {
                TextField("Feed Title", text: $title)
                TextField("RSS Feed URL", text: $url)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } header: {
                Text("Feed Details")
            }

            Section {
                Toggle("Use Custom Category", isOn: $useCustomCategory)
                if useCustomCategory {
                    TextField("Custom Category Name", text: $category)
                        .textInputAutocapitalization(.never)
                } else {
                    Picker("Category", selection: $category) {
                        ForEach(categoryManager.allCategories, id: \.self) { category in
                            Text(category).tag(category)
                        }
                    }
                }
            } header: {
                Text("Category")
            } footer: {
                if useCustomCategory {
                    Text("Enter a custom category name for this feed")
                } else {
                    Text("Select from predefined categories")
                }
            }
        }
        .navigationTitle("Edit Feed")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { saveFeed() }
                    .disabled(title.isEmpty || url.isEmpty || category.isEmpty)
            }
        }
        #endif
    }

    private func saveFeed() {
        feed.title = title
        feed.url = url

        // Trim custom category to ensure consistency with CategoryManager
        let trimmedCategory = useCustomCategory
            ? category.trimmingCharacters(in: .whitespacesAndNewlines)
            : category
        feed.category = trimmedCategory

        // Save custom category to CategoryManager if it's a custom category
        if useCustomCategory {
            _ = categoryManager.addCustomCategory(trimmedCategory)
        }

        do {
            try modelContext.save()
            dismiss()
        } catch {
            print("Error saving feed: \(error.localizedDescription)")
        }
    }
}

// MARK: - Feed Articles View
struct FeedArticlesView: View {
    let feed: Feed
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Article.publishedDate, order: .reverse) private var allArticles: [Article]
    @AppStorage("accentColor") private var accentColor: AccentColorOption = .orange

    @State private var showReadArticles = false
    @State private var searchText = ""
    @State private var navigationState: NavigationState?
    @AppStorage("fontOption") private var fontOption: FontOption = .serif

    // For macOS: use parent's selectedArticle to show in detail column
    #if os(macOS)
    @Binding var selectedArticle: Article?

    init(feed: Feed, selectedArticle: Binding<Article?>) {
        self.feed = feed
        _selectedArticle = selectedArticle
    }
    #else
    init(feed: Feed) {
        self.feed = feed
    }
    #endif

    // Navigation state that bundles article ID with context
    struct NavigationState: Hashable {
        let articleID: PersistentIdentifier
        let context: [PersistentIdentifier]
    }

    private var filteredArticles: [Article] {
        var articles = allArticles.filter { $0.feed?.id == feed.id }

        if !showReadArticles {
            articles = articles.filter { !$0.isRead }
        }

        // Filter by search text
        if !searchText.isEmpty {
            articles = articles.filter {
                $0.title.localizedCaseInsensitiveContains(searchText) ||
                $0.articleDescription?.localizedCaseInsensitiveContains(searchText) == true ||
                $0.content?.localizedCaseInsensitiveContains(searchText) == true
            }
        }

        return articles
    }

    private var unreadCount: Int {
        allArticles.filter { $0.feed?.id == feed.id && !$0.isRead }.count
    }

    var body: some View {
        VStack(spacing: 0) {
            // Show r/subreddit header for Reddit feeds
            if feed.isRedditFeed, let subreddit = feed.redditSubreddit {
                Text("r/\(subreddit)")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(accentColor.color)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
                    #if os(iOS)
                    .background(Color(.systemGroupedBackground))
                    #else
                    .background(Color(NSColor.controlBackgroundColor))
                    #endif
            }

            Group {
                if filteredArticles.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: showReadArticles ? "tray" : "checkmark.circle")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                        Text(showReadArticles ? "No articles in this feed" : "All caught up!")
                            .font(.headline)
                        Text(showReadArticles ? "Try syncing the feed to fetch new articles" : "No unread articles from this feed")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(filteredArticles, id: \.persistentModelID) { article in
                        Button {
                            #if os(macOS)
                            // Set parent's selectedArticle to show in detail column
                            selectedArticle = article
                            #else
                            // Capture navigation context when article is selected
                            let context = filteredArticles.map { $0.persistentModelID }
                            navigationState = NavigationState(
                                articleID: article.persistentModelID,
                                context: context
                            )
                            #endif
                        } label: {
                            HStack {
                                ArticleRowView(article: article, fontOption: fontOption, isInFeedView: true)
                                Spacer()
                                #if os(iOS)
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                #endif
                            }
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .leading) {
                            Button {
                                article.isRead.toggle()
                                try? modelContext.save()
                            } label: {
                                Label(
                                    article.isRead ? "Unread" : "Read",
                                    systemImage: article.isRead ? "envelope.badge" : "envelope.open"
                                )
                            }
                            .tint(.blue)
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        }
        .navigationTitle(feed.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .searchable(text: $searchText, prompt: "Search in \(feed.title)")
        .toolbar {
            #if os(iOS)
            ToolbarItem(placement: .topBarTrailing) {
                feedDetailMenu
            }
            #else
            ToolbarItem(placement: .primaryAction) {
                feedDetailMenu
            }
            #endif
        }
        #if os(iOS)
        .navigationDestination(item: $navigationState) { state in
            if let article = modelContext.model(for: state.articleID) as? Article {
                // For Reddit posts, show combined post + comments view
                if article.isRedditPost {
                    if !state.context.isEmpty,
                       let currentIndex = state.context.firstIndex(of: state.articleID) {
                        let previousIndex = currentIndex - 1
                        let nextIndex = currentIndex + 1
                        let previousArticleID = previousIndex >= 0 ? state.context[previousIndex] : nil
                        let nextArticleID = nextIndex < state.context.count ? state.context[nextIndex] : nil

                        RedditPostView(
                            article: article,
                            previousArticleID: previousArticleID,
                            nextArticleID: nextArticleID,
                            onNavigateToPrevious: { prevID in
                                Task { @MainActor in
                                    try? await Task.sleep(nanoseconds: 50_000_000)
                                    navigationState = NavigationState(articleID: prevID, context: state.context)
                                }
                            },
                            onNavigateToNext: { nextID in
                                Task { @MainActor in
                                    try? await Task.sleep(nanoseconds: 50_000_000)
                                    navigationState = NavigationState(articleID: nextID, context: state.context)
                                }
                            }
                        )
                        .id(state.articleID)  // Force view refresh when article changes
                    } else {
                        RedditPostView(
                            article: article,
                            previousArticleID: nil,
                            nextArticleID: nil,
                            onNavigateToPrevious: { _ in },
                            onNavigateToNext: { _ in }
                        )
                    }
                }
                // Use the captured navigation context
                else if !state.context.isEmpty,
                   let currentIndex = state.context.firstIndex(of: state.articleID) {
                    let previousIndex = currentIndex - 1
                    let nextIndex = currentIndex + 1
                    let previousArticleID = previousIndex >= 0 ? state.context[previousIndex] : nil
                    let nextArticleID = nextIndex < state.context.count ? state.context[nextIndex] : nil

                    ArticleDetailSimple(
                        article: article,
                        previousArticleID: previousArticleID,
                        nextArticleID: nextArticleID,
                        onNavigateToPrevious: { prevID in
                            Task { @MainActor in
                                try? await Task.sleep(nanoseconds: 50_000_000)
                                navigationState = NavigationState(articleID: prevID, context: state.context)
                            }
                        },
                        onNavigateToNext: { nextID in
                            Task { @MainActor in
                                try? await Task.sleep(nanoseconds: 50_000_000)
                                navigationState = NavigationState(articleID: nextID, context: state.context)
                            }
                        }
                    )
                } else {
                    ArticleDetailSimple(
                        article: article,
                        previousArticleID: nil,
                        nextArticleID: nil,
                        onNavigateToPrevious: { _ in },
                        onNavigateToNext: { _ in }
                    )
                }
            }
        }
        #endif
    }

    private var feedDetailMenu: some View {
        Menu {
            Button {
                showReadArticles.toggle()
            } label: {
                Label(showReadArticles ? "Hide Read" : "Show Read",
                      systemImage: showReadArticles ? "eye.slash" : "eye")
            }

            if unreadCount > 0 {
                Divider()
                Button {
                    markAllAsRead()
                } label: {
                    Label("Mark All as Read", systemImage: "checkmark.circle")
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
    }

    private func markAllAsRead() {
        for article in filteredArticles where !article.isRead {
            article.isRead = true
        }
        try? modelContext.save()
    }
}

// MARK: - Feed Newsletter View
struct FeedNewsletterView: View {
    let feed: Feed
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Article.publishedDate, order: .reverse) private var allArticles: [Article]

    @State private var isGenerating = false
    @State private var newsletterMessage: ChatMessage?

    private var feedArticles: [Article] {
        // Get articles from this feed, prioritizing unread then by date
        let feedArticles = allArticles.filter { article in
            article.feed?.id == feed.id
        }

        // Sort: unread first, then by published date (newest first)
        let sortedArticles = feedArticles.sorted { a, b in
            if a.isRead != b.isRead {
                return !a.isRead  // Unread articles first
            }
            return a.publishedDate > b.publishedDate  // Then newest first
        }

        // Limit to most recent 15 articles to avoid context window issues
        return Array(sortedArticles.prefix(15))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if let message = newsletterMessage {
                    // Show newsletter
                    VStack(alignment: .leading, spacing: 16) {
                        // Header
                        if message.isTyping {
                            TypingIndicator()
                                .padding(12)
                                .background(Color.gray.opacity(0.2))
                                .cornerRadius(16)
                        } else {
                            VStack(alignment: .leading, spacing: 0) {
                                Text(parseMarkdown(message.content))
                                    .padding(16)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .textSelection(.enabled)

                                Divider()
                                    .background(Color.accentColor)
                                    .frame(height: 2)
                            }
                            .background(Color.accentColor.opacity(0.1))
                            .cornerRadius(16)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(Color.accentColor.opacity(0.3), lineWidth: 1)
                            )
                        }

                        // Newsletter items
                        if let items = message.newsletterItems, !items.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                ForEach(items) { item in
                                    if let article = item.article {
                                        // Regular newsletter item with article link
                                        NavigationLink {
                                            // Show RedditPostView for Reddit posts, ArticleDetailSimple for regular articles
                                            if article.isRedditPost {
                                                RedditPostView(
                                                    article: article,
                                                    previousArticleID: nil,
                                                    nextArticleID: nil,
                                                    onNavigateToPrevious: { _ in },
                                                    onNavigateToNext: { _ in }
                                                )
                                            } else {
                                                ArticleDetailSimple(
                                                    article: article,
                                                    previousArticleID: nil,
                                                    nextArticleID: nil,
                                                    onNavigateToPrevious: { _ in },
                                                    onNavigateToNext: { _ in }
                                                )
                                            }
                                        } label: {
                                            VStack(alignment: .leading, spacing: 8) {
                                                // Summary text
                                                Text(parseMarkdown(item.summary))
                                                    .frame(maxWidth: .infinity, alignment: .leading)
                                                    .textSelection(.enabled)
                                                    .foregroundStyle(.primary)

                                                Divider()

                                                // Article link
                                                HStack(spacing: 8) {
                                                    Image(systemName: "arrow.right.circle.fill")
                                                        .font(.subheadline)
                                                        .foregroundStyle(Color.accentColor)

                                                    VStack(alignment: .leading, spacing: 2) {
                                                        Text("Read full article")
                                                            .font(.subheadline)
                                                            .fontWeight(.medium)

                                                        if let feedTitle = article.feed?.title {
                                                            Text(feedTitle)
                                                                .font(.caption2)
                                                                .foregroundStyle(.secondary)
                                                        }
                                                    }

                                                    Spacer()

                                                    Image(systemName: "chevron.right")
                                                        .font(.caption)
                                                        .foregroundStyle(.secondary)
                                                }
                                                .foregroundStyle(Color.accentColor)
                                            }
                                            .padding(12)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .background(Color.gray.opacity(0.1))
                                            .cornerRadius(12)
                                        }
                                        .buttonStyle(.plain)
                                    } else {
                                        // Closing message
                                        VStack(alignment: .leading, spacing: 8) {
                                            Text(parseMarkdown(item.summary))
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                                .textSelection(.enabled)
                                                .foregroundStyle(.primary)
                                        }
                                        .padding(12)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(Color.gray.opacity(0.1))
                                        .cornerRadius(12)
                                    }
                                }
                            }
                        }
                    }
                    .padding()
                } else {
                    // Welcome screen
                    VStack(spacing: 20) {
                        Image(systemName: "newspaper")
                            .font(.system(size: 60))
                            .foregroundStyle(Color.accentColor)

                        Text("Feed Newsletter")
                            .font(.title2)
                            .fontWeight(.bold)

                        Text("Generate a curated newsletter from \(feed.title)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)

                        if feedArticles.isEmpty {
                            Text("No recent articles from this feed")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding()
                        } else {
                            Button {
                                generateNewsletter()
                            } label: {
                                VStack(spacing: 8) {
                                    Image(systemName: "newspaper.fill")
                                        .font(.title2)
                                    Text("Generate Newsletter")
                                        .font(.headline)
                                    Text("\(feedArticles.count) recent articles")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.accentColor)
                                .foregroundStyle(.white)
                                .cornerRadius(12)
                            }
                            .disabled(isGenerating)
                            .padding(.horizontal)
                        }
                    }
                    .padding()
                    .frame(maxHeight: .infinity)
                }
            }
        }
        .navigationTitle(feed.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") {
                    dismiss()
                }
            }
        }
        .overlay {
            if isGenerating && newsletterMessage == nil {
                ProgressView("Generating newsletter...")
                    .padding()
                    .background(.regularMaterial)
                    .cornerRadius(10)
            }
        }
    }

    private func generateNewsletter() {
        isGenerating = true

        // Create message immediately with typing indicator
        let message = ChatMessage(content: "", isUser: false, isTyping: true, isNewsletter: true)
        newsletterMessage = message

        Task {
            // Use streaming on-device AI if available (iOS 18+)
            if #available(iOS 18.0, *), OnDeviceAIService.shared.isAvailable {
                do {
                    var items: [NewsletterItem] = []

                    for try await event in OnDeviceAIService.shared.generateNewsletterSummaryStream(articles: feedArticles) {
                        await MainActor.run {
                            switch event {
                            case .header(let header):
                                // Show header and stop typing indicator
                                message.isTyping = false
                                message.content = header

                            case .item(let itemData):
                                // Add item as it's generated
                                items.append(NewsletterItem(summary: itemData.summary, article: itemData.article))
                                message.newsletterItems = items

                            case .completed:
                                // All done
                                break
                            }
                        }
                    }
                } catch {
                    // Fallback to basic service if on-device AI fails
                    await MainActor.run {
                        message.isTyping = false
                    }
                    let (text, _) = await AIService.shared.generateNewsletterSummary(articles: feedArticles)
                    await MainActor.run {
                        message.content = text
                        message.newsletterItems = nil
                    }
                }
            } else {
                // Use basic service for older iOS versions
                let (text, _) = await AIService.shared.generateNewsletterSummary(articles: feedArticles)
                await MainActor.run {
                    message.isTyping = false
                    message.content = text
                    message.newsletterItems = nil
                }
            }

            await MainActor.run {
                isGenerating = false
            }
        }
    }

    private func parseMarkdown(_ text: String) -> AttributedString {
        do {
            return try AttributedString(markdown: text, options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace))
        } catch {
            return AttributedString(text)
        }
    }
}


