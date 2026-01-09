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
    @StateObject private var categoryManager = CategoryManager.shared

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

    init(modelContext: ModelContext) {
        _feedManager = StateObject(wrappedValue: FeedManager(modelContext: modelContext))
    }

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
                .onAppear {
                    // Sync custom categories from existing feeds
                    categoryManager.syncCategories(from: feeds.map { $0.category })
                }
        }
    }

    @ViewBuilder
    private var feedListContent: some View {
        List {
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
        importProgress = nil

        print("📥 OPML Import: Starting import process...")
        print("📥 OPML Import: Input length: \(opmlText.count) characters")

        Task {
            do {
                print("📥 OPML Import: Parsing OPML...")
                let feedsToImport = try parseOPML(opmlText)
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

    private func fixUnescapedAttributeValues(_ content: String) -> String {
        // Fix unescaped quotes and ampersands inside attribute values
        // This handles Stream's broken OPML export which doesn't escape special chars

        var fixed = ""
        var inAttributeValue = false
        var inXMLDeclaration = false
        var inComment = false
        var i = content.startIndex

        while i < content.endIndex {
            let char = content[i]

            // Check if we're entering an XML comment <!--
            if !inComment && !inXMLDeclaration && char == "<" {
                let remaining = String(content[i...])
                if remaining.hasPrefix("<!--") {
                    inComment = true
                }
            }

            // Check if we're exiting an XML comment -->
            if inComment && char == "-" {
                let remaining = String(content[i...])
                if remaining.hasPrefix("-->") {
                    fixed.append("-->")
                    i = content.index(i, offsetBy: 3)
                    inComment = false
                    continue
                }
            }

            // Skip processing inside comments
            if inComment {
                fixed.append(char)
                i = content.index(after: i)
                continue
            }

            // Check if we're entering an XML declaration
            if char == "<" && content.index(after: i) < content.endIndex &&
               content[content.index(after: i)] == "?" {
                inXMLDeclaration = true
                fixed.append(char)
                i = content.index(after: i)
                continue
            }

            // Check if we're exiting an XML declaration
            if inXMLDeclaration && char == "?" && content.index(after: i) < content.endIndex &&
               content[content.index(after: i)] == ">" {
                fixed.append(char) // append ?
                i = content.index(after: i)
                fixed.append(content[i]) // append >
                inXMLDeclaration = false
                i = content.index(after: i)
                continue
            }

            // Skip processing inside XML declarations
            if inXMLDeclaration {
                fixed.append(char)
                i = content.index(after: i)
                continue
            }

            // Detect start of attribute value: ="
            if char == "=" && content.index(after: i) < content.endIndex &&
               content[content.index(after: i)] == "\"" {
                fixed.append(char) // append =
                i = content.index(after: i)
                fixed.append(content[i]) // append opening "
                i = content.index(after: i)
                inAttributeValue = true
                continue
            }

            // Inside attribute value
            if inAttributeValue {
                if char == "\"" {
                    // Check if this is the closing quote by looking ahead for the next attribute or tag end
                    // A closing quote is followed by: space + attribute name + = OR / OR >
                    var j = content.index(after: i)
                    var isClosingQuote = false

                    // Skip whitespace after the quote
                    while j < content.endIndex && (content[j] == " " || content[j] == "\t") {
                        j = content.index(after: j)
                    }

                    if j < content.endIndex {
                        let nextChar = content[j]
                        // If followed by / or >, it's definitely a closing quote
                        if nextChar == "/" || nextChar == ">" {
                            isClosingQuote = true
                        } else if nextChar.isLetter {
                            // If followed by letters, check if it's an attribute name (letter+ followed by =)
                            var k = j
                            while k < content.endIndex && (content[k].isLetter || content[k].isNumber || content[k] == "_" || content[k] == "-") {
                                k = content.index(after: k)
                            }
                            if k < content.endIndex && content[k] == "=" {
                                isClosingQuote = true
                            }
                        }
                    } else {
                        // End of content
                        isClosingQuote = true
                    }

                    if isClosingQuote {
                        fixed.append(char) // Keep closing quote
                        inAttributeValue = false
                    } else {
                        // Escape embedded quote
                        fixed.append("&quot;")
                    }
                } else if char == "&" {
                    // Check if this is already part of an entity
                    let remainingContent = String(content[i...])
                    let isEntity = remainingContent.hasPrefix("&quot;") ||
                        remainingContent.hasPrefix("&amp;") ||
                        remainingContent.hasPrefix("&lt;") ||
                        remainingContent.hasPrefix("&gt;") ||
                        remainingContent.hasPrefix("&apos;") ||
                        remainingContent.hasPrefix("&#")

                    if isEntity {
                        fixed.append(char) // Keep as-is
                    } else {
                        // Escape unescaped ampersand
                        fixed.append("&amp;")
                    }
                } else {
                    fixed.append(char)
                }
            } else {
                fixed.append(char)
            }

            i = content.index(after: i)
        }

        return fixed
    }

    private func parseOPML(_ opmlContent: String) throws -> [(url: String, title: String, category: String)] {
        print("🔍 OPML Parser: Starting XML parsing...")
        print("🔍 OPML Parser: Input length: \(opmlContent.count) characters")

        // Clean up OPML content
        var cleanedContent = opmlContent.trimmingCharacters(in: .whitespacesAndNewlines)

        // Remove BOM if present
        if cleanedContent.hasPrefix("\u{FEFF}") {
            cleanedContent = String(cleanedContent.dropFirst())
            print("🔍 OPML Parser: Removed BOM")
        }

        // Detect if OPML was pasted twice (duplicate content)
        // Check for multiple <?xml declarations or multiple </opml> tags
        let xmlDeclarationCount = cleanedContent.components(separatedBy: "<?xml").count - 1
        let closingOpmlCount = cleanedContent.components(separatedBy: "</opml>").count - 1

        if xmlDeclarationCount > 1 || closingOpmlCount > 1 {
            print("⚠️ OPML Parser: Detected duplicate content (multiple XML declarations or closing tags)")
            print("⚠️ OPML Parser: Attempting to extract first valid OPML section...")

            // Extract just the first OPML document
            if let firstOpmlEnd = cleanedContent.range(of: "</opml>") {
                let endIndex = cleanedContent.index(firstOpmlEnd.upperBound, offsetBy: 0)
                cleanedContent = String(cleanedContent[..<endIndex])
                print("✅ OPML Parser: Extracted first OPML section (\(cleanedContent.count) characters)")
            }
        }

        // Fix attribute spacing: text= "value" -> text="value"
        // This is a common issue in Stream and other OPML exporters
        // Use a more comprehensive regex to catch all variations
        do {
            let regex = try NSRegularExpression(pattern: "=\\s+\"", options: [])
            let range = NSRange(cleanedContent.startIndex..., in: cleanedContent)
            let fixed = regex.stringByReplacingMatches(
                in: cleanedContent,
                options: [],
                range: range,
                withTemplate: "=\""
            )
            let fixCount = regex.numberOfMatches(in: cleanedContent, options: [], range: range)
            if fixCount > 0 {
                cleanedContent = fixed
                print("🔍 OPML Parser: Fixed \(fixCount) attribute spacing issues (= \" -> =\")")
            }
        } catch {
            print("⚠️ OPML Parser: Regex failed, using simple string replacement")
            cleanedContent = cleanedContent.replacingOccurrences(of: "= \"", with: "=\"")
        }

        // Fix unescaped special characters in attribute values
        // Stream exporter doesn't escape quotes or ampersands in attribute values
        // We need to escape:
        // - Unescaped quotes: " -> &quot; (but only inside attribute values)
        // - Unescaped ampersands: & -> &amp; (but not if already part of an entity like &quot; or &amp;)
        cleanedContent = fixUnescapedAttributeValues(cleanedContent)
        print("🔍 OPML Parser: Fixed unescaped special characters in attributes")

        // Remove any invalid control characters (except tab, newline, carriage return)
        cleanedContent = cleanedContent.filter { char in
            let scalar = char.unicodeScalars.first!
            let value = scalar.value
            // Allow tab (0x09), newline (0x0A), carriage return (0x0D)
            // Allow normal printable characters (0x20 and above)
            // Disallow other control characters (0x00-0x1F except the above)
            return value == 0x09 || value == 0x0A || value == 0x0D || value >= 0x20
        }

        guard let data = cleanedContent.data(using: .utf8) else {
            print("❌ OPML Parser: Failed to convert to UTF-8 data")
            throw NSError(domain: "OPML", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid OPML text encoding"])
        }

        print("🔍 OPML Parser: UTF-8 conversion successful, data size: \(data.count) bytes")

        let parser = XMLParser(data: data)
        let delegate = OPMLParserDelegate()
        parser.delegate = delegate

        print("🔍 OPML Parser: Starting XMLParser.parse()...")
        let parseResult = parser.parse()
        print("🔍 OPML Parser: XMLParser.parse() completed with result: \(parseResult)")

        if parseResult {
            // Check if any parsing error occurred
            if let error = delegate.parseError {
                print("❌ OPML Parser: Parse error occurred: \(error.localizedDescription)")
                throw NSError(domain: "OPML", code: -1, userInfo: [
                    NSLocalizedDescriptionKey: "XML parsing error: \(error.localizedDescription)"
                ])
            }

            print("🔍 OPML Parser: Found \(delegate.feeds.count) feeds")

            // Check if we found any feeds
            if delegate.feeds.isEmpty {
                print("❌ OPML Parser: No feeds found in OPML")
                throw NSError(domain: "OPML", code: -1, userInfo: [
                    NSLocalizedDescriptionKey: "No valid feeds found in OPML file. Make sure feeds have both a URL and title."
                ])
            }

            print("✅ OPML Parser: Successfully parsed \(delegate.feeds.count) feeds")
            return delegate.feeds
        } else {
            // Parser failed - check for specific error
            let line = parser.lineNumber
            let column = parser.columnNumber

            if let error = delegate.parseError {
                print("❌ OPML Parser: Parse failed at line \(line), column \(column)")
                print("❌ OPML Parser: Error: \(error.localizedDescription)")
                print("❌ OPML Parser: Error code: \((error as NSError).code)")

                // Try to show the problematic line
                let lines = cleanedContent.components(separatedBy: .newlines)
                if line > 0 && line <= lines.count {
                    let problemLine = lines[line - 1]
                    print("❌ OPML Parser: Problematic line: \(problemLine)")
                    if column > 0 && column <= problemLine.count {
                        let index = problemLine.index(problemLine.startIndex, offsetBy: column - 1, limitedBy: problemLine.endIndex)
                        if let index = index {
                            let char = problemLine[index]
                            print("❌ OPML Parser: Character at error: '\(char)' (Unicode: \\u{\(String(char.unicodeScalars.first!.value, radix: 16))})")
                        }
                    }
                }

                // Provide helpful error message based on error code
                let errorCode = (error as NSError).code
                var errorMessage = "Failed to parse OPML at line \(line), column \(column)"

                if errorCode == 23 { // NSXMLParserInvalidCharacterError
                    errorMessage += "\n\nThis OPML file contains invalid XML characters. This is a known issue with some RSS readers' OPML export.\n\nTry:\n1. Re-export the OPML from your RSS reader\n2. Open the OPML file in a text editor and check for unusual characters\n3. Make sure you didn't accidentally paste the content twice"
                } else if errorCode == 4 { // NSXMLParserEmptyDocumentError
                    errorMessage += "\n\nThe OPML content appears to be empty or invalid."
                } else {
                    errorMessage += ": \(error.localizedDescription)"
                }

                throw NSError(domain: "OPML", code: -1, userInfo: [
                    NSLocalizedDescriptionKey: errorMessage
                ])
            } else {
                print("❌ OPML Parser: Parse failed at line \(line), column \(column) with no specific error")

                var errorMessage = "Failed to parse OPML file at line \(line), column \(column)."
                errorMessage += "\n\nPlease check that:"
                errorMessage += "\n• The OPML file was exported correctly from your RSS reader"
                errorMessage += "\n• You copied the entire file content"
                errorMessage += "\n• You didn't paste the content multiple times"

                throw NSError(domain: "OPML", code: -1, userInfo: [
                    NSLocalizedDescriptionKey: errorMessage
                ])
            }
        }
    }

    private func toggleAltFeeds() {
        showAltFeeds.toggle()
    }
}

// MARK: - OPML Parser Delegate
class OPMLParserDelegate: NSObject, XMLParserDelegate {
    var feeds: [(url: String, title: String, category: String)] = []
    private var currentCategory = "General"
    private var categoryStack: [String] = []
    var parseError: Error?
    private var elementCount = 0
    private var feedCount = 0
    private var categoryCount = 0
    private var skippedCount = 0

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        if elementName == "outline" {
            elementCount += 1

            // Log first few elements for debugging
            if elementCount <= 3 {
                print("🔍 Delegate: Element \(elementCount) - attributes: \(attributeDict)")
            }

            // Case-insensitive attribute lookup helper
            func getAttribute(_ name: String) -> String? {
                // Try exact match first
                if let value = attributeDict[name] {
                    return value
                }
                // Try case-insensitive match
                for (key, value) in attributeDict {
                    if key.lowercased() == name.lowercased() {
                        return value
                    }
                }
                return nil
            }

            let type = getAttribute("type")
            let xmlUrl = getAttribute("xmlUrl")
            let title = getAttribute("title") ?? getAttribute("text")
            let text = getAttribute("text")

            // Check if this is a feed entry (has xmlUrl or type="rss")
            let isFeed = xmlUrl != nil || type?.lowercased() == "rss"

            if isFeed, let url = xmlUrl, let feedTitle = title, !feedTitle.trimmingCharacters(in: .whitespaces).isEmpty {
                // This is a valid feed entry with non-empty title
                feeds.append((url: url, title: feedTitle, category: currentCategory))
                feedCount += 1

                if feedCount <= 3 {
                    print("✅ Delegate: Added feed \(feedCount): \(feedTitle) | \(url)")
                }
            } else if !isFeed, let categoryName = text, !categoryName.trimmingCharacters(in: .whitespaces).isEmpty {
                // This is a category (outline without type="rss" or xmlUrl, with text)
                categoryStack.append(currentCategory)
                currentCategory = categoryName.lowercased()
                categoryCount += 1
                print("📁 Delegate: Found category: \(categoryName)")
            } else {
                // Skipped element - log why
                skippedCount += 1
                if skippedCount <= 3 {
                    var reason = "Unknown"
                    if !isFeed {
                        reason = "Not a feed (no xmlUrl or type=rss)"
                    } else if xmlUrl == nil {
                        reason = "Missing xmlUrl"
                    } else if title == nil || title!.trimmingCharacters(in: .whitespaces).isEmpty {
                        reason = "Missing or empty title"
                    }
                    print("⏭️  Delegate: Skipped element (reason: \(reason))")
                }
            }
        }
    }

    func parser(_ parser: XMLParser, didEndDocument: Void) {
        print("📊 Delegate: Parsing complete - Processed \(elementCount) outline elements")
        print("📊 Delegate: Found \(feedCount) feeds, \(categoryCount) categories, skipped \(skippedCount) elements")
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "outline" && !categoryStack.isEmpty {
            currentCategory = categoryStack.removeLast()
        }
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        self.parseError = parseError
    }

    func parser(_ parser: XMLParser, validationErrorOccurred validationError: Error) {
        self.parseError = validationError
    }
}

// MARK: - Edit Feed View
struct EditFeedView: View {
    @Environment(\.dismiss) private var dismiss
    let feed: Feed
    let modelContext: ModelContext
    @StateObject private var categoryManager = CategoryManager.shared

    @State private var title: String
    @State private var url: String
    @State private var category: String
    @State private var useCustomCategory: Bool
    @State private var episodeLimit: Int
    @AppStorage("defaultEpisodeLimit") private var defaultEpisodeLimit: Int = 5

    private let episodeLimitOptions = [0, 1, 2, 3, 5, 10, 20] // 0 = use default

    init(feed: Feed, modelContext: ModelContext) {
        self.feed = feed
        self.modelContext = modelContext
        _title = State(initialValue: feed.title)
        _url = State(initialValue: feed.url)
        _category = State(initialValue: feed.category)
        // Check if current category is a predefined one
        let isPredefined = FeedCategory(rawValue: feed.category) != nil
        _useCustomCategory = State(initialValue: !isPredefined)
        _episodeLimit = State(initialValue: feed.downloadEpisodeLimit ?? 0)
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

            // Podcast download settings (only show for feeds with audio content)
            if feed.isPodcastFeed {
                Section {
                    Picker("Keep downloaded episodes", selection: $episodeLimit) {
                        Text("Use Default (\(defaultEpisodeLimit == 0 ? "Unlimited" : "\(defaultEpisodeLimit)"))").tag(0)
                        ForEach(episodeLimitOptions.filter { $0 > 0 }, id: \.self) { limit in
                            Text("\(limit) episodes").tag(limit)
                        }
                        Text("Unlimited").tag(-1)
                    }
                } header: {
                    Text("Podcast Downloads")
                } footer: {
                    Text("Older downloaded episodes will be automatically removed when this limit is exceeded.")
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

        // Trim custom category to ensure consistency with CategoryManager
        let trimmedCategory = useCustomCategory
            ? category.trimmingCharacters(in: .whitespacesAndNewlines)
            : category
        feed.category = trimmedCategory

        // Save custom category to CategoryManager if it's a custom category
        if useCustomCategory {
            _ = categoryManager.addCustomCategory(trimmedCategory)
        }

        // Save episode limit (0 = use default, -1 = unlimited, >0 = specific limit)
        if episodeLimit == 0 {
            feed.downloadEpisodeLimit = nil // Use global default
        } else if episodeLimit == -1 {
            feed.downloadEpisodeLimit = 0 // 0 in model means unlimited
        } else {
            feed.downloadEpisodeLimit = episodeLimit
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
