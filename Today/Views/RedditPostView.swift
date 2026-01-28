//
//  RedditPostView.swift
//  Today
//
//  Combined view for Reddit posts with inline comments
//

import SwiftUI
import SwiftData
import AVKit
import AVFoundation
import WebKit
import OSLog

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

private let logger = Logger(subsystem: "com.today.app", category: "RedditPostView")

// Helper function to create Image from platform-specific image type
private func platformImage(_ image: PlatformImage) -> Image {
    #if os(iOS)
    return Image(uiImage: image)
    #elseif os(macOS)
    return Image(nsImage: image)
    #endif
}

// Platform-specific background colors
private var platformBackgroundColor: Color {
    #if os(iOS)
    return Color(.systemBackground)
    #else
    // Use clear on macOS so it inherits from the parent view
    return Color.clear
    #endif
}

private var platformGray6Color: Color {
    #if os(iOS)
    return Color(.systemGray6)
    #else
    return Color(NSColor.controlBackgroundColor)
    #endif
}

struct RedditPostView: View {
    let article: Article
    let previousArticleID: PersistentIdentifier?
    let nextArticleID: PersistentIdentifier?
    let onNavigateToPrevious: (PersistentIdentifier) -> Void
    let onNavigateToNext: (PersistentIdentifier) -> Void

    @State private var post: ParsedRedditPost?
    @State private var comments: [RedditComment] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var collapsedCommentIds: Set<String> = [] // Track collapsed comments for macOS flat view
    @State private var commentsWithChildren: Set<String> = [] // Pre-computed set of comment IDs that have children
    @AppStorage("fontOption") private var fontOption: FontOption = .serif
    @Environment(\.openURL) private var openURL
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            if isLoading {
                VStack {
                    ProgressView("Loading post...")
                        .padding()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = errorMessage {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("Failed to Load Post")
                        .font(.headline)
                    Text(error)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Try Again") {
                        Task {
                            await loadPost()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
            } else if let post = post {
                GeometryReader { geometry in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            // Post content section
                            PostContentView(post: post, fontOption: fontOption, openURL: openURL, availableWidth: geometry.size.width)

                        Divider()
                            .padding(.vertical, 16)

                        // Comments section
                        // On macOS, flatten the comment tree to avoid recursive view issues
                        #if os(macOS)
                        let displayComments = flattenComments(comments, maxDepth: 4, collapsedIds: collapsedCommentIds)
                        #else
                        let displayComments = comments
                        #endif

                        if displayComments.isEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: "bubble.left")
                                    .font(.system(size: 36))
                                    .foregroundStyle(.secondary)
                                Text("No comments yet")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 32)
                        } else {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("\(post.numComments) Comments")
                                        .font(.headline)
                                        .fontWeight(.semibold)
                                    Spacer()
                                }
                                .padding(.horizontal, 16)
                                .padding(.bottom, 8)

                                LazyVStack(alignment: .leading, spacing: 0) {
                                    ForEach(displayComments) { comment in
                                        #if os(macOS)
                                        CommentRowView(
                                            comment: comment,
                                            fontOption: fontOption,
                                            isCollapsed: collapsedCommentIds.contains(comment.id),
                                            hasChildren: commentsWithChildren.contains(comment.id),
                                            onToggleCollapse: {
                                                if collapsedCommentIds.contains(comment.id) {
                                                    collapsedCommentIds.remove(comment.id)
                                                } else {
                                                    collapsedCommentIds.insert(comment.id)
                                                }
                                            }
                                        )
                                        #else
                                        CommentRowView(comment: comment, fontOption: fontOption)
                                        #endif
                                    }
                                }
                            }
                        }
                        }
                        .padding(.bottom, 32)
                    }
                }
            }
        }
        .navigationTitle(article.feed?.title ?? "Reddit")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            #if os(iOS)
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    // Share functionality handled in context menu
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .contextMenu {
                    if let url = article.articleURL {
                        ShareLink(item: url, subject: Text(article.title)) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                    }
                }
            }

            ToolbarItem(placement: .bottomBar) {
                HStack(spacing: 20) {
                    // Previous article button
                    Button {
                        if let prevID = previousArticleID {
                            onNavigateToPrevious(prevID)
                        }
                    } label: {
                        Label("Previous", systemImage: "chevron.left")
                    }
                    .disabled(previousArticleID == nil)

                    // Open in Safari button
                    Button {
                        if let url = article.articleURL {
                            openURL(url)
                        }
                    } label: {
                        Label("Safari", systemImage: "safari")
                    }
                    .contextMenu {
                        if let url = article.articleURL {
                            Button {
                                openURL(url)
                            } label: {
                                Label("Open in Safari", systemImage: "safari")
                            }

                            ShareLink(item: url, subject: Text(article.title)) {
                                Label("Share", systemImage: "square.and.arrow.up")
                            }

                            Divider()
                        }

                        Button {
                            markAsUnreadAndGoBack()
                        } label: {
                            Label("Mark as Unread", systemImage: "envelope.badge")
                        }
                    }

                    // Next article button
                    Button {
                        if let nextID = nextArticleID {
                            onNavigateToNext(nextID)
                        }
                    } label: {
                        Label("Next", systemImage: "chevron.right")
                    }
                    .disabled(nextArticleID == nil)
                }
            }
            #else
            ToolbarItem(placement: .primaryAction) {
                if let url = article.articleURL {
                    ShareLink(item: url, subject: Text(article.title)) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                }
            }

            ToolbarItem(placement: .navigation) {
                HStack(spacing: 12) {
                    Button {
                        if let prevID = previousArticleID {
                            onNavigateToPrevious(prevID)
                        }
                    } label: {
                        Label("Previous", systemImage: "chevron.left")
                    }
                    .disabled(previousArticleID == nil)

                    Button {
                        if let nextID = nextArticleID {
                            onNavigateToNext(nextID)
                        }
                    } label: {
                        Label("Next", systemImage: "chevron.right")
                    }
                    .disabled(nextArticleID == nil)
                }
            }
            #endif
        }
        #if os(iOS)
        .toolbar(.hidden, for: .tabBar)
        #endif
        .onAppear {
            markAsRead()
        }
        .task {
            await loadPost()
        }
    }

    private func markAsRead() {
        if !article.isRead {
            article.isRead = true
            try? modelContext.save()

            // Track article read for review prompts
            ReviewRequestManager.shared.incrementArticleReadCount()
            ReviewRequestManager.shared.requestReviewIfAppropriate()
        }
    }

    private func markAsUnreadAndGoBack() {
        article.isRead = false
        try? modelContext.save()
        dismiss()
    }

    private func loadPost() async {
        isLoading = true
        errorMessage = nil

        guard let commentsUrl = article.redditCommentsUrl else {
            errorMessage = "Invalid Reddit post URL"
            isLoading = false
            return
        }

        do {
            let jsonURL = commentsUrl.hasSuffix("/") ? commentsUrl + ".json" : commentsUrl + ".json"
            guard let requestURL = URL(string: jsonURL) else {
                throw RedditError.invalidURL
            }

            var request = URLRequest(url: requestURL)
            request.setValue("ios:com.today.app:v1.0 (by /u/TodayApp)", forHTTPHeaderField: "User-Agent")

            let (data, _) = try await URLSession.shared.data(for: request)

            let parser = RedditJSONParser()
            let (parsedPost, parsedComments) = try parser.parsePostWithComments(data: data)

            self.post = parsedPost
            self.comments = parsedComments

            // Pre-compute which comments have children (for macOS collapse UI)
            #if os(macOS)
            self.commentsWithChildren = computeCommentsWithChildren(parsedComments)
            #endif

            isLoading = false
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }

    enum RedditError: LocalizedError {
        case invalidURL

        var errorDescription: String? {
            "Invalid Reddit URL"
        }
    }

    /// Flatten a nested comment tree into a single array for non-recursive rendering
    /// This avoids SwiftUI performance issues with deeply recursive views on macOS
    private func flattenComments(_ comments: [RedditComment], maxDepth: Int, collapsedIds: Set<String>) -> [RedditComment] {
        var result: [RedditComment] = []

        func flatten(_ comment: RedditComment, depth: Int, parentCollapsed: Bool) {
            // Skip this comment if parent is collapsed
            if parentCollapsed {
                return
            }

            // Create a copy with NO replies (flat structure for rendering)
            let flatComment = RedditComment(
                id: comment.id,
                author: comment.author,
                body: comment.body,
                decodedBody: comment.decodedBody,
                bodyHtml: comment.bodyHtml,
                score: comment.score,
                createdUtc: comment.createdUtc,
                depth: depth,
                replies: [] // No nested replies in flattened view
            )
            result.append(flatComment)

            // Check if this comment is collapsed
            let isCollapsed = collapsedIds.contains(comment.id)

            // Recursively add replies up to max depth (unless collapsed)
            if depth < maxDepth {
                for reply in comment.replies {
                    flatten(reply, depth: depth + 1, parentCollapsed: isCollapsed)
                }
            }
        }

        for comment in comments {
            flatten(comment, depth: 0, parentCollapsed: false)
        }

        return result
    }

    /// Pre-compute which comments have children (called once when comments load)
    private func computeCommentsWithChildren(_ comments: [RedditComment]) -> Set<String> {
        var result: Set<String> = []

        func traverse(_ comments: [RedditComment]) {
            for comment in comments {
                if !comment.replies.isEmpty {
                    result.insert(comment.id)
                    traverse(comment.replies)
                }
            }
        }

        traverse(comments)
        return result
    }
}

