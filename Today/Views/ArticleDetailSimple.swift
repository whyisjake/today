//
//  ArticleDetailSimple.swift
//  Today
//
//  Simplified article detail view without cycles
//

import SwiftUI
import SwiftData
import WebKit

// Shared WebView configuration to speed up initialization
class WebViewPool {
    static let shared = WebViewPool()

    private let sharedConfiguration: WKWebViewConfiguration = {
        let config = WKWebViewConfiguration()
        config.dataDetectorTypes = [.link, .phoneNumber]
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

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(article.title)
                    .font(.title2)
                    .fontWeight(.bold)

                HStack {
                    if let author = article.author {
                        Text("By \(author)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(article.publishedDate, style: .date)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Divider()

                // Show full content if available, otherwise show description
                if let contentEncoded = article.contentEncoded {
                    ArticleContentWebView(htmlContent: contentEncoded)
                } else if let content = article.content {
                    ArticleContentWebView(htmlContent: content)
                } else if let description = article.articleDescription {
                    ArticleContentWebView(htmlContent: description)
                }
            }
            .padding()
        }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
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

                    // Open menu with Read in App, Safari, Share, and Mark as Unread options
                    Menu {
                        NavigationLink {
                            ArticleWebViewSimple(url: URL(string: article.link)!)
                        } label: {
                            Label("Read in App", systemImage: "doc.text")
                        }

                        Button {
                            if let url = URL(string: article.link) {
                                openURL(url)
                            }
                        } label: {
                            Label("Open in Safari", systemImage: "safari")
                        }

                        ShareLink(item: URL(string: article.link)!, subject: Text(article.title)) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }

                        Divider()

                        Button {
                            markAsUnreadAndGoBack()
                        } label: {
                            Label("Mark as Unread", systemImage: "envelope.badge")
                        }
                    } label: {
                        Label("Open", systemImage: "arrow.up.forward.square")
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
        .toolbar(.hidden, for: .tabBar)
        .onAppear {
            markAsRead()
        }
    }

    private func markAsRead() {
        if !article.isRead {
            article.isRead = true
            try? modelContext.save()
        }
    }

    private func markAsUnreadAndGoBack() {
        article.isRead = false
        try? modelContext.save()
        dismiss()
    }
}

struct ArticleWebViewSimple: View {
    let url: URL
    @Environment(\.openURL) private var openURL

    var body: some View {
        WebViewRepresentable(url: url)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        openURL(url)
                    } label: {
                        Image(systemName: "safari")
                    }
                }
            }
    }
}

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

// WKWebView for rendering HTML content with proper CSS support
struct ArticleContentWebView: View {
    let htmlContent: String
    @State private var contentHeight: CGFloat = 0
    @State private var selectedURL: URL?

    var body: some View {
        WebViewWithHeight(htmlContent: htmlContent, height: $contentHeight, selectedURL: $selectedURL)
            .frame(height: contentHeight > 0 ? contentHeight : 200)
            .animation(.easeInOut(duration: 0.3), value: contentHeight)
            .navigationDestination(item: $selectedURL) { url in
                ArticleWebViewSimple(url: url)
            }
    }
}

struct WebViewWithHeight: UIViewRepresentable {
    let htmlContent: String
    @Binding var height: CGFloat
    @Binding var selectedURL: URL?
    @Environment(\.colorScheme) var colorScheme
    @AppStorage("accentColor") private var accentColor: AccentColorOption = .orange

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
        let styledHTML = createStyledHTML(from: htmlContent, colorScheme: colorScheme, accentColor: accentColor.color)
        context.coordinator.parent = self
        webView.loadHTMLString(styledHTML, baseURL: nil)
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: WebViewWithHeight

        init(_ parent: WebViewWithHeight) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // Get content height after page finishes loading
            webView.evaluateJavaScript("document.body.scrollHeight") { height, error in
                if let height = height as? CGFloat {
                    DispatchQueue.main.async {
                        self.parent.height = height
                    }
                }
            }
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            // Allow initial page load
            if navigationAction.navigationType == .other {
                decisionHandler(.allow)
                return
            }

            // Handle link taps - open in app WebView
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

    func createStyledHTML(from html: String, colorScheme: ColorScheme, accentColor: Color) -> String {
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
                body {
                    font-family: -apple-system, BlinkMacSystemFont, 'SF Pro Text', 'Helvetica Neue', sans-serif;
                    font-size: 17px;
                    line-height: 1.6;
                    color: \(textColor);
                    background-color: transparent;
                    margin: 0;
                    padding: 0;
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
}

// Extension to convert SwiftUI Color to hex string
extension Color {
    func toHex() -> String {
        guard let components = UIColor(self).cgColor.components else {
            return "#FF4F00" // Fallback to International Orange
        }

        let r = components[0]
        let g = components[1]
        let b = components[2]

        return String(format: "#%02X%02X%02X",
                     Int(r * 255),
                     Int(g * 255),
                     Int(b * 255))
    }
}
