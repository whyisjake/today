//
//  ArticleDetailSimple.swift
//  Today
//
//  Simplified article detail view without cycles
//

import SwiftUI
import SwiftData
import WebKit

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

// Shared WebView configuration to speed up initialization
class WebViewPool {
    static let shared = WebViewPool()

    private let sharedConfiguration: WKWebViewConfiguration = {
        let config = WKWebViewConfiguration()
        #if os(iOS)
        config.dataDetectorTypes = [.link, .phoneNumber]
        #endif
        // iOS 15+ automatically shares process pools, no need to set manually
        return config
    }()

    func makeConfiguration() -> WKWebViewConfiguration {
        return sharedConfiguration
    }
}

struct ArticleDetailSimple: View {
    let article: Article
    let previousArticleID: PersistentIdentifier?
    let nextArticleID: PersistentIdentifier?
    var isAtBottomBinding: Binding<Bool>? = nil // Optional binding for scroll position
    let onNavigateToPrevious: (PersistentIdentifier) -> Void
    let onNavigateToNext: (PersistentIdentifier) -> Void

    @Environment(\.openURL) private var openURL
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @AppStorage("fontOption") private var fontOption: FontOption = .serif
    @AppStorage("shortArticleBehavior") private var shortArticleBehavior: ShortArticleBehavior = .openInAppBrowser
    @AppStorage("accentColor") private var accentColor: AccentColorOption = .orange
    @StateObject private var audioPlayer = ArticleAudioPlayer.shared

