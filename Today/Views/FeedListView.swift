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
    @State private var customCategory = ""
    @State private var useCustomCategory = false
    @State private var isAddingFeed = false
    @State private var addFeedError: String?

    @State private var editingFeedID: PersistentIdentifier?

    private var showingEditFeed: Binding<Bool> {
        Binding(
            get: { editingFeedID != nil },
            set: { if !$0 { editingFeedID = nil } }
        )
    }

    @State private var showingImportOPML = false
    @State private var opmlText = ""
    @State private var isImporting = false
    @State private var importError: String?
    @State private var showingExportConfirmation = false

    init(modelContext: ModelContext) {
        _feedManager = StateObject(wrappedValue: FeedManager(modelContext: modelContext))
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(feeds) { feed in
                    NavigationLink {
                        FeedArticlesView(feed: feed)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(feed.title)
                                    .font(.headline)
                                Spacer()
                                if let unreadCount = feed.articles?.filter({ !$0.isRead }).count, unreadCount > 0 {
                                    Text("\(unreadCount)")
                                        .font(.caption)
                                        .fontWeight(.bold)
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 2)
                                        .background(Color.accentColor)
                                        .cornerRadius(10)
                                }
                            }
                            Text(feed.url)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            HStack {
                                Text(feed.category)
                                    .font(.caption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(Color.accentColor.opacity(0.2))
                                    .cornerRadius(4)

                                if let lastFetched = feed.lastFetched {
                                    Text("Last synced: \(lastFetched, style: .relative) ago")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .contextMenu {
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
                    .swipeActions(edge: .trailing) {
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

                        Button {
                            showingImportOPML = true
                        } label: {
                            Label("Import OPML", systemImage: "square.and.arrow.down")
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
                        }

                        Section {
                            Toggle("Use Custom Category", isOn: $useCustomCategory)

                            if useCustomCategory {
                                TextField("Custom Category Name", text: $customCategory)
                                    .textInputAutocapitalization(.never)
                            } else {
                                Picker("Category", selection: $newFeedCategory) {
                                    Text("General").tag("general")
                                    Text("Work").tag("work")
                                    Text("Social").tag("social")
                                    Text("Tech").tag("tech")
                                    Text("News").tag("news")
                                    Text("Politics").tag("politics")
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
                            .disabled(newFeedURL.isEmpty || isAddingFeed || (useCustomCategory && customCategory.isEmpty))
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
            .sheet(isPresented: $showingImportOPML) {
                NavigationStack {
                    Form {
                        Section("Paste OPML Content") {
                            TextEditor(text: $opmlText)
                                .font(.system(.body, design: .monospaced))
                                .frame(minHeight: 200)
                        }

                        if let error = importError {
                            Section {
                                Text(error)
                                    .foregroundStyle(.red)
                                    .font(.caption)
                            }
                        }

                        Section {
                            Text("Paste your OPML file content above to import feeds.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
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
                            ProgressView("Importing feeds...")
                                .padding()
                                .background(.regularMaterial)
                                .cornerRadius(10)
                        }
                    }
                }
            }
            .sheet(isPresented: showingEditFeed) {
                if let feedID = editingFeedID,
                   let feed = feeds.first(where: { $0.id == feedID }) {
                    NavigationStack {
                        EditFeedView(feed: feed, modelContext: modelContext)
                    }
                }
            }
            .alert("OPML Exported", isPresented: $showingExportConfirmation) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Your OPML feed list has been copied to the clipboard.")
            }
        }
    }

    private func addFeed() {
        isAddingFeed = true
        addFeedError = nil

        Task {
            do {
                let category = useCustomCategory ? customCategory : newFeedCategory
                _ = try await feedManager.addFeed(url: newFeedURL, category: category)
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
        UIPasteboard.general.string = opml
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

        Task {
            do {
                let feedsToImport = try parseOPML(opmlText)

                // Import each feed
                for (url, title, category) in feedsToImport {
                    // Check if feed already exists
                    if !feeds.contains(where: { $0.url == url }) {
                        do {
                            _ = try await feedManager.addFeed(url: url, category: category)
                        } catch {
                            // Continue even if one feed fails
                            print("Failed to import \(title): \(error.localizedDescription)")
                        }
                    }
                }

                await MainActor.run {
                    showingImportOPML = false
                    opmlText = ""
                    isImporting = false
                }
            } catch {
                await MainActor.run {
                    importError = error.localizedDescription
                    isImporting = false
                }
            }
        }
    }

    private func parseOPML(_ opmlContent: String) throws -> [(url: String, title: String, category: String)] {
        guard let data = opmlContent.data(using: .utf8) else {
            throw NSError(domain: "OPML", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid OPML text"])
        }

        let parser = XMLParser(data: data)
        let delegate = OPMLParserDelegate()
        parser.delegate = delegate

        if parser.parse() {
            return delegate.feeds
        } else {
            throw NSError(domain: "OPML", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to parse OPML"])
        }
    }
}

// MARK: - OPML Parser Delegate
class OPMLParserDelegate: NSObject, XMLParserDelegate {
    var feeds: [(url: String, title: String, category: String)] = []
    private var currentCategory = "general"
    private var categoryStack: [String] = []

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        if elementName == "outline" {
            if let type = attributeDict["type"], type == "rss" {
                // This is a feed entry
                if let xmlUrl = attributeDict["xmlUrl"],
                   let title = attributeDict["title"] ?? attributeDict["text"] {
                    feeds.append((url: xmlUrl, title: title, category: currentCategory))
                }
            } else if let text = attributeDict["text"] {
                // This is a category
                categoryStack.append(currentCategory)
                currentCategory = text.lowercased()
            }
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "outline" && !categoryStack.isEmpty {
            currentCategory = categoryStack.removeLast()
        }
    }
}

// MARK: - Edit Feed View
struct EditFeedView: View {
    @Environment(\.dismiss) private var dismiss
    let feed: Feed
    let modelContext: ModelContext

    @State private var title: String
    @State private var url: String
    @State private var category: String
    @State private var useCustomCategory: Bool
    @State private var predefinedCategories = ["general", "work", "social", "tech", "news", "politics"]

    init(feed: Feed, modelContext: ModelContext) {
        self.feed = feed
        self.modelContext = modelContext
        _title = State(initialValue: feed.title)
        _url = State(initialValue: feed.url)
        _category = State(initialValue: feed.category)
        // Check if current category is a predefined one
        let isPredefined = ["general", "work", "social", "tech", "news", "politics"].contains(feed.category)
        _useCustomCategory = State(initialValue: !isPredefined)
    }

    var body: some View {
        Form {
            Section("Feed Details") {
                TextField("Feed Title", text: $title)

                TextField("RSS Feed URL", text: $url)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }

            Section {
                Toggle("Use Custom Category", isOn: $useCustomCategory)

                if useCustomCategory {
                    TextField("Custom Category Name", text: $category)
                        .textInputAutocapitalization(.never)
                } else {
                    Picker("Category", selection: $category) {
                        Text("General").tag("general")
                        Text("Work").tag("work")
                        Text("Social").tag("social")
                        Text("Tech").tag("tech")
                        Text("News").tag("news")
                        Text("Politics").tag("politics")
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
                Button("Save") {
                    saveFeed()
                }
                .disabled(title.isEmpty || url.isEmpty || category.isEmpty)
            }
        }
    }

    private func saveFeed() {
        feed.title = title
        feed.url = url
        feed.category = category

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

    @State private var showReadArticles = false
    @State private var selectedArticleID: PersistentIdentifier?
    @State private var navigationContext: [PersistentIdentifier] = []
    @AppStorage("fontOption") private var fontOption: FontOption = .serif

    private var filteredArticles: [Article] {
        var articles = allArticles.filter { $0.feed?.id == feed.id }

        if !showReadArticles {
            articles = articles.filter { !$0.isRead }
        }

        return articles
    }

    private var unreadCount: Int {
        allArticles.filter { $0.feed?.id == feed.id && !$0.isRead }.count
    }

    var body: some View {
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
                            // Capture navigation context when article is selected
                            navigationContext = filteredArticles.map { $0.persistentModelID }
                            selectedArticleID = article.persistentModelID
                        } label: {
                            HStack {
                                ArticleRowView(article: article, fontOption: fontOption)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
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
        .navigationTitle(feed.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
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
        }
        .navigationDestination(item: $selectedArticleID) { articleID in
            if let article = modelContext.model(for: articleID) as? Article {
                // Use the captured navigation context
                if !navigationContext.isEmpty,
                   let currentIndex = navigationContext.firstIndex(of: articleID) {
                    let previousIndex = currentIndex - 1
                    let nextIndex = currentIndex + 1
                    let previousArticleID = previousIndex >= 0 ? navigationContext[previousIndex] : nil
                    let nextArticleID = nextIndex < navigationContext.count ? navigationContext[nextIndex] : nil

                    ArticleDetailSimple(
                        article: article,
                        previousArticleID: previousArticleID,
                        nextArticleID: nextArticleID,
                        onNavigateToPrevious: { prevID in
                            Task { @MainActor in
                                try? await Task.sleep(nanoseconds: 50_000_000)
                                selectedArticleID = prevID
                            }
                        },
                        onNavigateToNext: { nextID in
                            Task { @MainActor in
                                try? await Task.sleep(nanoseconds: 50_000_000)
                                selectedArticleID = nextID
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
        .onAppear {
            navigationContext = filteredArticles.map { $0.persistentModelID }
        }
        .onChange(of: filteredArticles) { _, newArticles in
            navigationContext = newArticles.map { $0.persistentModelID }
        }
    }

    private func markAllAsRead() {
        for article in filteredArticles where !article.isRead {
            article.isRead = true
        }
        try? modelContext.save()
    }
}