// MARK: - Post Content View

struct PostContentView: View {
    let post: ParsedRedditPost
    let fontOption: FontOption
    let openURL: OpenURLAction
    var availableWidth: CGFloat = ScreenUtilities.mainScreenWidth

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Title
            Text(post.title.decodeHTMLEntities())
                .font(fontOption == .serif ?
                    .system(.title2, design: .serif, weight: .bold) :
                    .system(.title2, design: .default, weight: .bold))

            // Meta info: author, score, time
            HStack(spacing: 8) {
                Text("u/\(post.author)")
                    .font(.subheadline)
                    .foregroundStyle(.orange)

                Text("•")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 4) {
                    Image(systemName: "arrow.up")
                        .font(.caption)
                    Text("\(post.score)")
                        .font(.subheadline)
                }
                .foregroundStyle(.secondary)

                Text("•")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(post.createdUtc, style: .relative)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            // Gallery images (if available)
            if !post.galleryImages.isEmpty {
                ImageGalleryView(images: post.galleryImages, availableWidth: availableWidth)
            }
            // Embedded media from external video services
            else if let mediaEmbedHtml = post.mediaEmbedHtml,
                    let width = post.mediaEmbedWidth,
                    let height = post.mediaEmbedHeight {
                EmbeddedMediaView(html: mediaEmbedHtml, width: width, height: height)
                    .frame(height: CGFloat(height) * (availableWidth / CGFloat(width)))
                    .cornerRadius(8)
            }
            // Single post image (if available and no gallery or embed)
            else if let imageUrl = post.imageUrl, let url = URL(string: imageUrl) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .cornerRadius(8)
                    case .failure:
                        EmptyView()
                    case .empty:
                        ProgressView()
                    @unknown default:
                        EmptyView()
                    }
                }
                .frame(maxWidth: .infinity)
            }

            // Post body (for text posts)
            #if os(iOS)
            if let selftextHtml = post.selftextHtml, !selftextHtml.isEmpty {
                PostHTMLView(html: selftextHtml, fontOption: fontOption)
            } else if let selftext = post.selftext, !selftext.isEmpty {
                Text(selftext)
                    .font(fontOption == .serif ?
                        .system(.body, design: .serif) :
                        .system(.body, design: .default))
                    .textSelection(.enabled)
            }
            #else
            // On macOS, use plain text to avoid WebView scroll capture issues
            if let selftext = post.selftext, !selftext.isEmpty {
                Text(selftext.decodeHTMLEntities())
                    .font(fontOption == .serif ?
                        .system(.body, design: .serif) :
                        .system(.body, design: .default))
                    .textSelection(.enabled)
            }
            #endif

        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
    }
}

// MARK: - Post HTML View

struct PostHTMLView: View {
    let html: String
    let fontOption: FontOption
    @State private var contentHeight: CGFloat = 0
    @Environment(\.colorScheme) var colorScheme
    @AppStorage("accentColor") private var accentColor: AccentColorOption = .orange