    var body: some View {
        articleContent
            .navigationTitle(article.feed?.title ?? "Article")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .topBarTrailing) {
                    toolbarTrailingContent
                }
                ToolbarItem(placement: .bottomBar) {
                    toolbarBottomContent
                }
                #else
                // Combined toolbar: navigation arrows first, then action buttons
                ToolbarItem(placement: .automatic) {
                    macOSToolbarContent
                }
                #endif
            }
            #if os(iOS)
            .toolbar(.hidden, for: .tabBar)
            #endif
            .onDisappear {
                markAsRead()
            }
    }

    @ViewBuilder
    private var articleContent: some View {
        #if os(iOS)
        iOSArticleContent
        #else
        macOSArticleContent
        #endif
    }

    #if os(iOS)
    private var iOSArticleContent: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    articleHeader
                    articleBody(geometry: geometry)
                }
                .padding()
            }
        }
    }
    #endif

    #if os(macOS)
    private var macOSArticleContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Fixed header - full width container, content has horizontal padding
            VStack(alignment: .leading, spacing: 12) {
                articleHeader
                    .padding(.horizontal, 16)

                // Show podcast controls if this is a podcast episode
                if article.hasPodcastAudio {
                    PodcastAudioControls(article: article)
                        .padding(.horizontal, 16)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 16)

            Divider()

            // WebView fills remaining space and handles its own scrolling
            // WebView has its own internal padding via CSS
            if article.hasMinimalContent && shortArticleBehavior == .openInAppBrowser && !article.isRedditPost,
               let url = article.articleURL {
                WebViewRepresentable(url: url)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let contentEncoded = article.contentEncoded {
                ScrollableWebView(
                    htmlContent: contentEncoded,
                    articleID: article.persistentModelID
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let content = article.content {
                ScrollableWebView(
                    htmlContent: content,
                    articleID: article.persistentModelID
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let description = article.articleDescription {
                ScrollableWebView(
                    htmlContent: description,
                    articleID: article.persistentModelID
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    #endif

    @ViewBuilder
    private var articleHeader: some View {
        Text(article.title)
            .font(fontOption == .serif ?
                .system(.title2, design: .serif, weight: .bold) :
                .system(.title2, design: .default, weight: .bold))

        HStack {
            if let author = article.author {
                Text("By \(author)")
                    .font(fontOption == .serif ?
                        .system(.subheadline, design: .serif) :
                        .system(.subheadline, design: .default))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(article.publishedDate, style: .date)
                .font(fontOption == .serif ?
                    .system(.subheadline, design: .serif) :
                    .system(.subheadline, design: .default))
                .foregroundStyle(.secondary)
        }
    }

    #if os(iOS)
    @ViewBuilder
    private func articleBody(geometry: GeometryProxy) -> some View {
        Divider()

        // Show podcast controls if this is a podcast episode
        if article.hasPodcastAudio {
            PodcastAudioControls(article: article)
            Divider()
        }

        // For short articles with "Open in Today Browser", show full web page
        if article.hasMinimalContent && shortArticleBehavior == .openInAppBrowser && !article.isRedditPost,
           let url = article.articleURL {
            WebViewRepresentable(url: url)
                .frame(height: geometry.size.height - 200)
        }
        // Otherwise show article content
        else if let contentEncoded = article.contentEncoded {
            ArticleContentWebView(htmlContent: contentEncoded)
        } else if let content = article.content {
            ArticleContentWebView(htmlContent: content)
        } else if let description = article.articleDescription {
            ArticleContentWebView(htmlContent: description)
        }
    }
    #endif

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

    private var isPlayingThisArticle: Bool {
        audioPlayer.currentArticle?.id == article.id &&
        (audioPlayer.isPlaying || audioPlayer.isPaused)
    }

    @ViewBuilder
    private var toolbarTrailingContent: some View {
        HStack(spacing: 16) {
            // Audio player button
            Button {
                if audioPlayer.currentArticle?.id == article.id {
                    audioPlayer.togglePlayPause()
                } else {
                    audioPlayer.play(article: article)
                }
            } label: {
                Image(systemName: isPlayingThisArticle ? "waveform.circle.fill" : "play.circle")
            }
            .foregroundStyle(accentColor.color)
            .accessibilityLabel(isPlayingThisArticle ? "Pause article audio" : "Play article audio")

            // Share button (only show if article has a valid link)
            if let url = article.articleURL {
                ShareLink(item: url, subject: Text(article.title)) {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
    }

    @ViewBuilder
    private var toolbarBottomContent: some View {
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

            // Reddit Comments button (if this is a Reddit post)
            if article.isRedditPost {
                NavigationLink {
                    RedditPostView(
                        article: article,
                        previousArticleID: previousArticleID,
                        nextArticleID: nextArticleID,
                        onNavigateToPrevious: onNavigateToPrevious,
                        onNavigateToNext: onNavigateToNext
                    )
                } label: {
                    Label("Comments", systemImage: "bubble.left.and.bubble.right")
                }
            }

            // Read in App button with long-press menu (only show if article has a valid link)
            if let url = article.articleURL {
                NavigationLink {
                    ArticleWebViewSimple(url: url)
                } label: {
                    Label("Read in App", systemImage: "doc.text")
                }
                .contextMenu {
                    Button {
                        openURL(url)
                    } label: {
                        Label("Open in Safari", systemImage: "safari")
                    }

                    ShareLink(item: url, subject: Text(article.title)) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }

                    Divider()

                    Button {
                        markAsUnreadAndGoBack()
                    } label: {
                        Label("Mark as Unread", systemImage: "envelope.badge")
                    }
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

    #if os(macOS)
    @ViewBuilder
    private var macOSToolbarContent: some View {
        HStack(spacing: 16) {
            // Navigation arrows first
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

            Divider()
                .frame(height: 16)

            // Action buttons
            Button {
                if audioPlayer.currentArticle?.id == article.id {
                    audioPlayer.togglePlayPause()
                } else {
                    audioPlayer.play(article: article)
                }
            } label: {
                Image(systemName: isPlayingThisArticle ? "waveform.circle.fill" : "play.circle")
            }
            .foregroundStyle(accentColor.color)
            .accessibilityLabel(isPlayingThisArticle ? "Pause article audio" : "Play article audio")

            if let url = article.articleURL {
                ShareLink(item: url, subject: Text(article.title)) {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
    }
    #endif
}

struct ArticleWebViewSimple: View {
    let url: URL
    @Environment(\.openURL) private var openURL

    var body: some View {
        WebViewRepresentable(url: url)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .topBarTrailing) {
                    safariButton
                }
                #else
                ToolbarItem(placement: .primaryAction) {
                    safariButton
                }
                #endif
            }
    }

    private var safariButton: some View {
        Button {
            openURL(url)
        } label: {
            Image(systemName: "safari")
        }
    }
}

#if os(iOS)
struct WebViewRepresentable: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        if webView.url != url {
            webView.load(URLRequest(url: url))
        }
    }
}
#elseif os(macOS)
struct WebViewRepresentable: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        if webView.url != url {
            webView.load(URLRequest(url: url))
        }
    }
}
#endif

// WKWebView for rendering HTML content with proper CSS support
struct ArticleContentWebView: View {
    let htmlContent: String
    @State private var contentHeight: CGFloat = 0
    @State private var selectedURL: URL?

    var body: some View {
        WebViewWithHeight(htmlContent: htmlContent, height: $contentHeight, selectedURL: $selectedURL)
            .frame(height: max(contentHeight, 200))
            .navigationDestination(item: $selectedURL) { url in
                ArticleWebViewSimple(url: url)
            }
    }
}

// macOS: WebView that handles its own scrolling
#if os(macOS)
struct ScrollableWebView: NSViewRepresentable {
    let htmlContent: String
    let articleID: PersistentIdentifier? // For tracking which article's scroll position
    @Environment(\.colorScheme) var colorScheme
    @AppStorage("accentColor") private var accentColor: AccentColorOption = .orange
    @AppStorage("fontOption") private var fontOption: FontOption = .serif

    func makeCoordinator() -> Coordinator {
        Coordinator(self, articleID: articleID)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WebViewPool.shared.makeConfiguration()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator

        // Transparent background for dark mode
        webView.underPageBackgroundColor = .clear
        webView.setValue(false, forKey: "drawsBackground")
        
        // Set up scroll observation
        context.coordinator.setupScrollObservation(webView: webView)
        
        // Listen for page down notification
        context.coordinator.setupPageDownNotification(webView: webView)

        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let styledHTML = createStyledHTML(from: htmlContent, colorScheme: colorScheme, accentColor: accentColor.color, fontOption: fontOption)
        context.coordinator.parent = self
        webView.loadHTMLString(styledHTML, baseURL: nil)
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: ScrollableWebView
        let articleID: PersistentIdentifier?
        private var scrollObserver: NSKeyValueObservation?
        private var pageDownObserver: NSObjectProtocol?

        init(_ parent: ScrollableWebView, articleID: PersistentIdentifier?) {
            self.parent = parent
            self.articleID = articleID
        }
        
        deinit {
            scrollObserver?.invalidate()
            if let observer = pageDownObserver {
                NotificationCenter.default.removeObserver(observer)
            }
        }
        
        func setupScrollObservation(webView: WKWebView) {
            // Observe scroll position changes via contentView.bounds on macOS
            guard let scrollView = webView.enclosingScrollView else { return }
            
            // Use a debounced approach to avoid too many notifications
            scrollObserver = scrollView.contentView.observe(\.bounds, options: [.new]) { [weak self] contentView, _ in
                guard let self = self, 
                      let articleID = self.articleID,
                      let scrollView = contentView.enclosingScrollView,
                      let documentView = scrollView.documentView else { return }
                
                let scrollPosition = scrollView.documentVisibleRect.maxY
                let contentHeight = documentView.frame.height
                
                // Only post if we have valid dimensions
                guard contentHeight > 0 else { return }
                
                // Consider "at bottom" if within 100 points of the end
                let isAtBottom = (contentHeight - scrollPosition) < 100
                
                // Post on main thread to be safe
                DispatchQueue.main.async {
                    if isAtBottom {
                        NotificationCenter.default.post(
                            name: .articleScrolledToBottom,
                            object: articleID
                        )
                    } else {
                        NotificationCenter.default.post(
                            name: .articleScrolledFromBottom,
                            object: articleID
                        )
                    }
                }
            }
        }
        
        func setupPageDownNotification(webView: WKWebView) {
            // Listen for space bar "page down" command
            pageDownObserver = NotificationCenter.default.addObserver(
                forName: .scrollPageDown,
                object: nil,
                queue: .main
            ) { [weak webView] _ in
                guard let webView = webView,
                      let scrollView = webView.enclosingScrollView else { return }
                
                // Scroll down by viewport height
                let currentY = scrollView.contentView.bounds.origin.y
                let viewportHeight = scrollView.contentView.bounds.height
                let newY = min(currentY + viewportHeight,
                              (scrollView.documentView?.frame.height ?? 0) - viewportHeight)
                
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.25
                    context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    scrollView.contentView.animator().setBoundsOrigin(NSPoint(x: 0, y: newY))
                }
            }
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if navigationAction.navigationType == .other {
                decisionHandler(.allow)
                return
            }

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
}
#endif

// Shared HTML styling function for WebViewWithHeight
// Uses Tailwind Typography-inspired styles embedded locally (no network request)
private func createStyledHTML(from html: String, colorScheme: ColorScheme, accentColor: Color, fontOption: FontOption) -> String {
    // Convert SwiftUI Color to hex string
    let accentColorHex = accentColor.toHex()
    let isDark = colorScheme == .dark

    // Colors based on color scheme (Tailwind Typography defaults)
    let textColor = isDark ? "#f3f4f6" : "#1f2937"           // gray-100 / gray-800
    let textColorMuted = isDark ? "#9ca3af" : "#6b7280"      // gray-400 / gray-500
    let textColorFaint = isDark ? "#6b7280" : "#9ca3af"      // gray-500 / gray-400
    let bgCode = isDark ? "#374151" : "#f3f4f6"              // gray-700 / gray-100
    let borderColor = isDark ? "#4b5563" : "#e5e7eb"         // gray-600 / gray-200
    let bgBlockquote = isDark ? "rgba(55, 65, 81, 0.5)" : "rgba(243, 244, 246, 0.5)"

    // Font family based on user preference
    let fontFamily = fontOption == .serif
        ? "ui-serif, Georgia, Cambria, 'Times New Roman', Times, serif"
        : "ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif"

    // Clean up WordPress emoji images and CDATA
    let cleanedHTML = html
        .replacingOccurrences(of: "<img[^>]*class=\"wp-smiley\"[^>]*>", with: "", options: .regularExpression)
        .replacingOccurrences(of: "<img[^>]*wp-smiley[^>]*>", with: "", options: .regularExpression)
        .replacingOccurrences(of: "<![CDATA[", with: "")
        .replacingOccurrences(of: "]]>", with: "")

    return """
    <!DOCTYPE html>
    <html>
    <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0">
        <style>
            /* Tailwind Typography-inspired prose styles (embedded locally) */
            *, *::before, *::after {
                box-sizing: border-box;
            }

            html, body {
                background-color: transparent;
                margin: 0;
                padding: 0;
                overflow: visible;
                -webkit-overflow-scrolling: auto;
            }

            .prose {
                color: \(textColor);
                font-family: \(fontFamily);
                font-size: 1.125rem;
                line-height: 1.778;
                max-width: 70ch;
                margin-left: auto;
                margin-right: auto;
                padding: 1rem 1.5rem;
            }

            /* Paragraphs */
            .prose p {
                margin-top: 1.25em;
                margin-bottom: 1.25em;
            }

            .prose p:first-child {
                margin-top: 0;
            }

            /* Links */
            .prose a {
                color: \(accentColorHex);
                text-decoration: none;
                font-weight: 500;
            }

            .prose a:hover {
                text-decoration: underline;
            }

            /* Bold & Italic */
            .prose strong {
                color: \(textColor);
                font-weight: 600;
            }

            .prose em {
                font-style: italic;
            }

            /* Headings */
            .prose h1, .prose h2, .prose h3, .prose h4, .prose h5, .prose h6 {
                color: \(textColor);
                font-weight: 700;
                line-height: 1.3;
                margin-top: 2em;
                margin-bottom: 0.75em;
            }

            .prose h1 { font-size: 2.25em; margin-top: 0; }
            .prose h2 { font-size: 1.5em; }
            .prose h3 { font-size: 1.25em; }
            .prose h4 { font-size: 1.125em; }
            .prose h5 { font-size: 1em; }
            .prose h6 { font-size: 0.875em; color: \(textColorMuted); }

            /* Blockquotes */
            .prose blockquote {
                border-left: 4px solid \(accentColorHex);
                background-color: \(bgBlockquote);
                padding: 1em 1.25em;
                margin: 1.5em 0;
                font-style: italic;
                color: \(textColorMuted);
                border-radius: 0 0.5rem 0.5rem 0;
            }

            .prose blockquote p {
                margin: 0;
            }

            /* Lists */
            .prose ul, .prose ol {
                margin-top: 1.25em;
                margin-bottom: 1.25em;
                padding-left: 1.625em;
            }

            .prose ul {
                list-style-type: disc;
            }

            .prose ol {
                list-style-type: decimal;
            }

            .prose li {
                margin-top: 0.5em;
                margin-bottom: 0.5em;
                padding-left: 0.375em;
            }

            .prose li::marker {
                color: \(textColorFaint);
            }

            .prose ol > li::marker {
                font-weight: 400;
            }

            /* Nested lists */
            .prose ul ul, .prose ol ol, .prose ul ol, .prose ol ul {
                margin-top: 0.5em;
                margin-bottom: 0.5em;
            }

            /* Code */
            .prose code {
                color: \(textColor);
                background-color: \(bgCode);
                padding: 0.25em 0.4em;
                border-radius: 0.375rem;
                font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace;
                font-size: 0.875em;
                font-weight: 500;
            }

            .prose pre {
                background-color: \(bgCode);
                color: \(textColor);
                overflow-x: auto;
                padding: 1em 1.25em;
                border-radius: 0.5rem;
                margin: 1.5em 0;
                font-size: 0.875em;
                line-height: 1.714;
            }

            .prose pre code {
                background-color: transparent;
                padding: 0;
                font-weight: inherit;
                color: inherit;
                font-size: inherit;
                border-radius: 0;
            }

            /* Images */
            .prose img {
                max-width: 100%;
                height: auto;
                margin-top: 1.5em;
                margin-bottom: 1.5em;
                border-radius: 0.5rem;
            }

            .prose figure {
                margin: 1.5em 0;
            }

            .prose figcaption {
                color: \(textColorMuted);
                font-size: 0.875em;
                margin-top: 0.75em;
                text-align: center;
            }

            /* Horizontal Rule */
            .prose hr {
                border: none;
                border-top: 1px solid \(borderColor);
                margin: 2.5em 0;
            }

            /* Tables */
            .prose table {
                width: 100%;
                border-collapse: collapse;
                margin: 1.5em 0;
                font-size: 0.875em;
            }

            .prose thead {
                border-bottom: 2px solid \(borderColor);
            }

            .prose th {
                color: \(textColor);
                font-weight: 600;
                padding: 0.75em 1em;
                text-align: left;
            }

            .prose td {
                padding: 0.75em 1em;
                border-bottom: 1px solid \(borderColor);
            }

            .prose tbody tr:last-child td {
                border-bottom: none;
            }

            /* Video and embeds */
            .prose video, .prose iframe {
                max-width: 100%;
                margin: 1.5em 0;
                border-radius: 0.5rem;
            }

            /* Definition lists */
            .prose dl {
                margin: 1.25em 0;
            }

            .prose dt {
                font-weight: 600;
                margin-top: 1em;
            }

            .prose dd {
                margin-left: 1.625em;
                margin-top: 0.25em;
            }

            /* Abbreviations */
            .prose abbr[title] {
                text-decoration: underline dotted;
                cursor: help;
            }

            /* Small text */
            .prose small {
                font-size: 0.875em;
            }

            /* Subscript and superscript */
            .prose sub, .prose sup {
                font-size: 0.75em;
                line-height: 0;
                position: relative;
                vertical-align: baseline;
            }

            .prose sup {
                top: -0.5em;
            }

            .prose sub {
                bottom: -0.25em;
            }
        </style>
    </head>
    <body>
        <article class="prose">
            \(cleanedHTML)
        </article>
    </body>
    </html>
    """
}

#if os(iOS)
struct WebViewWithHeight: UIViewRepresentable {
    let htmlContent: String
    @Binding var height: CGFloat
    @Binding var selectedURL: URL?
    @Environment(\.colorScheme) var colorScheme
    @AppStorage("accentColor") private var accentColor: AccentColorOption = .orange
    @AppStorage("fontOption") private var fontOption: FontOption = .serif

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> WKWebView {
        // Use shared configuration for faster initialization
        let configuration = WebViewPool.shared.makeConfiguration()

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.navigationDelegate = context.coordinator

        // Make webview background transparent to inherit from SwiftUI
        webView.underPageBackgroundColor = .clear

        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let styledHTML = createStyledHTML(from: htmlContent, colorScheme: colorScheme, accentColor: accentColor.color, fontOption: fontOption)
        context.coordinator.parent = self
        webView.loadHTMLString(styledHTML, baseURL: nil)
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: WebViewWithHeight

        init(_ parent: WebViewWithHeight) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.evaluateJavaScript("Math.max(document.body.scrollHeight, document.documentElement.scrollHeight)") { height, error in
                if let height = height as? CGFloat {
                    DispatchQueue.main.async {
                        self.parent.height = height
                    }
                } else if let error = error {
                    print("Error calculating height: \(error)")
                }
            }
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if navigationAction.navigationType == .other {
                decisionHandler(.allow)
                return
            }

            if navigationAction.navigationType == .linkActivated {
                if let url = navigationAction.request.url {
                    DispatchQueue.main.async {
                        self.parent.selectedURL = url
                    }
                }
                decisionHandler(.cancel)
                return
            }

            decisionHandler(.allow)
        }
    }
}
#elseif os(macOS)
struct WebViewWithHeight: NSViewRepresentable {
    let htmlContent: String
    @Binding var height: CGFloat
    @Binding var selectedURL: URL?
    @Environment(\.colorScheme) var colorScheme
    @AppStorage("accentColor") private var accentColor: AccentColorOption = .orange
    @AppStorage("fontOption") private var fontOption: FontOption = .serif

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> WKWebView {
        // Use shared configuration for faster initialization
        let configuration = WebViewPool.shared.makeConfiguration()

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator

        // Make webview background transparent to inherit from SwiftUI
        webView.underPageBackgroundColor = .clear

        // macOS-specific: disable drawing background for transparency
        webView.setValue(false, forKey: "drawsBackground")

        // Disable WebView's internal scrolling so parent ScrollView can scroll
        disableWebViewScrolling(webView)

        return webView
    }

    private func disableWebViewScrolling(_ webView: WKWebView) {
        // Recursively find and disable all scroll views
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
                // Disable scroll wheel events
                scrollView.allowsMagnification = false
            }
            disableScrollingRecursively(in: subview)
        }
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let styledHTML = createStyledHTML(from: htmlContent, colorScheme: colorScheme, accentColor: accentColor.color, fontOption: fontOption)
        context.coordinator.parent = self
        context.coordinator.webViewRef = webView
        webView.loadHTMLString(styledHTML, baseURL: nil)

        // Re-apply scroll disabling after update
        disableWebViewScrolling(webView)
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: WebViewWithHeight
        weak var webViewRef: WKWebView?

        init(_ parent: WebViewWithHeight) {
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
                } else if let error = error {
                    print("Error calculating height: \(error)")
                }
            }
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if navigationAction.navigationType == .other {
                decisionHandler(.allow)
                return
            }

            if navigationAction.navigationType == .linkActivated {
                if let url = navigationAction.request.url {
                    DispatchQueue.main.async {
                        self.parent.selectedURL = url
                    }
                }
                decisionHandler(.cancel)
                return
            }

            decisionHandler(.allow)
        }
    }
}
#endif

// Extension to convert SwiftUI Color to hex string
extension Color {
    func toHex() -> String {
        #if os(iOS)
        guard let components = UIColor(self).cgColor.components else {
            return "#FF4F00" // Fallback to International Orange
        }
        #elseif os(macOS)
        guard let nsColor = NSColor(self).usingColorSpace(.deviceRGB),
              let components = nsColor.cgColor.components else {
            return "#FF4F00" // Fallback to International Orange
        }
        #endif

        let r = components[0]
        let g = components[1]
        let b = components[2]

        return String(format: "#%02X%02X%02X",
                     Int(r * 255),
                     Int(g * 255),
                     Int(b * 255))
    }
}
