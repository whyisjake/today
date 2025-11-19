//
//  FeedListView.swift
//  Today
//
//  View for managing RSS feed subscriptions
//

import SwiftUI
import SwiftData

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
    static var pickerCategories: [FeedCategory] {
        [.general, .work, .social, .tech, .news, .politics]
    }
}

struct FeedListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Feed.title) private var feeds: [Feed]
    @StateObject private var feedManager: FeedManager

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
    @State private var showingExportConfirmation = false

    init(modelContext: ModelContext) {
        _feedManager = StateObject(wrappedValue: FeedManager(modelContext: modelContext))
    }

    var body: some View {
        NavigationStack {
            feedListContent
                .navigationTitle("RSS Feeds")
                .toolbar {
                    toolbarContent
                }
                .overlay {
                    syncingOverlay
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
                .alert("OPML Exported", isPresented: $showingExportConfirmation) {
                    Button("OK", role: .cancel) { }
                } message: {
                    Text("Your OPML feed list has been copied to the clipboard.")
                }
        }
    }

    @ViewBuilder
    private var feedListContent: some View {
        List {
            ForEach(feeds) { feed in
                feedRow(for: feed)
            }
        }
    }

    @ViewBuilder
    private func feedRow(for feed: Feed) -> some View {
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
            .tint(.orange)
        }
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

    @ViewBuilder
    private var syncingOverlay: some View {
        if feedManager.isSyncing {
            VStack {
                ProgressView("Syncing feeds...")
                    .padding()
                    .background(.regularMaterial)
                    .cornerRadius(10)
            }
        }
    }

    @ViewBuilder
    private var addFeedSheet: some View {
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
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
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
                            ForEach(FeedCategory.pickerCategories, id: \.self) { category in
                                Text(category.localizedName).tag(category.rawValue)
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

    @ViewBuilder
    private var importOPMLSheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $opmlText)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 200)
                } header: {
                    Text("Paste OPML Content")
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
                    .background(Color.accentColor)
                    .cornerRadius(10)
            }
        }
    }

    private func addFeed() {
        isAddingFeed = true
        addFeedError = nil

        Task {
            do {
                let category = useCustomCategory ? customCategory : newFeedCategory

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
                        ForEach(FeedCategory.pickerCategories, id: \.self) { category in
                            Text(category.localizedName).tag(category.rawValue)
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
    @State private var navigationState: NavigationState?
    @AppStorage("fontOption") private var fontOption: FontOption = .serif

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
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
                    .background(Color(.systemGroupedBackground))
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
                            // Capture navigation context when article is selected
                            let context = filteredArticles.map { $0.persistentModelID }
                            navigationState = NavigationState(
                                articleID: article.persistentModelID,
                                context: context
                            )
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
        .navigationBarTitleDisplayMode(.inline)
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