    var body: some View {
        PostWebView(html: html, height: $contentHeight, colorScheme: colorScheme, accentColor: accentColor.color, fontOption: fontOption)
            .frame(height: max(contentHeight, 20))
    }
}

#if os(iOS)
struct PostWebView: UIViewRepresentable {
    let html: String
    @Binding var height: CGFloat
    let colorScheme: ColorScheme
    let accentColor: Color
    let fontOption: FontOption

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.navigationDelegate = context.coordinator
        webView.underPageBackgroundColor = .clear
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // Decode HTML entities (Reddit double-encodes, so decode twice)
        let decodedHTML = html.decodeHTMLEntities().decodeHTMLEntities()

        let styledHTML = createStyledHTML(from: decodedHTML, colorScheme: colorScheme, accentColor: accentColor, fontOption: fontOption)
        context.coordinator.parent = self
        webView.loadHTMLString(styledHTML, baseURL: nil)
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: PostWebView

        init(_ parent: PostWebView) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.evaluateJavaScript("Math.max(document.body.scrollHeight, document.documentElement.scrollHeight)") { height, error in
                if let height = height as? CGFloat {
                    DispatchQueue.main.async {
                        self.parent.height = height
                    }
                }
            }
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if navigationAction.navigationType == .other {
                decisionHandler(.allow)
                return
            }

            // Handle link taps - open in Safari
            if navigationAction.navigationType == .linkActivated {
                if let url = navigationAction.request.url {
                    UIApplication.shared.open(url)
                }
                decisionHandler(.cancel)
                return
            }

            decisionHandler(.allow)
        }
    }

    func createStyledHTML(from html: String, colorScheme: ColorScheme, accentColor: Color, fontOption: FontOption) -> String {
        let textColor = colorScheme == .dark ? "#FFFFFF" : "#000000"
        let secondaryBg = colorScheme == .dark ? "#2C2C2E" : "#F2F2F7"
        let accentColorHex = accentColor.toHex()

        return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0">
            <style>
                body {
                    font-family: \(fontOption.fontFamily);
                    font-size: 16px;
                    line-height: 1.6;
                    color: \(textColor);
                    background-color: transparent;
                    margin: 0;
                    padding: 0;
                }
                p {
                    margin: 0 0 12px 0;
                    padding: 0;
                }
                a {
                    color: \(accentColorHex);
                    text-decoration: none;
                }
                img {
                    max-width: 100%;
                    height: auto;
                    margin: 12px 0;
                    border-radius: 8px;
                }
                code {
                    font-family: 'SF Mono', Menlo, Monaco, monospace;
                    font-size: 14px;
                    background-color: \(secondaryBg);
                    padding: 2px 6px;
                    border-radius: 3px;
                }
                pre {
                    background-color: \(secondaryBg);
                    padding: 12px;
                    border-radius: 6px;
                    overflow-x: auto;
                    margin: 12px 0;
                }
                blockquote {
                    margin: 12px 0;
                    padding: 12px 16px;
                    border-left: 4px solid \(accentColorHex);
                    background-color: \(secondaryBg);
                }
                strong, b {
                    font-weight: 600;
                }
                em, i {
                    font-style: italic;
                }
                ul, ol {
                    margin: 12px 0;
                    padding-left: 24px;
                }
                li {
                    margin: 4px 0;
                }
            </style>
        </head>
        <body>
            \(html)
        </body>
        </html>
        """
    }
}
#elseif os(macOS)
struct PostWebView: NSViewRepresentable {
    let html: String
    @Binding var height: CGFloat
    let colorScheme: ColorScheme
    let accentColor: Color
    let fontOption: FontOption

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        // macOS-specific: disable drawing background for dark mode transparency
        webView.setValue(false, forKey: "drawsBackground")
        webView.underPageBackgroundColor = .clear
        // Disable WebView scrolling so parent ScrollView handles it
        disableWebViewScrolling(webView)
        return webView
    }

    private func disableWebViewScrolling(_ webView: WKWebView) {
        disableScrollingRecursively(in: webView)
    }

    private func disableScrollingRecursively(in view: NSView) {
        for subview in view.subviews {
            if let scrollView = subview as? NSScrollView {
                scrollView.hasVerticalScroller = false
                scrollView.hasHorizontalScroller = false
                scrollView.verticalScrollElasticity = .none
                scrollView.horizontalScrollElasticity = .none
                scrollView.scrollerStyle = .overlay
            }
            disableScrollingRecursively(in: subview)
        }
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        // Decode HTML entities (Reddit double-encodes, so decode twice)
        let decodedHTML = html.decodeHTMLEntities().decodeHTMLEntities()

        let styledHTML = createStyledHTML(from: decodedHTML, colorScheme: colorScheme, accentColor: accentColor, fontOption: fontOption)
        context.coordinator.parent = self
        webView.loadHTMLString(styledHTML, baseURL: nil)
        disableWebViewScrolling(webView)
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: PostWebView

        init(_ parent: PostWebView) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // Disable scrolling after content loads
            parent.disableWebViewScrolling(webView)

            webView.evaluateJavaScript("Math.max(document.body.scrollHeight, document.documentElement.scrollHeight)") { height, error in
                if let height = height as? CGFloat {
                    DispatchQueue.main.async {
                        self.parent.height = height
                        // Re-disable after height adjustment
                        self.parent.disableWebViewScrolling(webView)
                    }
                }
            }
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if navigationAction.navigationType == .other {
                decisionHandler(.allow)
                return
            }

            // Handle link taps - open in browser
            if navigationAction.navigationType == .linkActivated {
                if let url = navigationAction.request.url {
                    NSWorkspace.shared.open(url)
                }
                decisionHandler(.cancel)
                return
            }

            decisionHandler(.allow)
        }
    }

    func createStyledHTML(from html: String, colorScheme: ColorScheme, accentColor: Color, fontOption: FontOption) -> String {
        let textColor = colorScheme == .dark ? "#FFFFFF" : "#000000"
        let secondaryBg = colorScheme == .dark ? "#2C2C2E" : "#F2F2F7"
        let accentColorHex = accentColor.toHex()

        return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0">
            <style>
                body {
                    font-family: \(fontOption.fontFamily);
                    font-size: 16px;
                    line-height: 1.6;
                    color: \(textColor);
                    background-color: transparent;
                    margin: 0;
                    padding: 0;
                }
                p {
                    margin: 0 0 12px 0;
                    padding: 0;
                }
                a {
                    color: \(accentColorHex);
                    text-decoration: none;
                }
                img {
                    max-width: 100%;
                    height: auto;
                    margin: 12px 0;
                    border-radius: 8px;
                }
                code {
                    font-family: 'SF Mono', Menlo, Monaco, monospace;
                    font-size: 14px;
                    background-color: \(secondaryBg);
                    padding: 2px 6px;
                    border-radius: 3px;
                }
                pre {
                    background-color: \(secondaryBg);
                    padding: 12px;
                    border-radius: 6px;
                    overflow-x: auto;
                    margin: 12px 0;
                }
                blockquote {
                    margin: 12px 0;
                    padding: 12px 16px;
                    border-left: 4px solid \(accentColorHex);
                    background-color: \(secondaryBg);
                }
                strong, b {
                    font-weight: 600;
                }
                em, i {
                    font-style: italic;
                }
                ul, ol {
                    margin: 12px 0;
                    padding-left: 24px;
                }
                li {
                    margin: 4px 0;
                }
            </style>
        </head>
        <body>
            \(html)
        </body>
        </html>
        """
    }
}
#endif


