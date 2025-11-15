//
//  RedditPostView.swift
//  Today
//
//  Combined view for Reddit posts with inline comments
//

import SwiftUI

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
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        // Post content section
                        PostContentView(post: post, fontOption: fontOption, openURL: openURL)

                        Divider()
                            .padding(.vertical, 16)

                        // Comments section
                        if comments.isEmpty {
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
                                    ForEach(comments) { comment in
                                        CommentRowView(comment: comment, fontOption: fontOption)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.bottom, 32)
                }
            }
        }
        .navigationTitle(article.feed?.title ?? "Reddit")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: URL(string: article.link)!, subject: Text(article.title)) {
                    Image(systemName: "square.and.arrow.up")
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
                        if let url = URL(string: article.link) {
                            openURL(url)
                        }
                    } label: {
                        Label("Safari", systemImage: "safari")
                    }
                    .contextMenu {
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
        .task {
            await loadPost()
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
}

// MARK: - Post Content View

struct PostContentView: View {
    let post: ParsedRedditPost
    let fontOption: FontOption
    let openURL: OpenURLAction

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Title
            Text(post.title)
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

            // Post image (if available)
            if let imageUrl = post.imageUrl, let url = URL(string: imageUrl) {
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
            if let selftextHtml = post.selftextHtml, !selftextHtml.isEmpty {
                PostHTMLView(html: selftextHtml, fontOption: fontOption)
            } else if let selftext = post.selftext, !selftext.isEmpty {
                Text(selftext)
                    .font(fontOption == .serif ?
                        .system(.body, design: .serif) :
                        .system(.body, design: .default))
                    .textSelection(.enabled)
            }

            // Link to external content (if it's a link post)
            if post.url != post.permalink, let url = URL(string: post.url) {
                Button {
                    openURL(url)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("View linked content")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Text(url.host ?? post.url)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Image(systemName: "arrow.up.forward")
                            .font(.caption)
                    }
                    .padding(12)
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
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
        // Decode HTML entities (Reddit returns HTML-encoded)
        let decodedHTML = html
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")

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

import WebKit
