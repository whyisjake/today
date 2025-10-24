//
//  ArticleWebView.swift
//  Today
//
//  WebView for displaying full article content
//

import SwiftUI
import SwiftData
import WebKit

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

// Enhanced article detail view with in-app browser option
struct ArticleDetailViewEnhanced: View {
    let article: Article
    @State private var showWebView = false
    @Environment(\.openURL) private var openURL
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        ZStack {
            if showWebView {
                if let url = URL(string: article.link) {
                    ArticleWebView(url: url)
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("Close") {
                                    showWebView = false
                                }
                            }
                            ToolbarItem(placement: .topBarTrailing) {
                                Button {
                                    if let url = URL(string: article.link) {
                                        openURL(url)
                                    }
                                } label: {
                                    Image(systemName: "safari")
                                }
                            }
                        }
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
                                showWebView = true
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
                                if let url = URL(string: article.link) {
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
                .navigationBarTitleDisplayMode(.inline)
            }
        }
        .onAppear {
            markAsRead()
        }
        .animation(.default, value: showWebView)
    }

    private func markAsRead() {
        if !article.isRead {
            article.isRead = true
            try? modelContext.save()
        }
    }
}