// MARK: - Image Size Tracking Helper
struct SizeTrackingAsyncImage: View {
    let imageUrl: String
    let onSizeCalculated: (CGFloat) -> Void
    var availableWidth: CGFloat = ScreenUtilities.mainScreenWidth

    @State private var image: PlatformImage?
    @State private var isLoading = true
    @State private var hasFailed = false

    var body: some View {
        Group {
            if let image = image {
                platformImage(image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .cornerRadius(8)
            } else if hasFailed {
                VStack {
                    Image(systemName: "photo")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("Failed to load")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 200)
                #if os(iOS)
                .background(platformGray6Color)
                #else
                .background(Color(NSColor.controlBackgroundColor))
                #endif
                .cornerRadius(8)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 200)
            }
        }
        .task {
            await loadImage()
        }
    }

    private func loadImage() async {
        guard let url = URL(string: imageUrl) else {
            hasFailed = true
            return
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let loadedImage = PlatformImage(data: data) {
                await MainActor.run {
                    self.image = loadedImage

                    // Calculate height based on aspect ratio
                    let aspectRatio = loadedImage.size.height / loadedImage.size.width
                    let contentWidth = availableWidth - 32 // Account for padding
                    let calculatedHeight = contentWidth * aspectRatio

                    // Cap maximum height to 100% of screen height
                    let maxHeight = ScreenUtilities.mainScreenHeight
                    let finalHeight = min(calculatedHeight, maxHeight)

                    print("📸 Image sizing - Original: \(loadedImage.size.width)x\(loadedImage.size.height), AspectRatio: \(aspectRatio), ContentWidth: \(contentWidth), CalculatedHeight: \(calculatedHeight), FinalHeight: \(finalHeight)")

                    onSizeCalculated(finalHeight)
                }
            } else {
                await MainActor.run {
                    hasFailed = true
                }
            }
        } catch {
            await MainActor.run {
                hasFailed = true
            }
        }
    }
}

// MARK: - Image Gallery View

struct ImageGalleryView: View {
    let images: [RedditGalleryImage]
    var availableWidth: CGFloat = ScreenUtilities.mainScreenWidth
    @State private var showFullScreen = false
    @State private var currentPage = 0
    @State private var galleryHeight: CGFloat = 300

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Image carousel
            TabView(selection: $currentPage) {
                ForEach(Array(images.enumerated()), id: \.element.id) { index, image in
                    if image.isAnimated, let videoUrl = image.videoUrl {
                        ZStack {
                            AnimatedMediaView(videoUrl: videoUrl, posterUrl: image.url, availableWidth: availableWidth)
                                .cornerRadius(8)

                            // Transparent overlay to capture taps (VideoPlayer intercepts gestures)
                            Color.clear
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    showFullScreen = true
                                }
                        }
                        .tag(index)
                    } else {
                        SizeTrackingAsyncImage(imageUrl: image.url, onSizeCalculated: { height in
                            // Update gallery height based on first loaded image
                            if galleryHeight == 300 {
                                print("📐 Gallery height updated from 300 to \(height)")
                                galleryHeight = height
                            }
                        }, availableWidth: availableWidth)
                        .onTapGesture {
                            showFullScreen = true
                        }
                        .tag(index)
                    }
                }
            }
            #if os(iOS)
            .tabViewStyle(.page(indexDisplayMode: images.count > 1 ? .always : .never))
            #endif
            .frame(height: galleryHeight)

            // Image counter
            if images.count > 1 {
                HStack {
                    Text("\(currentPage + 1) / \(images.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("Tap to view full size")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Tap to view full size")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        #if os(iOS)
        .fullScreenCover(isPresented: $showFullScreen) {
            FullScreenImageGallery(images: images, currentIndex: $currentPage)
        }
        #else
        .sheet(isPresented: $showFullScreen) {
            FullScreenImageGallery(images: images, currentIndex: $currentPage)
                .frame(minWidth: 800, minHeight: 600)
        }
        #endif
        .onChange(of: showFullScreen) { oldValue, newValue in
            print("🖼️ ImageGalleryView: showFullScreen changed \(oldValue) → \(newValue)")
        }
    }
}

// MARK: - Full Screen Image Gallery

