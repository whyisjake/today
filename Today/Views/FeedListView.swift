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

    @State private var editingFeedID: PersistentIdentifier?

    @State private var showingImportOPML = false
    @State private var opmlText = ""
    @State private var isImporting = false
    @State private var importError: String?

    init(modelContext: ModelContext) {
        _feedManager = StateObject(wrappedValue: FeedManager(modelContext: modelContext))
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(feeds) { feed in
                    NavigationLink {
                        EditFeedView(feed: feed, modelContext: modelContext)
                    } label: {
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
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .swipeActions(edge: .trailing) {
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

    private func exportOPML() {
        let opml = generateOPML(from: feeds)
        UIPasteboard.general.string = opml

        // Show a toast or alert (simplified version - just print for now)
        print("OPML exported to clipboard!")
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

    init(feed: Feed, modelContext: ModelContext) {
        self.feed = feed
        self.modelContext = modelContext
        _title = State(initialValue: feed.title)
        _url = State(initialValue: feed.url)
        _category = State(initialValue: feed.category)
    }

    var body: some View {
        Form {
            Section("Feed Details") {
                TextField("Feed Title", text: $title)

                TextField("RSS Feed URL", text: $url)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                Picker("Category", selection: $category) {
                    Text("General").tag("general")
                    Text("Work").tag("work")
                    Text("Social").tag("social")
                    Text("Tech").tag("tech")
                    Text("News").tag("news")
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
                .disabled(title.isEmpty || url.isEmpty)
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
