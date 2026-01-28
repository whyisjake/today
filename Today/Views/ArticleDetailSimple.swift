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
    let onNavigateToPrevious: (PersistentIdentifier) -> Void
    let onNavigateToNext: (PersistentIdentifier) -> Void

    @Environment(\.openURL) private var openURL
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @AppStorage("fontOption") private var fontOption: FontOption = .serif
    @AppStorage("shortArticleBehavior") private var shortArticleBehavior: ShortArticleBehavior = .openInAppBrowser
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
                ToolbarItem(placement: .primaryAction) {
                    toolbarTrailingContent
                }
                ToolbarItem(placement: .automatic) {
                    toolbarBottomContent
                }
                #endif
            }
            #if os(iOS)
            .toolbar(.hidden, for: .tabBar)
            #endif
            .onAppear {
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
            // Fixed header area
            VStack(alignment: .leading, spacing: 16) {
                articleHeader

                // Show podcast controls if this is a podcast episode
                if article.hasPodcastAudio {
                    PodcastAudioControls(article: article)
                }
            }
            .padding()

            Divider()

            // Scrollable WebView area - let WebView handle its own scrolling
            macOSWebViewContent
        }
    }

    @ViewBuilder
    private var macOSWebViewContent: some View {
        if article.hasMinimalContent && shortArticleBehavior == .openInAppBrowser && !article.isRedditPost,
           let url = article.articleURL {
            WebViewRepresentable(url: url)
        } else if let contentEncoded = article.contentEncoded {
            ScrollableWebView(htmlContent: contentEncoded)
        } else if let content = article.content {
            ScrollableWebView(htmlContent: content)
        } else if let description = article.articleDescription {
            ScrollableWebView(htmlContent: description)
        }
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
            .foregroundStyle(Color.accentColor)
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
    @State private var selectedURL: URL?
    @Environment(\.colorScheme) var colorScheme
    @AppStorage("accentColor") private var accentColor: AccentColorOption = .orange
    @AppStorage("fontOption") private var fontOption: FontOption = .serif

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WebViewPool.shared.makeConfiguration()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator

        // Transparent background for dark mode
        webView.underPageBackgroundColor = .clear
        webView.setValue(false, forKey: "drawsBackground")

        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let styledHTML = createStyledHTML(from: htmlContent, colorScheme: colorScheme, accentColor: accentColor.color, fontOption: fontOption)
        context.coordinator.parent = self
        webView.loadHTMLString(styledHTML, baseURL: nil)
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: ScrollableWebView

        init(_ parent: ScrollableWebView) {
            self.parent = parent
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
private func createStyledHTML(from html: String, colorScheme: ColorScheme, accentColor: Color, fontOption: FontOption) -> String {
    // Dynamic colors based on color scheme
    let textColor = colorScheme == .dark ? "#FFFFFF" : "#000000"
    let secondaryBg = colorScheme == .dark ? "#2C2C2E" : "#F2F2F7"
    let borderColor = colorScheme == .dark ? "#3A3A3C" : "#E5E5EA"

    // Convert SwiftUI Color to hex string
    let accentColorHex = accentColor.toHex()
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
            html, body {
                font-family: \(fontOption.fontFamily);
                font-size: 18px;
                line-height: 1.7;
                color: \(textColor);
                background-color: transparent;
                margin: 0;
                padding: 16px;
                overflow: visible;
                -webkit-overflow-scrolling: auto;
            }

            p {
                margin: 0 0 16px 0;
                padding: 0;
            }

            h1, h2, h3, h4, h5, h6 {
                font-weight: 600;
                margin: 24px 0 12px 0;
                line-height: 1.3;
            }

            h1 { font-size: 28px; }
            h2 { font-size: 24px; }
            h3 { font-size: 20px; }
            h4 { font-size: 18px; }

            ul, ol {
                margin: 16px 0;
                padding-left: 28px;
            }

            li {
                margin: 8px 0;
                padding-left: 4px;
                line-height: 1.6;
            }

            blockquote {
                margin: 16px 0;
                padding: 12px 16px;
                border-left: 4px solid \(accentColorHex);
                background-color: \(secondaryBg);
                font-style: italic;
            }

            pre {
                background-color: \(secondaryBg);
                padding: 12px;
                border-radius: 6px;
                overflow-x: auto;
                margin: 16px 0;
            }

            code {
                font-family: 'SF Mono', Menlo, Monaco, monospace;
                font-size: 14px;
                background-color: \(secondaryBg);
                padding: 2px 6px;
                border-radius: 3px;
            }

            pre code {
                background-color: transparent;
                padding: 0;
            }

            a {
                color: \(accentColorHex);
                text-decoration: none;
            }

            img {
                max-width: 100%;
                height: auto;
                margin: 16px 0;
                border-radius: 8px;
            }

            hr {
                border: none;
                border-top: 1px solid \(borderColor);
                margin: 24px 0;
            }

            strong, b {
                font-weight: 600;
            }

            em, i {
                font-style: italic;
            }
        </style>
    </head>
    <body>
        \(cleanedHTML)
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