struct FullScreenImageGallery: View {
    let images: [RedditGalleryImage]
    @Binding var currentIndex: Int
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            TabView(selection: $currentIndex) {
                ForEach(Array(images.enumerated()), id: \.element.id) { index, image in
                    if image.isAnimated, let videoUrl = image.videoUrl {
                        AnimatedMediaView(videoUrl: videoUrl, posterUrl: image.url)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(platformBackgroundColor)
                            .tag(index)
                    } else {
                        ZoomableImageView(imageUrl: image.url)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(platformBackgroundColor)
                            .tag(index)
                    }
                }
            }
            #if os(iOS)
            .tabViewStyle(.page(indexDisplayMode: .never))
            #endif
            .background(platformBackgroundColor)
            .ignoresSafeArea()
            .navigationTitle("\(currentIndex + 1) of \(images.count)")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            #endif
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") {
                        logger.info("🖼️ FullScreenImageGallery: Done button tapped")
                        dismiss()
                    }
                }
                #else
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        logger.info("🖼️ FullScreenImageGallery: Done button tapped")
                        dismiss()
                    }
                }
                #endif

                #if os(iOS)
                ToolbarItem(placement: .topBarTrailing) {
                    if let imageUrl = URL(string: images[currentIndex].url) {
                        ShareLink(item: imageUrl) {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                }
                #else
                ToolbarItem(placement: .primaryAction) {
                    if let imageUrl = URL(string: images[currentIndex].url) {
                        ShareLink(item: imageUrl) {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                }
                #endif
            }
            .onAppear {
                logger.info("🖼️ FullScreenImageGallery: appeared with \(self.images.count) images")
            }
            .onDisappear {
                logger.info("🖼️ FullScreenImageGallery: disappeared")
            }
            // Keyboard navigation for gallery
            .background {
                Group {
                    Button("") {
                        if currentIndex > 0 {
                            withAnimation { currentIndex -= 1 }
                        }
                    }
                    .keyboardShortcut(.leftArrow, modifiers: [])

                    Button("") {
                        if currentIndex < images.count - 1 {
                            withAnimation { currentIndex += 1 }
                        }
                    }
                    .keyboardShortcut(.rightArrow, modifiers: [])

                    Button("") { dismiss() }
                        .keyboardShortcut(.escape, modifiers: [])
                }
                .opacity(0)
            }
        }
    }
}

// MARK: - Zoomable Image View

struct ZoomableImageView: View {
    let imageUrl: String

    @State private var scale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var imageSize: CGSize = .zero
    @State private var lastZoomTime: Date = .distantPast

    @GestureState private var gestureScale: CGFloat = 1.0
    @GestureState private var gestureOffset: CGSize = .zero

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Blurred background image
                AsyncImage(url: URL(string: imageUrl)) { phase in
                    if case .success(let image) = phase {
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .blur(radius: 40)
                            .ignoresSafeArea()
                    }
                }

                // Sharp foreground image with zoom/pan
                AsyncImage(url: URL(string: imageUrl)) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .scaleEffect(scale * gestureScale)
                            .offset(x: offset.width + gestureOffset.width,
                                   y: offset.height + gestureOffset.height)
                            .highPriorityGesture(makeDoubleTapGesture(in: geometry.size))
                            .gesture(makeZoomGesture(in: geometry.size))
                            .simultaneousGesture(makeDragGesture(in: geometry.size))

                    case .failure:
                        VStack {
                            Image(systemName: "photo")
                                .font(.largeTitle)
                                .foregroundStyle(.secondary)
                            Text("Failed to load image")
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    case .empty:
                        ProgressView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)

                    @unknown default:
                        EmptyView()
                    }
                }
            }
        }
    }

    private func makeZoomGesture(in size: CGSize) -> some Gesture {
        MagnifyGesture()
            .updating($gestureScale) { value, state, _ in
                state = value.magnification
            }
            .onEnded { value in
                let newScale = scale * value.magnification

                // Clamp between 1.0 and 10.0
                let clampedScale: CGFloat
                if newScale < 1.0 {
                    clampedScale = 1.0
                } else if newScale > 10.0 {
                    clampedScale = 10.0
                } else {
                    clampedScale = newScale
                }

                // Calculate offset to keep the pinch center point stationary
                let anchorUnit = value.startAnchor
                // Convert UnitPoint (0-1) to actual pixel coordinates
                let anchor = CGPoint(x: anchorUnit.x * size.width, y: anchorUnit.y * size.height)
                let imageCenter = CGPoint(x: size.width / 2, y: size.height / 2)

                // Calculate how much to offset to keep the anchor point at the same position
                let anchorOffsetX = anchor.x - imageCenter.x
                let anchorOffsetY = anchor.y - imageCenter.y

                // Adjust offset based on scale change
                let scaleChange = clampedScale / scale
                let newOffsetX = offset.width * scaleChange - anchorOffsetX * (clampedScale - scale)
                let newOffsetY = offset.height * scaleChange - anchorOffsetY * (clampedScale - scale)

                // Add any pan offset that accumulated during the zoom gesture
                let finalOffsetX = newOffsetX + gestureOffset.width
                let finalOffsetY = newOffsetY + gestureOffset.height

                // No animation - apply immediately for smoother feel
                scale = clampedScale
                if scale <= 1.0 {
                    offset = .zero
                } else {
                    offset = CGSize(width: finalOffsetX, height: finalOffsetY)
                    offset = constrainOffset(offset, for: scale, in: size)
                }

                // Mark that a zoom just completed
                lastZoomTime = Date()
            }
    }

    private func makeDragGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: scale > 1.0 ? 5 : 1000)
            .updating($gestureOffset) { value, state, _ in
                // Only update when zoomed in (including during active zoom gesture)
                let currentScale = scale * gestureScale
                guard currentScale > 1.01 else { return }
                state = value.translation
            }
            .onEnded { value in
                // Skip if a zoom just completed (within last 50ms) - zoom already handled offset
                let timeSinceZoom = Date().timeIntervalSince(lastZoomTime)
                guard timeSinceZoom > 0.05 else { return }

                // Only apply if we're zoomed in
                let currentScale = scale * gestureScale
                guard currentScale > 1.01 else { return }

                let newOffset = CGSize(
                    width: offset.width + value.translation.width,
                    height: offset.height + value.translation.height
                )
                offset = constrainOffset(newOffset, for: scale, in: size)
            }
    }

    private func makeDoubleTapGesture(in size: CGSize) -> some Gesture {
        SpatialTapGesture(count: 2)
            .onEnded { value in
                withAnimation(.spring(response: 0.3)) {
                    if scale > 1.0 {
                        // Already zoomed in - reset to 1x
                        scale = 1.0
                        offset = .zero
                    } else {
                        // At 1x - zoom to 2.5x centered on tap location
                        let tapLocation = value.location
                        let imageCenter = CGPoint(x: size.width / 2, y: size.height / 2)

                        scale = 2.5

                        // Calculate offset to center the tap point
                        let offsetX = (imageCenter.x - tapLocation.x) * (scale - 1)
                        let offsetY = (imageCenter.y - tapLocation.y) * (scale - 1)

                        offset = CGSize(width: offsetX, height: offsetY)
                        offset = constrainOffset(offset, for: scale, in: size)
                    }
                }
            }
    }

    private func constrainOffset(_ offset: CGSize, for scale: CGFloat, in size: CGSize) -> CGSize {
        // Don't constrain if at 1x zoom
        guard scale > 1.0 else { return .zero }

        // Calculate the maximum allowed offset based on the scaled image size
        let maxOffsetX = (size.width * (scale - 1)) / 2
        let maxOffsetY = (size.height * (scale - 1)) / 2

        return CGSize(
            width: min(max(offset.width, -maxOffsetX), maxOffsetX),
            height: min(max(offset.height, -maxOffsetY), maxOffsetY)
        )
    }
}

