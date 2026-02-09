//
//  ArticleWebView.swift
//  Today
//
//  WebView for displaying full article content
//

import SwiftUI
import SwiftData
import WebKit

#if os(iOS)
import SafariServices

// Safari View Controller wrapper with full WebAuthn/passkey support
struct SafariView: UIViewControllerRepresentable {
    let url: URL
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let config = SFSafariViewController.Configuration()
        config.entersReaderIfAvailable = false
        config.barCollapsingEnabled = true

        let safari = SFSafariViewController(url: url, configuration: config)
        safari.delegate = context.coordinator
        safari.preferredControlTintColor = .systemBlue
        safari.dismissButtonStyle = .done

        return safari
    }

    func updateUIViewController(_ safari: SFSafariViewController, context: Context) {
        // No updates needed
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, SFSafariViewControllerDelegate {
        var parent: SafariView

        init(_ parent: SafariView) {
            self.parent = parent
        }

        func safariViewControllerDidFinish(_ controller: SFSafariViewController) {
            parent.dismiss()
        }
    }
}

// WKWebView for basic viewing (does NOT support WebAuthn)
struct ArticleWebView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.dataDetectorTypes = [.link, .phoneNumber]

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true

        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // Only load if not already loading this URL
        if webView.url != url {
            let request = URLRequest(url: url)
            webView.load(request)
        }
    }
}
#elseif os(macOS)
// macOS Safari View using WKWebView (SFSafariViewController is iOS-only)
struct SafariView: NSViewRepresentable {
    let url: URL
    @Environment(\.dismiss) private var dismiss

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

// WKWebView for basic viewing
struct ArticleWebView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        // Only load if not already loading this URL
        if webView.url != url {
            let request = URLRequest(url: url)
            webView.load(request)
        }
    }
}
#endif

// Enhanced article detail view with in-app browser option
struct ArticleDetailViewEnhanced: View {
    let article: Article
    @State private var showSafariView = false
    @Environment(\.openURL) private var openURL
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        ZStack {
            if showSafariView {
                if let url = article.articleURL {
                    // Use SafariView for full WebAuthn/passkey support
                    SafariView(url: url)
                        .ignoresSafeArea()
                } else {
                    Text("Invalid URL: \(article.link)")
                        .foregroundStyle(.red)
                }
            } else {
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

                        if let description = article.articleDescription {
                            Text(description.htmlToAttributedString)
                                .font(.body)
                        }

                        VStack(spacing: 12) {
                            Button {
                                showSafariView = true
                            } label: {
                                Label("Read in App", systemImage: "doc.text")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.accentColor)
                            .foregroundStyle(.white)
                            .cornerRadius(10)
                            .buttonStyle(.plain)

                            Button {
                                if let url = article.articleURL {
                                    openURL(url)
                                }
                            } label: {
                                Label("Open in Safari", systemImage: "safari")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.gray.opacity(0.2))
                            .foregroundStyle(.primary)
                            .cornerRadius(10)
                        }
                        .padding(.top)
                    }
                    .padding()
                }
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
            }
        }
        .onDisappear {
            markAsRead()
        }
        .animation(.default, value: showSafariView)
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
}
