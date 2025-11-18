//
//  RedditCommentsView.swift
//  Today
//
//  View for displaying Reddit comments in a threaded format
//

import SwiftUI

struct RedditCommentsView: View {
    let commentsUrl: String
    @State private var comments: [RedditComment] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @AppStorage("fontOption") private var fontOption: FontOption = .serif

    var body: some View {
        Group {
            if isLoading {
                VStack {
                    ProgressView("Loading comments...")
                        .padding()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = errorMessage {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("Failed to Load Comments")
                        .font(.headline)
                    Text(error)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Try Again") {
                        Task {
                            await loadComments()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
            } else if comments.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "bubble.left")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("No Comments Yet")
                        .font(.headline)
                    Text("Be the first to comment!")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(comments) { comment in
                            CommentRowView(comment: comment, fontOption: fontOption)
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
        }
        .navigationTitle("Comments")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadComments()
        }
    }

    private func loadComments() async {
        isLoading = true
        errorMessage = nil

        do {
            comments = try await RedditCommentService.shared.fetchComments(from: commentsUrl)
            isLoading = false
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }
}

struct CommentRowView: View {
    let comment: RedditComment
    let fontOption: FontOption
    @State private var isCollapsed = false

    // Color for indent line based on depth
    private var indentColor: Color {
        let colors: [Color] = [.blue, .green, .orange, .purple, .pink, .cyan]
        return colors[comment.depth % colors.count]
    }

    // Decode HTML entities from plain text
    private func decodeHTMLEntities(_ text: String) -> String {
        var decoded = text
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")

        // Second pass for double-encoded entities
        decoded = decoded
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")

        return decoded
    }

    // Parse simple HTML to AttributedString (lightweight alternative to WebView)
    private func parseSimpleHTML(_ html: String) -> AttributedString {
        // Decode HTML entities first
        let decoded = decodeHTMLEntities(html)

        // Use NSAttributedString.DocumentType.html for parsing
        guard let data = decoded.data(using: .utf8) else {
            return AttributedString(decoded)
        }

        do {
            let nsAttributed = try NSAttributedString(
                data: data,
                options: [.documentType: NSAttributedString.DocumentType.html,
                         .characterEncoding: String.Encoding.utf8.rawValue],
                documentAttributes: nil
            )
            return AttributedString(nsAttributed)
        } catch {
            // Fallback to plain text if parsing fails
            return AttributedString(decoded)
        }
    }

    // Check if HTML contains images or other rich content worth rendering
    private func hasRichContent(_ html: String) -> Bool {
        // Check for images
        if html.contains("<img") {
            return true
        }
        // Check for GIFs/videos
        if html.contains("<video") || html.contains("giphy") || html.contains(".gif") {
            return true
        }
        // Check for tables
        if html.contains("<table") {
            return true
        }
        // Otherwise use plain text (covers bold, italic, links - which look fine as plain text)
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 8) {
                // Indent line for nested comments
                if comment.depth > 0 {
                    Rectangle()
                        .fill(indentColor.opacity(0.3))
                        .frame(width: 2)
                        .padding(.leading, CGFloat(comment.depth - 1) * 12)
                }

                VStack(alignment: .leading, spacing: 8) {
                    // Header: author, score, time
                    HStack(spacing: 8) {
                        Button {
                            withAnimation {
                                isCollapsed.toggle()
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)

                                Text("u/\(comment.author)")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.orange)
                            }
                        }

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
                        // Use body_html if available (preserves markdown formatting, links, etc.)
                        if let bodyHtml = comment.bodyHtml, !bodyHtml.isEmpty {
                            CommentHTMLView(html: bodyHtml, fontOption: fontOption)
                        } else {
                            // Fallback to plain text if body_html is not available
                            Text(decodeHTMLEntities(comment.body))
                                .font(fontOption == .serif ?
                                    .system(.subheadline, design: .serif) :
                                    .system(.subheadline, design: .default))
                                .textSelection(.enabled)
                        }
                    }
                }
                .padding(.leading, comment.depth > 0 ? 12 : 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color(.systemBackground))

            Divider()
                .padding(.leading, CGFloat(comment.depth) * 12 + 16)

            // Nested replies (hidden if collapsed)
            if !isCollapsed && !comment.replies.isEmpty {
                ForEach(comment.replies) { reply in
                    CommentRowView(comment: reply, fontOption: fontOption)
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
        var decodedHTML = html
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")

        // Second pass to handle double-encoded entities like &amp;amp;
        decodedHTML = decodedHTML
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")

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

import WebKit