// MARK: - Animated Media View

struct AnimatedMediaView: View {
    let videoUrl: String
    let posterUrl: String?
    var availableWidth: CGFloat = ScreenUtilities.mainScreenWidth

    @State private var player: AVPlayer?
    @State private var videoSize: CGSize?
    @State private var itemObserver: NSKeyValueObservation?

    var body: some View {
        ZStack {
            if let player = player {
                if let videoSize = videoSize {
                    VideoPlayer(player: player)
                        .aspectRatio(videoSize.width / videoSize.height, contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .frame(height: calculatedHeight(for: availableWidth))
                        .onAppear {
                            player.play()
                        }
                } else {
                    // While loading, show player without size constraints
                    VideoPlayer(player: player)
                        .frame(height: 300)
                        .onAppear {
                            player.play()
                        }
                }
            } else {
                ProgressView()
                    .frame(height: 300)
            }
        }
        .onAppear {
            if let url = URL(string: videoUrl) {
                let player = AVPlayer(url: url)
                player.actionAtItemEnd = .none

                // Observe when the video dimensions are available
                itemObserver = player.currentItem?.observe(\.presentationSize, options: [.new]) { item, change in
                    if let size = change.newValue, size.width > 0, size.height > 0 {
                        DispatchQueue.main.async {
                            self.videoSize = size
                        }
                    }
                }

                // Loop the video when it ends
                NotificationCenter.default.addObserver(
                    forName: .AVPlayerItemDidPlayToEndTime,
                    object: player.currentItem,
                    queue: .main
                ) { _ in
                    player.seek(to: .zero)
                    player.play()
                }

                self.player = player
            }
        }
        .onDisappear {
            player?.pause()
            itemObserver?.invalidate()
            player = nil
        }
    }

    private func calculatedHeight(for width: CGFloat) -> CGFloat {
        guard let videoSize = videoSize, videoSize.width > 0 else {
            // Default height while loading or if dimensions unavailable
            print("🎥 Video sizing - No video size yet, using default 300")
            return 300
        }

        let aspectRatio = videoSize.height / videoSize.width
        let calculatedHeight = width * aspectRatio

        // Cap maximum height to 100% of screen height
        let maxHeight = ScreenUtilities.mainScreenHeight
        let finalHeight = min(calculatedHeight, maxHeight)

        print("🎥 Video sizing - Original: \(videoSize.width)x\(videoSize.height), AspectRatio: \(aspectRatio), Width: \(width), CalculatedHeight: \(calculatedHeight), FinalHeight: \(finalHeight)")

        return finalHeight
    }
}

// MARK: - Video Player View (Platform wrapper)

#if os(iOS)
struct VideoPlayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear

        let playerLayer = AVPlayerLayer(player: player)
        playerLayer.videoGravity = .resizeAspect
        playerLayer.frame = view.bounds
        view.layer.addSublayer(playerLayer)

        context.coordinator.playerLayer = playerLayer

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        if let playerLayer = context.coordinator.playerLayer {
            playerLayer.frame = uiView.bounds
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator {
        var playerLayer: AVPlayerLayer?
    }
}
#elseif os(macOS)
struct VideoPlayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor

        let playerLayer = AVPlayerLayer(player: player)
        playerLayer.videoGravity = .resizeAspect
        playerLayer.frame = view.bounds
        view.layer?.addSublayer(playerLayer)

        context.coordinator.playerLayer = playerLayer

        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let playerLayer = context.coordinator.playerLayer {
            playerLayer.frame = nsView.bounds
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator {
        var playerLayer: AVPlayerLayer?
    }
}
#endif

// MARK: - Embedded Media View

struct EmbeddedMediaView: View {
    let html: String
    let width: Int
    let height: Int
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        EmbeddedMediaWebView(html: html, colorScheme: colorScheme)
    }
}

#if os(iOS)
struct EmbeddedMediaWebView: UIViewRepresentable {
    let html: String
    let colorScheme: ColorScheme

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.allowsPictureInPictureMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []

        // Enable fullscreen video playback
        if #available(iOS 15.0, *) {
            configuration.preferences.isElementFullscreenEnabled = true
        }

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false

        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        loadContent(in: webView)
    }

    private func loadContent(in webView: WKWebView) {
        let bgColor = colorScheme == .dark ? "#000000" : "#FFFFFF"

        let wrappedHTML = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
            <style>
                * {
                    margin: 0;
                    padding: 0;
                    box-sizing: border-box;
                }
                body {
                    background-color: \(bgColor);
                    overflow: hidden;
                }
                iframe {
                    position: absolute;
                    top: 0;
                    left: 0;
                    width: 100%;
                    height: 100%;
                    border: none;
                }
            </style>
        </head>
        <body>
            \(html)
        </body>
        </html>
        """

        webView.loadHTMLString(wrappedHTML, baseURL: nil)
    }
}
#elseif os(macOS)
struct EmbeddedMediaWebView: NSViewRepresentable {
    let html: String
    let colorScheme: ColorScheme

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        // allowsInlineMediaPlayback is iOS-only; macOS always allows inline playback
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.preferences.isElementFullscreenEnabled = true

        let webView = WKWebView(frame: .zero, configuration: configuration)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        loadContent(in: webView)
    }

    private func loadContent(in webView: WKWebView) {
        let bgColor = colorScheme == .dark ? "#000000" : "#FFFFFF"

        let wrappedHTML = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
            <style>
                * {
                    margin: 0;
                    padding: 0;
                    box-sizing: border-box;
                }
                body {
                    background-color: \(bgColor);
                    overflow: hidden;
                }
                iframe {
                    position: absolute;
                    top: 0;
                    left: 0;
                    width: 100%;
                    height: 100%;
                    border: none;
                }
            </style>
        </head>
        <body>
            \(html)
        </body>
        </html>
        """

        webView.loadHTMLString(wrappedHTML, baseURL: nil)
    }
}
#endif

