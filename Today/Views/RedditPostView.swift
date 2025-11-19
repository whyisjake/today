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
                Button {
                    // Share functionality handled in context menu
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .contextMenu {
                    if let url = URL(string: article.link) {
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

            // Track article read for review prompts
            Task { @MainActor in
                ReviewRequestManager.shared.incrementArticleReadCount()
                ReviewRequestManager.shared.requestReviewIfAppropriate()
            }
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

            // Gallery images (if available)
            if !post.galleryImages.isEmpty {
                ImageGalleryView(images: post.galleryImages)
            }
            // Embedded media from external video services
            else if let mediaEmbedHtml = post.mediaEmbedHtml,
                    let width = post.mediaEmbedWidth,
                    let height = post.mediaEmbedHeight {
                EmbeddedMediaView(html: mediaEmbedHtml, width: width, height: height)
                    .frame(height: CGFloat(height) * (UIScreen.main.bounds.width / CGFloat(width)))
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
            if let selftextHtml = post.selftextHtml, !selftextHtml.isEmpty {
                PostHTMLView(html: selftextHtml, fontOption: fontOption)
            } else if let selftext = post.selftext, !selftext.isEmpty {
                Text(selftext)
                    .font(fontOption == .serif ?
                        .system(.body, design: .serif) :
                        .system(.body, design: .default))
                    .textSelection(.enabled)
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

// MARK: - Image Size Tracking Helper
struct SizeTrackingAsyncImage: View {
    let imageUrl: String
    let onSizeCalculated: (CGFloat) -> Void

    @State private var image: UIImage?
    @State private var isLoading = true
    @State private var hasFailed = false

    var body: some View {
        Group {
            if let image = image {
                Image(uiImage: image)
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
                .background(Color(.systemGray6))
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
            if let uiImage = UIImage(data: data) {
                await MainActor.run {
                    self.image = uiImage

                    // Calculate height based on aspect ratio
                    let aspectRatio = uiImage.size.height / uiImage.size.width
                    let screenWidth = UIScreen.main.bounds.width - 32 // Account for padding
                    let calculatedHeight = screenWidth * aspectRatio

                    // Cap maximum height to 100% of screen height
                    let maxHeight = UIScreen.main.bounds.height
                    let finalHeight = min(calculatedHeight, maxHeight)

                    print("📸 Image sizing - Original: \(uiImage.size.width)x\(uiImage.size.height), AspectRatio: \(aspectRatio), ScreenWidth: \(screenWidth), CalculatedHeight: \(calculatedHeight), FinalHeight: \(finalHeight)")

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
                            AnimatedMediaView(videoUrl: videoUrl, posterUrl: image.url)
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
                        })
                        .onTapGesture {
                            showFullScreen = true
                        }
                        .tag(index)
                    }
                }
            }
            .tabViewStyle(.page(indexDisplayMode: images.count > 1 ? .always : .never))
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
        .sheet(isPresented: $showFullScreen) {
            FullScreenImageGallery(images: images, currentIndex: $currentPage)
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
                            .background(Color(.systemBackground))
                            .tag(index)
                    } else {
                        ZoomableImageView(imageUrl: image.url)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color(.systemBackground))
                            .tag(index)
                    }
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .background(Color(.systemBackground))
            .ignoresSafeArea()
            .navigationTitle("\(currentIndex + 1) of \(images.count)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    if let imageUrl = URL(string: images[currentIndex].url) {
                        ShareLink(item: imageUrl) {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                }
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
                        .frame(height: calculatedHeight(for: UIScreen.main.bounds.width))
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
        let maxHeight = UIScreen.main.bounds.height
        let finalHeight = min(calculatedHeight, maxHeight)

        print("🎥 Video sizing - Original: \(videoSize.width)x\(videoSize.height), AspectRatio: \(aspectRatio), Width: \(width), CalculatedHeight: \(calculatedHeight), FinalHeight: \(finalHeight)")

        return finalHeight
    }
}

// MARK: - Video Player View (UIKit wrapper)

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

struct EmbeddedMediaWebView: UIViewRepresentable {
    let html: String
    let colorScheme: ColorScheme

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false

        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
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
