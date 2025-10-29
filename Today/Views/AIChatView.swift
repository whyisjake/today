//
//  AIChatView.swift
//  Today
//
//  AI-powered chat interface for article summaries and recommendations
//

import SwiftUI
import SwiftData
import Combine

struct NewsletterItem: Identifiable, Equatable {
    let id = UUID()
    let summary: String
    let article: Article?

    static func == (lhs: NewsletterItem, rhs: NewsletterItem) -> Bool {
        lhs.id == rhs.id
    }
}

class ChatMessage: Identifiable, ObservableObject {
    let id = UUID()
    @Published var content: String
    let isUser: Bool
    let timestamp: Date
    @Published var recommendedArticles: [Article]?
    @Published var newsletterItems: [NewsletterItem]?
    @Published var isTyping: Bool = false
    let isNewsletter: Bool  // Track if this is a newsletter message from the start

    init(content: String, isUser: Bool, recommendedArticles: [Article]? = nil, newsletterItems: [NewsletterItem]? = nil, isTyping: Bool = false, isNewsletter: Bool = false) {
        self.content = content
        self.isUser = isUser
        self.timestamp = Date()
        self.recommendedArticles = recommendedArticles
        self.newsletterItems = newsletterItems
        self.isTyping = isTyping
        self.isNewsletter = isNewsletter
    }
}

struct AIChatView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Article.publishedDate, order: .reverse) private var articles: [Article]

    @State private var messages: [ChatMessage] = []
    @State private var inputText = ""
    @State private var isProcessing = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if messages.isEmpty {
                    // Welcome screen
                    VStack(spacing: 20) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 60))
                            .foregroundStyle(Color.accentColor)

                        Text("AI Summary Assistant")
                            .font(.title2)
                            .fontWeight(.bold)

                        Text("Ask me about your articles or get a curated news summary.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)

                        // Newsletter-style summary button
                        Button {
                            Task { @MainActor in
                                try? await Task.sleep(nanoseconds: 50_000_000)
                                generateNewsletterSummary()
                            }
                        } label: {
                            VStack(spacing: 8) {
                                Image(systemName: "newspaper.fill")
                                    .font(.title)
                                Text("Generate Today's Newsletter")
                                    .font(.headline)
                                Text("Get a curated summary with commentary")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.accentColor)
                            .foregroundStyle(.white)
                            .cornerRadius(12)
                        }
                        .padding(.horizontal)
                        .disabled(articles.isEmpty || isProcessing)

                        VStack(alignment: .leading, spacing: 12) {
                            Text("Or try asking:")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            SuggestionButton(text: "What should I read?", action: sendMessage)
                            SuggestionButton(text: "Show me recent articles", action: sendMessage)
                            SuggestionButton(text: "What's trending?", action: sendMessage)
                            SuggestionButton(text: "Help", action: sendMessage)
                        }
                        .padding()
                    }
                    .frame(maxHeight: .infinity)
                } else {
                    // Chat messages
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 16) {
                                ForEach(messages) { message in
                                    MessageBubble(message: message)
                                        .id(message.id)
                                }
                            }
                            .padding()
                        }
                        .onChange(of: messages.count) { _, _ in
                            if let lastMessage = messages.last {
                                withAnimation {
                                    proxy.scrollTo(lastMessage.id, anchor: .bottom)
                                }
                            }
                        }
                    }
                }

                // Input area
                Divider()

                HStack(spacing: 12) {
                    TextField("Ask about your articles...", text: $inputText, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1...4)
                        .disabled(isProcessing)
                        .onSubmit {
                            if !inputText.isEmpty && !isProcessing {
                                sendMessage(inputText)
                            }
                        }

                    Button {
                        sendMessage(inputText)
                    } label: {
                        Image(systemName: isProcessing ? "hourglass" : "arrow.up.circle.fill")
                            .font(.title2)
                            .foregroundStyle(inputText.isEmpty ? .gray : Color.accentColor)
                    }
                    .disabled(inputText.isEmpty || isProcessing)
                }
                .padding()
            }
            .navigationTitle("AI Summary")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        messages.removeAll()
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                    }
                    .disabled(messages.isEmpty)
                }
            }
        }
    }

    private func sendMessage(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // Add user message
        messages.append(ChatMessage(content: trimmed, isUser: true))
        inputText = ""
        isProcessing = true

        // Generate AI response
        Task {
            let (response, recommendedArticles) = await AIService.shared.generateResponse(for: trimmed, articles: Array(articles))

            await MainActor.run {
                messages.append(ChatMessage(content: response, isUser: false, recommendedArticles: recommendedArticles))
                isProcessing = false
            }
        }
    }

    private func generateNewsletterSummary() {
        isProcessing = true

        // Create message immediately with typing indicator
        let message = ChatMessage(content: "", isUser: false, isTyping: true, isNewsletter: true)
        messages.append(message)

        Task {
            // Use streaming on-device AI if available (iOS 18+)
            if #available(iOS 18.0, *), OnDeviceAIService.shared.isAvailable {
                do {
                    var items: [NewsletterItem] = []

                    for try await event in OnDeviceAIService.shared.generateNewsletterSummaryStream(articles: Array(articles)) {
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
                    let (text, _) = await AIService.shared.generateNewsletterSummary(articles: Array(articles))
                    await MainActor.run {
                        message.content = text
                        message.newsletterItems = nil
                    }
                }
            } else {
                // Use basic service for older iOS versions
                let (text, _) = await AIService.shared.generateNewsletterSummary(articles: Array(articles))
                await MainActor.run {
                    message.isTyping = false
                    message.content = text
                    message.newsletterItems = nil
                }
            }

            await MainActor.run {
                isProcessing = false
            }
        }
    }
}