// MARK: - View Extension for Conditional Modifiers

extension View {
    @ViewBuilder func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

// MARK: - Comment Row View

struct CommentRowView: View {
    let comment: RedditComment
    let fontOption: FontOption

    // For iOS: local collapse state
    // For macOS: externally managed collapse state
    #if os(iOS)
    @State private var isCollapsed = false
    #else
    var isCollapsed: Bool = false
    var hasChildren: Bool = false
    var onToggleCollapse: (() -> Void)? = nil
    #endif

    // Color for indent line based on depth
    private var indentColor: Color {
        let colors: [Color] = [.blue, .green, .orange, .purple, .pink, .cyan]
        return colors[comment.depth % colors.count]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 8) {
                // Indent line for nested comments
                if comment.depth > 0 {
                    Rectangle()
                        .fill(indentColor.opacity(0.3))
                        .frame(width: 2)
                        .padding(.leading, CGFloat(min(comment.depth - 1, 4)) * 12)
                }

                VStack(alignment: .leading, spacing: 8) {
                    // Header: author, score, time
                    HStack(spacing: 8) {
                        #if os(iOS)
                        // iOS: local collapse state with toggle
                        Button {
                            withAnimation {
                                isCollapsed.toggle()
                            }
                        } label: {
                            HStack(spacing: 4) {
                                if !comment.replies.isEmpty {
                                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }

                                Text("u/\(comment.author)")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.orange)
                            }
                        }
                        .buttonStyle(.plain)
                        #else
                        // macOS: external collapse state with callback
                        Button {
                            withAnimation {
                                onToggleCollapse?()
                            }
                        } label: {
                            HStack(spacing: 4) {
                                if hasChildren {
                                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }

                                Text("u/\(comment.author)")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.orange)
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(!hasChildren)
                        #endif

                        Text("•")
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up")
                                .font(.caption2)
                            Text("\(comment.score)")
                                .font(.caption2)
                        }
                        .foregroundStyle(.secondary)

                        Text("•")
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        Text(comment.timeAgo)
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        Spacer()
                    }

                    // Comment body (hidden if collapsed)
                    if !isCollapsed {
                        #if os(iOS)
                        // Use body_html if available (preserves markdown formatting, links, etc.)
                        if let bodyHtml = comment.bodyHtml, !bodyHtml.isEmpty {
                            CommentHTMLView(html: bodyHtml, fontOption: fontOption)
                        } else {
                            Text(comment.decodedBody)
                                .font(fontOption == .serif ?
                                    .system(.subheadline, design: .serif) :
                                    .system(.subheadline, design: .default))
                                .textSelection(.enabled)
                        }
                        #else
                        // On macOS, use plain text to avoid WebView scroll capture issues
                        Text(comment.decodedBody)
                            .font(fontOption == .serif ?
                                .system(.subheadline, design: .serif) :
                                .system(.subheadline, design: .default))
                            .textSelection(.enabled)
                        #endif
                    }
                }
                .padding(.leading, comment.depth > 0 ? 12 : 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(platformBackgroundColor)

            Divider()
                .padding(.leading, CGFloat(min(comment.depth, 5)) * 12 + 16)

            // Nested replies (hidden if collapsed)
            // Use LazyVStack to prevent layout calculation of entire nested tree
            if !isCollapsed && !comment.replies.isEmpty {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(comment.replies) { reply in
                        CommentRowView(comment: reply, fontOption: fontOption)
                    }
                }
            }
        }
    }
}

// MARK: - Comment HTML View (only used for comments with images/rich content)

struct CommentHTMLView: View {
    let html: String
    let fontOption: FontOption
    @State private var contentHeight: CGFloat = 0
    @Environment(\.colorScheme) var colorScheme
    @AppStorage("accentColor") private var accentColor: AccentColorOption = .orange

    var body: some View {
        CommentWebView(html: html, height: $contentHeight, colorScheme: colorScheme, accentColor: accentColor.color, fontOption: fontOption)
            .frame(height: max(contentHeight, 20))
    }
}

#if os(iOS)
struct CommentWebView: UIViewRepresentable {
    let html: String
    @Binding var height: CGFloat
    let colorScheme: ColorScheme
    let accentColor: Color
    let fontOption: FontOption

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.navigationDelegate = context.coordinator
        webView.underPageBackgroundColor = .clear
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // Decode HTML entities (Reddit double-encodes, so decode twice)
        let decodedHTML = html.decodeHTMLEntities().decodeHTMLEntities()

        let styledHTML = createStyledHTML(from: decodedHTML, colorScheme: colorScheme, accentColor: accentColor, fontOption: fontOption)
        context.coordinator.parent = self
        webView.loadHTMLString(styledHTML, baseURL: nil)
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: CommentWebView

        init(_ parent: CommentWebView) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // Better height calculation that measures actual content
            let script = """
            (function() {
                // Force layout
                document.body.style.height = 'auto';
                // Get actual content height
                var range = document.createRange();
                range.selectNodeContents(document.body);
                var rect = range.getBoundingClientRect();
                return Math.ceil(rect.height);
            })();
            """
            webView.evaluateJavaScript(script) { height, error in
                if let height = height as? CGFloat {
                    DispatchQueue.main.async {
                        self.parent.height = height
                    }
                }
            }
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if navigationAction.navigationType == .other {
                decisionHandler(.allow)
                return
            }

            // Handle link taps - open in Safari
            if navigationAction.navigationType == .linkActivated {
                if let url = navigationAction.request.url {
                    UIApplication.shared.open(url)
                }
                decisionHandler(.cancel)
                return
            }

