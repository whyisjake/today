//
//  AIChatView.swift
//  Today
//
//  AI-powered chat interface for article summaries and recommendations
//

import SwiftUI
import SwiftData

struct ChatMessage: Identifiable, Equatable {
    let id = UUID()
    let content: String
    let isUser: Bool
    let timestamp: Date
    let recommendedArticles: [Article]?

    init(content: String, isUser: Bool, recommendedArticles: [Article]? = nil) {
        self.content = content
        self.isUser = isUser
        self.timestamp = Date()
        self.recommendedArticles = recommendedArticles
    }

    static func == (lhs: ChatMessage, rhs: ChatMessage) -> Bool {
        lhs.id == rhs.id
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
                            .foregroundStyle(.blue)

                        Text("AI Summary Assistant")
                            .font(.title2)
                            .fontWeight(.bold)

                        Text("Ask me about your articles or request a summary of today's content.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)

                        VStack(alignment: .leading, spacing: 12) {
                            Text("Try asking:")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            SuggestionButton(text: "Summarize today's articles", action: sendMessage)
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
                            .foregroundStyle(inputText.isEmpty ? .gray : .blue)
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
}

struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.isUser {
                Spacer()
            }

            VStack(alignment: message.isUser ? .trailing : .leading, spacing: 8) {
                Text(message.content)
                    .padding(12)
                    .background(message.isUser ? Color.blue : Color.gray.opacity(0.2))
                    .foregroundStyle(message.isUser ? .white : .primary)
                    .cornerRadius(16)

                // Show recommended articles if available
                if let articles = message.recommendedArticles, !articles.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(articles) { article in
                            NavigationLink {
                                ArticleDetailSimple(article: article)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "doc.text.fill")
                                        .font(.caption)
                                        .foregroundStyle(.blue)

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
                                .background(Color.blue.opacity(0.1))
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
    }
}

struct SuggestionButton: View {
    let text: String
    let action: (String) -> Void

    var body: some View {
        Button {
            action(text)
        } label: {
            HStack {
                Text(text)
                    .font(.subheadline)
                Spacer()
                Image(systemName: "arrow.right")
                    .font(.caption)
            }
            .padding()
            .background(Color.blue.opacity(0.1))
            .foregroundStyle(.blue)
            .cornerRadius(10)
        }
    }
}

#Preview {
    AIChatView()
        .modelContainer(for: Article.self, inMemory: true)
}