struct MessageBubble: View {
    @ObservedObject var message: ChatMessage
    @State private var isVisible: Bool = false

    private func parseMarkdown(_ text: String) -> AttributedString {
        do {
            return try AttributedString(markdown: text, options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace))
        } catch {
            return AttributedString(text)
        }
    }

    var body: some View {
        HStack {
            if message.isUser {
                Spacer()
            }

            VStack(alignment: message.isUser ? .trailing : .leading, spacing: 8) {
                // Show typing indicator or content
                if message.isTyping {
                    TypingIndicator()
                        .padding(12)
                        .background(Color.gray.opacity(0.2))
                        .cornerRadius(16)
                } else {
                    // Show header text - style newsletter headers specially
                    if message.isNewsletter {
                        // Newsletter header with accent color and divider
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
                    } else {
                        // Regular message
                        Text(parseMarkdown(message.content))
                            .padding(12)
                            .background(message.isUser ? Color.accentColor : Color.gray.opacity(0.2))
                            .foregroundStyle(message.isUser ? .white : .primary)
                            .cornerRadius(16)
                            .textSelection(.enabled)
                    }
                }

                // Show newsletter items (summary + article link interleaved)
                if let items = message.newsletterItems, !items.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(items) { item in
                            if let article = item.article {
                                // Regular newsletter item with article link
                                NavigationLink {
                                    ArticleDetailSimple(article: article, previousArticleID: nil, nextArticleID: nil, onNavigateToPrevious: { _ in }, onNavigateToNext: { _ in })
                                } label: {
                                    VStack(alignment: .leading, spacing: 8) {
                                        // Summary text
                                        Text(parseMarkdown(item.summary))
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .textSelection(.enabled)
                                            .foregroundStyle(.primary)

                                        Divider()

                                        // Article link inside the same box
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
                                // Closing message or other non-article content
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
                    .padding(.horizontal, 4)
                }

                // Show recommended articles if available (for non-newsletter responses)
                if let articles = message.recommendedArticles, !articles.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(articles) { article in
                            NavigationLink {
                                ArticleDetailSimple(article: article, previousArticleID: nil, nextArticleID: nil, onNavigateToPrevious: { _ in }, onNavigateToNext: { _ in })
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "doc.text.fill")
                                        .font(.caption)
                                        .foregroundStyle(Color.accentColor)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(article.title)
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                            .foregroundStyle(.primary)
                                            .lineLimit(2)
                                            .multilineTextAlignment(.leading)

                                        if let feedTitle = article.feed?.title {
                                            Text(feedTitle)
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                    Spacer()

                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(10)
                                .background(Color.accentColor.opacity(0.1))
                                .cornerRadius(8)
                            }
                        }
                    }
                    .padding(.horizontal, 4)
                }

                Text(message.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if !message.isUser {
                Spacer()
            }
        }
        .opacity(isVisible ? 1 : 0)
        .onAppear {
            // Only animate AI messages (non-user messages)
            if !message.isUser {
                withAnimation(.easeIn(duration: 0.5)) {
                    isVisible = true
                }
            } else {
                // User messages appear immediately
                isVisible = true
            }
        }
    }
}

struct SuggestionButton: View {
    let text: String
    let action: (String) -> Void

    var body: some View {
        Button {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 50_000_000)
                action(text)
            }
        } label: {
            HStack {
                Text(text)
                    .font(.subheadline)
                Spacer()
                Image(systemName: "arrow.right")
                    .font(.caption)
            }
            .padding()
            .background(Color.accentColor.opacity(0.1))
            .foregroundStyle(Color.accentColor)
            .cornerRadius(10)
        }
    }
}

// Typing indicator with animated dots
struct TypingIndicator: View {
    @State private var dotCount = 0

    let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(Color.gray)
                    .frame(width: 8, height: 8)
                    .opacity(index < dotCount ? 1.0 : 0.3)
                    .animation(.easeInOut(duration: 0.3), value: dotCount)
            }
        }
        .onReceive(timer) { _ in
            dotCount = (dotCount + 1) % 4
        }
    }
}

#Preview {
    AIChatView()
        .modelContainer(for: Article.self, inMemory: true)
}