            decisionHandler(.allow)
        }
    }

    func createStyledHTML(from html: String, colorScheme: ColorScheme, accentColor: Color, fontOption: FontOption) -> String {
        let textColor = colorScheme == .dark ? "#FFFFFF" : "#000000"
        let secondaryBg = colorScheme == .dark ? "#2C2C2E" : "#F2F2F7"
        let accentColorHex = accentColor.toHex()

        return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0">
            <style>
                html, body {
                    font-family: \(fontOption.fontFamily);
                    font-size: 15px;
                    line-height: 1.6;
                    color: \(textColor);
                    background-color: transparent;
                    margin: 0;
                    padding: 0;
                    height: auto;
                    min-height: 0;
                }
                p {
                    margin: 0 0 8px 0;
                    padding: 0;
                }
                p:last-child {
                    margin-bottom: 0;
                }
                a {
                    color: \(accentColorHex);
                    text-decoration: none;
                }
                img {
                    max-width: 100%;
                    height: auto;
                    margin: 8px 0;
                    border-radius: 6px;
                }
                code {
                    font-family: 'SF Mono', Menlo, Monaco, monospace;
                    font-size: 13px;
                    background-color: \(secondaryBg);
                    padding: 2px 4px;
                    border-radius: 3px;
                }
                pre {
                    background-color: \(secondaryBg);
                    padding: 8px;
                    border-radius: 6px;
                    overflow-x: auto;
                    margin: 8px 0;
                }
                blockquote {
                    margin: 8px 0;
                    padding: 8px 12px;
                    border-left: 3px solid \(accentColorHex);
                    background-color: \(secondaryBg);
                }
                strong, b {
                    font-weight: 600;
                }
                em, i {
                    font-style: italic;
                }
                table {
                    border-collapse: collapse;
                    margin: 8px 0;
                    width: 100%;
                }
                th, td {
                    border: 1px solid \(secondaryBg);
                    padding: 8px;
                    text-align: left;
                }
                th {
                    background-color: \(secondaryBg);
                    font-weight: 600;
                }
            </style>
        </head>
        <body>
            \(html)
        </body>
        </html>
        """
    }
}
#elseif os(macOS)
struct CommentWebView: NSViewRepresentable {
    let html: String
    @Binding var height: CGFloat
    let colorScheme: ColorScheme
    let accentColor: Color
    let fontOption: FontOption

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        // macOS-specific: disable drawing background for dark mode transparency
        webView.setValue(false, forKey: "drawsBackground")
        webView.underPageBackgroundColor = .clear
        // Disable WebView scrolling so parent ScrollView handles it
        disableWebViewScrolling(webView)
        return webView
    }

    private func disableWebViewScrolling(_ webView: WKWebView) {
        disableScrollingRecursively(in: webView)
    }

    private func disableScrollingRecursively(in view: NSView) {
        for subview in view.subviews {
            if let scrollView = subview as? NSScrollView {
                scrollView.hasVerticalScroller = false
                scrollView.hasHorizontalScroller = false
                scrollView.verticalScrollElasticity = .none
                scrollView.horizontalScrollElasticity = .none
                scrollView.scrollerStyle = .overlay
            }
            disableScrollingRecursively(in: subview)
        }
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        // Decode HTML entities (Reddit double-encodes, so decode twice)
        let decodedHTML = html.decodeHTMLEntities().decodeHTMLEntities()

        let styledHTML = createStyledHTML(from: decodedHTML, colorScheme: colorScheme, accentColor: accentColor, fontOption: fontOption)
        context.coordinator.parent = self
        webView.loadHTMLString(styledHTML, baseURL: nil)
        disableWebViewScrolling(webView)
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: CommentWebView

        init(_ parent: CommentWebView) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // Disable scrolling after content loads
            parent.disableWebViewScrolling(webView)

            // Better height calculation that measures actual content
            let script = """
            (function() {
                // Force layout
                document.body.style.height = 'auto';
                // Get actual content height
                var range = document.createRange();
                range.selectNodeContents(document.body);
                var rect = range.getBoundingClientRect();
                return Math.ceil(rect.height);
            })();
            """
            webView.evaluateJavaScript(script) { height, error in
                if let height = height as? CGFloat {
                    DispatchQueue.main.async {
                        self.parent.height = height
                        // Re-disable after height adjustment
                        self.parent.disableWebViewScrolling(webView)
                    }
                }
            }
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if navigationAction.navigationType == .other {
                decisionHandler(.allow)
                return
            }

            // Handle link taps - open in browser
            if navigationAction.navigationType == .linkActivated {
                if let url = navigationAction.request.url {
                    NSWorkspace.shared.open(url)
                }
                decisionHandler(.cancel)
                return
            }

            decisionHandler(.allow)
        }
    }

    func createStyledHTML(from html: String, colorScheme: ColorScheme, accentColor: Color, fontOption: FontOption) -> String {
        let textColor = colorScheme == .dark ? "#FFFFFF" : "#000000"
        let secondaryBg = colorScheme == .dark ? "#2C2C2E" : "#F2F2F7"
        let accentColorHex = accentColor.toHex()

        return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0">
            <style>
                html, body {
                    font-family: \(fontOption.fontFamily);
                    font-size: 15px;
                    line-height: 1.6;
                    color: \(textColor);
                    background-color: transparent;
                    margin: 0;
                    padding: 0;
                    height: auto;
                    min-height: 0;
                }
                p {
                    margin: 0 0 8px 0;
                    padding: 0;
                }
                p:last-child {
                    margin-bottom: 0;
                }
                a {
                    color: \(accentColorHex);
                    text-decoration: none;
                }
                img {
                    max-width: 100%;
                    height: auto;
                    margin: 8px 0;
                    border-radius: 6px;
                }
                code {
                    font-family: 'SF Mono', Menlo, Monaco, monospace;
                    font-size: 13px;
                    background-color: \(secondaryBg);
                    padding: 2px 4px;
                    border-radius: 3px;
                }
                pre {
                    background-color: \(secondaryBg);
                    padding: 8px;
                    border-radius: 6px;
                    overflow-x: auto;
                    margin: 8px 0;
                }
                blockquote {
                    margin: 8px 0;
                    padding: 8px 12px;
                    border-left: 3px solid \(accentColorHex);
                    background-color: \(secondaryBg);
                }
                strong, b {
                    font-weight: 600;
                }
                em, i {
                    font-style: italic;
                }
                table {
                    border-collapse: collapse;
                    margin: 8px 0;
                    width: 100%;
                }
                th, td {
                    border: 1px solid \(secondaryBg);
                    padding: 8px;
                    text-align: left;
                }
                th {
                    background-color: \(secondaryBg);
                    font-weight: 600;
                }
            </style>
        </head>
        <body>
            \(html)
        </body>
        </html>
        """
    }
}
#endif

