//
//  AIService.swift
//  Today
//
//  Service for AI-powered content summarization
//

import Foundation
import NaturalLanguage

// Foundation Models is only available in iOS 26.0+
#if canImport(FoundationModels)
import FoundationModels
#endif

class AIService {
    static let shared = AIService()

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    private var systemModel: SystemLanguageModel?
    @available(iOS 26.0, *)
    private var session: LanguageModelSession?
    #endif

    private init() {
        // Initialize session if Apple Intelligence is available (iOS 26+)
        if #available(iOS 26.0, *) {
            #if canImport(FoundationModels)
            systemModel = SystemLanguageModel.default
            if systemModel?.isAvailable == true {
                session = LanguageModelSession()
            }
            #endif
        }
    }

    /// Check if Apple Intelligence is available on this device
    var isAppleIntelligenceAvailable: Bool {
        if #available(iOS 26.0, *) {
            #if canImport(FoundationModels)
            return systemModel?.isAvailable ?? false
            #else
            return false
            #endif
        }
        return false
    }

    /// Get detailed availability status
    var availabilityStatus: String {
        if #available(iOS 26.0, *) {
            #if canImport(FoundationModels)
            guard let systemModel = systemModel else {
                return "Apple Intelligence not initialized"
            }
            switch systemModel.availability {
            case .available:
                return "Apple Intelligence is available"
            case .unavailable(.appleIntelligenceNotEnabled):
                return "Apple Intelligence is disabled in Settings"
            case .unavailable(.deviceNotEligible):
                return "This device doesn't support Apple Intelligence"
            case .unavailable(.modelNotReady):
                return "Model is downloading..."
            case .unavailable(_):
                return "Apple Intelligence is unavailable"
            }
            #else
            return "Foundation Models not available"
            #endif
        }
        return "Requires iOS 26.0 or later"
    }

    /// Generate a summary of articles using Apple Intelligence or fallback to basic analysis
    func summarizeArticles(_ articles: [Article]) async -> String {
        guard !articles.isEmpty else {
            return "No articles to summarize."
        }

        // Try Apple Intelligence first if available (iOS 26+)
        if #available(iOS 26.0, *), isAppleIntelligenceAvailable {
            #if canImport(FoundationModels)
            if let session = session {
                do {
                    let summary = try await generateAISummary(articles: articles, session: session)
                    return summary
                } catch {
                    print("Apple Intelligence summarization failed: \(error.localizedDescription)")
                    // Fall through to basic analysis
                }
            }
            #endif
        }

        // Fallback to NLTagger for basic content analysis
        let summary = await analyzeTrends(from: articles)
        return summary
    }

    /// Generate summary using Apple's on-device LLM (iOS 26+)
    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    private func generateAISummary(articles: [Article], session: LanguageModelSession) async throws -> String {
        // Create a concise list of articles for the LLM
        let articleList = articles.prefix(10).enumerated().map { index, article in
            let description = article.articleDescription?.htmlToPlainText.prefix(150) ?? ""
            return "\(index + 1). \(article.title) - \(description)"
        }.joined(separator: "\n\n")

        let prompt = """
        Analyze these recent news articles and provide a brief, engaging summary highlighting the main themes and important stories:

        \(articleList)

        Provide a concise summary in 3-4 sentences that captures the key topics and trends.
        """

        let response = try await session.respond(to: prompt)
        return response
    }
    #endif

    /// Generate conversational response using Apple's on-device LLM (iOS 26+)
    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    private func generateAIResponse(query: String, articles: [Article], session: LanguageModelSession) async throws -> (String, [Article]?) {
        // Prepare article context (limit to avoid token limits)
        let articleContext = articles.prefix(15).map { article in
            "Title: \(article.title)\nRead: \(article.isRead ? "Yes" : "No")\nDate: \(article.publishedDate.formatted())"
        }.joined(separator: "\n---\n")

        let prompt = """
        You are a helpful RSS reader assistant. The user has asked: "\(query)"

        Here are their recent articles:
        \(articleContext)

        Total articles: \(articles.count)
        Unread: \(articles.filter { !$0.isRead }.count)

        Provide a helpful, conversational response to their question. Keep it brief (2-3 sentences) and friendly.
        """

        let response = try await session.respond(to: prompt)

        // Try to identify relevant articles based on the query
        let relevantArticles = identifyRelevantArticles(for: query, in: articles)

        return (response, relevantArticles)
    }
    #endif

    /// Identify relevant articles based on query keywords
    private func identifyRelevantArticles(for query: String, in articles: [Article]) -> [Article]? {
        let lowercasedQuery = query.lowercased()

        // For recommendation/reading queries, return unread articles
        if lowercasedQuery.contains("recommend") || lowercasedQuery.contains("read") || lowercasedQuery.contains("suggest") {
            let unread = articles.filter { !$0.isRead }.sorted { $0.publishedDate > $1.publishedDate }
            return unread.isEmpty ? nil : Array(unread.prefix(5))
        }

        // For recent/latest queries
        if lowercasedQuery.contains("recent") || lowercasedQuery.contains("latest") || lowercasedQuery.contains("new") {
            return Array(articles.sorted { $0.publishedDate > $1.publishedDate }.prefix(5))
        }

        // For unread queries
        if lowercasedQuery.contains("unread") {
            let unread = articles.filter { !$0.isRead }.sorted { $0.publishedDate > $1.publishedDate }
            return unread.isEmpty ? nil : Array(unread.prefix(5))
        }

        // Default: return top articles
        return Array(articles.prefix(5))
    }

    /// Generate a newsletter-style summary with article links (Dave Pell style)
    func generateNewsletterSummary(articles: [Article]) async -> (String, [Article]?) {
        guard !articles.isEmpty else {
            return ("No articles to summarize today.", nil)
        }

        // Get the most interesting articles (unread first, then by date)
        let sortedArticles = articles
            .sorted { a, b in
                if a.isRead != b.isRead {
                    return !a.isRead
                }
                return a.publishedDate > b.publishedDate
            }
            .prefix(10)

        var newsletter = "📰 **Today's Brief**\n\n"
        newsletter += "Here's what you need to know from your feeds today. I've curated the highlights with a bit of context.\n\n"

        // Group by category for better organization
        let articlesByCategory = Dictionary(grouping: Array(sortedArticles), by: { $0.feed?.category ?? "general" })

        var itemNumber = 1
        var featuredArticles: [Article] = []

        for (category, categoryArticles) in articlesByCategory.sorted(by: { $0.key < $1.key }) {
            for article in categoryArticles.prefix(3) {
                newsletter += "**\(itemNumber).** "

                // Add witty intro based on category
                let intro = getNewsletterIntro(for: category, itemNumber: itemNumber)
                newsletter += intro
                newsletter += " "

                // Add article title as the main point
                newsletter += "**\(article.title)**"

                // Add a snippet of context if available
                if let description = article.articleDescription?.htmlToPlainText, !description.isEmpty {
                    let snippet = String(description.prefix(120))
                    newsletter += " — \(snippet)..."
                }

                newsletter += "\n\n"

                featuredArticles.append(article)
                itemNumber += 1

                if itemNumber > 10 { break }
            }
            if itemNumber > 10 { break }
        }

        newsletter += "\n---\n\n"
        newsletter += "That's it for today! Tap any article below to read more. See you tomorrow. ✌️"

        return (newsletter, featuredArticles.isEmpty ? nil : featuredArticles)
    }

    /// Get witty newsletter intro based on category
    private func getNewsletterIntro(for category: String, itemNumber: Int) -> String {
        let intros: [String: [String]] = [
            "tech": [
                "In the latest tech news,",
                "Silicon Valley strikes again:",
                "From the world of tech,",
                "Here's what's buzzing in tech:",
                "Tech news that matters:"
            ],
            "news": [
                "Making headlines:",
                "In case you missed it,",
                "Here's what's happening:",
                "From the news desk,",
                "Worth knowing:"
            ],
            "work": [
                "On the work front,",
                "Career and business news:",
                "From the professional world,",
                "In workplace news,",
                "For your work life:"
            ],
            "social": [
                "Social sphere update:",
                "What people are talking about:",
                "From the social scene,",
                "Trending now:",
                "Social media's buzzing about:"
            ],
            "general": [
                "Interesting read:",
                "Worth your attention:",
                "Here's something:",
                "Don't miss this:",
                "FYI:"
            ]
        ]

        let categoryIntros = intros[category.lowercased()] ?? intros["general"]!
        let index = (itemNumber - 1) % categoryIntros.count
        return categoryIntros[index]
    }

    /// Analyze content trends and generate insights
    private func analyzeTrends(from articles: [Article]) async -> String {
        var insights: [String] = []

        // Group by feed
        let articlesByFeed = Dictionary(grouping: articles, by: { $0.feed?.title ?? "Unknown" })

        insights.append("📊 Today's Overview")
        insights.append("You have \(articles.count) new articles from \(articlesByFeed.keys.count) sources.")

        // Analyze by category
        let articlesByCategory = Dictionary(grouping: articles, by: { $0.feed?.category ?? "general" })

        insights.append("\n📑 By Category:")
        for (category, categoryArticles) in articlesByCategory.sorted(by: { $0.value.count > $1.value.count }) {
            insights.append("  • \(category.capitalized): \(categoryArticles.count) articles")
        }

        // Most active sources
        insights.append("\n📰 Most Active Sources:")
        let topSources = articlesByFeed.sorted { $0.value.count > $1.value.count }.prefix(5)
        for (source, sourceArticles) in topSources {
            insights.append("  • \(source): \(sourceArticles.count) articles")
        }

        // Extract keywords from titles
        let keywords = extractKeywords(from: articles)
        if !keywords.isEmpty {
            insights.append("\n🔑 Trending Topics:")
            for keyword in keywords.prefix(10) {
                insights.append("  • \(keyword)")
            }
        }

        // Recent highlights note
        if !articles.isEmpty {
            insights.append("\n✨ Tap the articles below to read the recent highlights!")
        }

        return insights.joined(separator: "\n")
    }

    /// Extract keywords from article titles
    private func extractKeywords(from articles: [Article]) -> [String] {
        let text = articles.map { $0.title }.joined(separator: " ")

        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = text

        var keywords: [String: Int] = [:]

        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .lexicalClass) { tag, tokenRange in
            if let tag = tag, tag == .noun || tag == .verb {
                let keyword = String(text[tokenRange]).lowercased()

                // Filter out common words and short words
                if keyword.count > 3 && !commonWords.contains(keyword) {
                    keywords[keyword, default: 0] += 1
                }
            }
            return true
        }

        // Return top keywords sorted by frequency
        return keywords
            .sorted { $0.value > $1.value }
            .map { $0.key }
    }

    /// Generate a conversational response about articles using Apple Intelligence when available
    func generateResponse(for query: String, articles: [Article]) async -> (String, [Article]?) {
        // Try Apple Intelligence for more natural responses (iOS 26+)
        if #available(iOS 26.0, *), isAppleIntelligenceAvailable {
            #if canImport(FoundationModels)
            if let session = session {
                do {
                    let result = try await generateAIResponse(query: query, articles: articles, session: session)
                    return result
                } catch {
                    print("Apple Intelligence response failed: \(error.localizedDescription)")
                    // Fall through to pattern-based responses
                }
            }
            #endif
        }

        // Fallback to pattern-based responses
        let lowercasedQuery = query.lowercased()

        // Count queries
        if lowercasedQuery.contains("how many") || lowercasedQuery.contains("count") {
            return ("You have \(articles.count) articles in your feed. \(articles.filter { !$0.isRead }.count) are unread.", nil)
        }

        // Summary queries
        if lowercasedQuery.contains("summary") || lowercasedQuery.contains("summarize") || lowercasedQuery.contains("overview") || lowercasedQuery.contains("what's new") {
            let summary = await summarizeArticles(articles)
            let topArticles = Array(articles.filter { !$0.isRead }.prefix(5))
            return (summary, topArticles.isEmpty ? nil : topArticles)
        }

        // Recommendation queries
        if lowercasedQuery.contains("recommend") || lowercasedQuery.contains("should i read") || lowercasedQuery.contains("what to read") || lowercasedQuery.contains("suggestions") {
            let unread = articles.filter { !$0.isRead }
            let recommended = Array(unread.sorted { $0.publishedDate > $1.publishedDate }.prefix(5))
            let response = recommendArticles(articles)
            return (response, recommended.isEmpty ? nil : recommended)
        }

        // Category/topic queries
        if lowercasedQuery.contains("category") || lowercasedQuery.contains("topic") || lowercasedQuery.contains("categories") || lowercasedQuery.contains("subjects") {
            let categories = Set(articles.compactMap { $0.feed?.category })
            return ("Your articles cover these topics: \(categories.sorted().joined(separator: ", "))", nil)
        }

        // Unread queries
        if lowercasedQuery.contains("unread") || lowercasedQuery.contains("haven't read") {
            let unreadCount = articles.filter { !$0.isRead }.count
            let unreadArticles = Array(articles.filter { !$0.isRead }.sorted { $0.publishedDate > $1.publishedDate }.prefix(5))
            return ("You have \(unreadCount) unread articles. Here are the most recent ones:", unreadArticles.isEmpty ? nil : unreadArticles)
        }

        // Recent queries
        if lowercasedQuery.contains("recent") || lowercasedQuery.contains("latest") || lowercasedQuery.contains("new") {
            let recentArticles = Array(articles.sorted { $0.publishedDate > $1.publishedDate }.prefix(5))
            return ("Here are the most recent articles:", recentArticles.isEmpty ? nil : recentArticles)
        }

        // Feed/source queries
        if lowercasedQuery.contains("feed") || lowercasedQuery.contains("source") || lowercasedQuery.contains("where") {
            let feedCounts = Dictionary(grouping: articles, by: { $0.feed?.title ?? "Unknown" })
                .mapValues { $0.count }
                .sorted { $0.value > $1.value }

            var response = "Your articles come from these sources:\n"
            for (feed, count) in feedCounts.prefix(10) {
                response += "  • \(feed): \(count) articles\n"
            }
            return (response, nil)
        }

        // Trending/popular queries
        if lowercasedQuery.contains("trending") || lowercasedQuery.contains("popular") || lowercasedQuery.contains("hot") {
            let keywords = extractKeywords(from: articles)
            var response = "🔥 Trending topics right now:\n"
            for keyword in keywords.prefix(10) {
                response += "  • \(keyword)\n"
            }
            let topArticles = Array(articles.prefix(5))
            return (response, topArticles.isEmpty ? nil : topArticles)
        }

        // Search/find queries
        if lowercasedQuery.contains("about") || lowercasedQuery.contains("related to") || lowercasedQuery.contains("find") {
            // Extract potential search terms (words after "about", "find", etc.)
            let searchTerms = lowercasedQuery
                .replacingOccurrences(of: "about", with: "")
                .replacingOccurrences(of: "related to", with: "")
                .replacingOccurrences(of: "find", with: "")
                .replacingOccurrences(of: "articles", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if !searchTerms.isEmpty {
                let matchingArticles = articles.filter { article in
                    article.title.localizedCaseInsensitiveContains(searchTerms) ||
                    article.articleDescription?.localizedCaseInsensitiveContains(searchTerms) == true
                }

                if !matchingArticles.isEmpty {
                    return ("I found \(matchingArticles.count) articles about \"\(searchTerms)\":", Array(matchingArticles.prefix(5)))
                } else {
                    return ("I couldn't find any articles about \"\(searchTerms)\". Try searching for something else or ask me to summarize your articles!", nil)
                }
            }
        }

        // Help queries
        if lowercasedQuery.contains("help") || lowercasedQuery.contains("what can you") || lowercasedQuery.contains("how do") {
            let helpText = """
            I can help you with:

            📊 "Summarize today's articles" - Get an overview
            📚 "What should I read?" - Get recommendations
            🔢 "How many articles?" - See counts
            🏷️ "What categories?" - View topics
            🆕 "Show me recent articles" - Latest content
            🔍 "Find articles about [topic]" - Search
            🔥 "What's trending?" - Popular topics

            Try asking me any of these questions!
            """
            return (helpText, nil)
        }

        // Default: acknowledge we don't understand and offer help
        return ("I'm not sure what you're asking. Try questions like:\n\n• 'Summarize today's articles'\n• 'What should I read?'\n• 'Show me recent articles'\n• 'What's trending?'\n\nOr type 'help' to see all my capabilities!", nil)
    }

    private func recommendArticles(_ articles: [Article]) -> String {
        let unread = articles.filter { !$0.isRead }

        guard !unread.isEmpty else {
            return "You're all caught up! No unread articles at the moment."
        }

        let count = min(unread.count, 5)
        return "📚 I found \(count) articles you might be interested in. Tap any article below to read more!"
    }

    private let commonWords = Set([
        "the", "a", "an", "and", "or", "but", "in", "on", "at", "to", "for",
        "of", "with", "by", "from", "up", "about", "into", "through", "during",
        "including", "until", "against", "among", "throughout", "despite", "towards",
        "upon", "concerning", "this", "that", "these", "those", "be", "have", "has",
        "had", "do", "does", "did", "will", "would", "could", "should", "may", "might"
    ])
}

extension Date {
    func timeAgoDisplay() -> String {
        let calendar = Calendar.current
        let now = Date()
        let components = calendar.dateComponents([.minute, .hour, .day], from: self, to: now)

        if let day = components.day, day > 0 {
            return day == 1 ? "1 day ago" : "\(day) days ago"
        } else if let hour = components.hour, hour > 0 {
            return hour == 1 ? "1 hour ago" : "\(hour) hours ago"
        } else if let minute = components.minute, minute > 0 {
            return minute == 1 ? "1 minute ago" : "\(minute) minutes ago"
        } else {
            return "Just now"
        }
    }
}
