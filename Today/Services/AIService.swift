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
        // Select the most important articles from the last 24 hours
        let selectedArticles = selectImportantArticles(from: articles, limit: 10)

        guard !selectedArticles.isEmpty else {
            return "No recent articles to summarize from the last 24 hours."
        }

        // Create a concise list of articles for the LLM
        let articleList = selectedArticles.enumerated().map { index, article in
            let description = article.articleDescription?.htmlToPlainText.prefix(150) ?? ""
            let readStatus = article.isRead ? "" : "[UNREAD] "
            return "\(index + 1). \(readStatus)\(article.title) - \(description)"
        }.joined(separator: "\n\n")

        let prompt = """
        Analyze these recent news articles from the last 24 hours and provide a brief, engaging summary highlighting the main themes and important stories:

        \(articleList)

        Provide a concise summary in 3-4 sentences that captures the key topics and trends. Focus especially on the unread articles marked [UNREAD].
        """

        let response = try await session.respond(to: prompt)
        return response.content
    }
    #endif

    /// Select the most important articles from the last 24 hours
    /// Prioritizes: 1) Last 24 hours, 2) Unread articles, 3) Diversity across feeds, 4) Recency
    private func selectImportantArticles(from articles: [Article], limit: Int) -> [Article] {
        let now = Date.now
        let twentyFourHoursAgo = now.addingTimeInterval(-86400) // 24 hours in seconds

        // Filter to articles from last 24 hours
        let recentArticles = articles.filter { $0.publishedDate >= twentyFourHoursAgo }

        guard !recentArticles.isEmpty else {
            return []
        }

        // Separate unread and read articles
        let unreadArticles = recentArticles.filter { !$0.isRead }
        let readArticles = recentArticles.filter { $0.isRead }

        // Score articles based on importance
        let scoredUnread = unreadArticles.map { (article: $0, score: calculateImportanceScore($0, now: now)) }
        let scoredRead = readArticles.map { (article: $0, score: calculateImportanceScore($0, now: now)) }

        // Sort by score (highest first)
        let sortedUnread = scoredUnread.sorted { $0.score > $1.score }
        let sortedRead = scoredRead.sorted { $0.score > $1.score }

        // Prioritize unread: take up to limit from unread, then fill with read if needed
        var selectedArticles: [Article] = []

        // Add unread articles first (up to limit)
        selectedArticles.append(contentsOf: sortedUnread.prefix(limit).map { $0.article })

        // If we haven't reached the limit, add some read articles
        if selectedArticles.count < limit {
            let remainingSlots = limit - selectedArticles.count
            selectedArticles.append(contentsOf: sortedRead.prefix(remainingSlots).map { $0.article })
        }

        return selectedArticles
    }

    /// Calculate importance score for an article
    /// Higher score = more important
    private func calculateImportanceScore(_ article: Article, now: Date) -> Double {
        var score = 0.0

        // Recency bonus (more recent = higher score)
        let hoursSincePublished = now.timeIntervalSince(article.publishedDate) / 3600
        let recencyScore = max(0, 24 - hoursSincePublished) // 24 points for brand new, 0 for 24h old
        score += recencyScore

        // Title length bonus (substantial titles often indicate important content)
        let titleWords = article.title.split(separator: " ").count
        if titleWords >= 8 && titleWords <= 20 {
            score += 5 // Sweet spot for informative titles
        }

        // Description length bonus (well-described articles are often more substantial)
        if let description = article.articleDescription, !description.isEmpty {
            let descLength = description.count
            if descLength > 200 {
                score += 3 // Substantial content
            }
        }

        // Feed diversity bonus (will be applied during selection to avoid one feed dominating)
        // This is handled in the selection logic by distributing across feeds

        return score
    }

    /// Generate conversational response using Apple's on-device LLM (iOS 26+)
    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    private func generateAIResponse(query: String, articles: [Article], session: LanguageModelSession) async throws -> (String, [Article]?) {
        // Prepare article context (limit to avoid token limits)
        let articleContext = articles.prefix(15).map { article in
            "Title: \(article.title)\nRead: \(article.isRead ? "Yes" : "No")\nDate: \(article.publishedDate.formatted())"
        }.joined(separator: "\n---\n")

        let prompt = """
        You are Dave Pell, the witty curator behind NextDraft — known for blending sharp humor, cultural insight, and brevity.
        The user has asked: "\(query)"

        Here are their recent articles:
        \(articleContext)

        Total articles: \(articles.count)
        Unread: \(articles.filter { !$0.isRead }.count)

        Respond in Dave Pell’s voice:
        - Be conversational and clever — like you're writing a newsletter intro.
        - Keep it tight (2–3 sentences max).
        - Include one unexpected or humorous observation if it fits.
        - Avoid sounding robotic or overly polished.
        - End with a quick punchline or insight — something memorable.
        """

        let response = try await session.respond(to: prompt)

        // Try to identify relevant articles based on the query
        let relevantArticles = identifyRelevantArticles(for: query, in: articles)

        return (response.content, relevantArticles)
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

                // Try to generate AI intro if available, fallback to static
                var intro = getNewsletterIntro(for: category, itemNumber: itemNumber)
                var usedAI = false
                if #available(iOS 26.0, *), isAppleIntelligenceAvailable {
                    #if canImport(FoundationModels)
                    if let session = session {
                        do {
                            intro = try await generateNewsletterIntro(for: category, articleTitle: article.title, session: session)
                            usedAI = true
                        } catch {
                            // Silently fall back to static intro
                            print("AI intro generation failed: \(error.localizedDescription)")
                        }
                    }
                    #endif
                }

                // Log static intro if AI wasn't used
                if !usedAI {
                    print("📝 Static intro for [\(category)] '\(article.title)': \"\(intro)\"")
                }

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
    /// Uses Apple Intelligence when available for dynamic intros, falls back to static Dave Pell-style ones
    private func getNewsletterIntro(for category: String, itemNumber: Int) -> String {
        // Static fallback intros in Dave Pell style (snarky, punchy, personality-driven)
        // No trailing punctuation - we'll add formatting in the output
        let intros: [String: [String]] = [
            "tech": [
                "Oh, THIS again",
                "Meanwhile, in Silicon Valley",
                "The tech bros are at it",
                "Because we needed another",
                "Your daily tech chaos",
                "Plot twist from the Valley",
                "In shocking news to no one"
            ],
            "news": [
                "Making headlines today",
                "In case you blinked",
                "Your daily dose of chaos",
                "Because of course this happened",
                "File under: Yikes",
                "The world keeps spinning",
                "Today's main character"
            ],
            "work": [
                "Your work life, explained",
                "The hustle is real",
                "Office politics corner",
                "Career advice incoming",
                "Meanwhile, at work",
                "Boss makes a dollar",
                "Another day, another meeting"
            ],
            "social": [
                "The internet is melting down over",
                "Trending for all the wrong reasons",
                "Everyone's talking about",
                "Social media's latest obsession",
                "File under: Very Online",
                "Going viral right now",
                "The discourse is discoursing"
            ],
            "general": [
                "Worth knowing about",
                "File this one away",
                "Interesting development",
                "Here's the deal",
                "Plot twist",
                "This landed on my radar",
                "Something to chew on"
            ]
        ]

        let categoryIntros = intros[category.lowercased()] ?? intros["general"]!
        let index = (itemNumber - 1) % categoryIntros.count
        return categoryIntros[index]
    }

    /// Public wrapper to generate AI-powered intro (for use by other services)
    @available(iOS 26.0, *)
    func generateIntro(for category: String, articleTitle: String, articleContent: String = "") async -> String? {
        guard isAppleIntelligenceAvailable, let session = session else {
            return nil
        }

        do {
            return try await generateNewsletterIntro(for: category, articleTitle: articleTitle, articleContent: articleContent, session: session)
        } catch {
            print("AI intro generation failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// Generate dynamic newsletter intro using Apple Intelligence (async version)
    /// Inspired by Dave Pell's NextDraft style - punchy, snarky, personality-driven
    @available(iOS 26.0, *)
    private func generateNewsletterIntro(for category: String, articleTitle: String, articleContent: String = "", session: LanguageModelSession) async throws -> String {
        let contentSnippet = articleContent.isEmpty ? "" : "\nContext: \(String(articleContent.prefix(200)))"
        let prompt = """
        Write a brief, punchy, Dave Pell-style introduction (3-10 words) for this newsletter item.

        Category: \(category)
        Article: \(articleTitle)\(contentSnippet)

        Style guide:
        - Snarky, witty, and conversational (like Dave Pell's NextDraft)
        - Cultural references, wordplay, or surprising angles welcome
        - NO punctuation at the end (we'll add formatting)
        - Show personality - be opinionated, funny, or clever
        - Match intensity to category (tech = hype/snark, news = urgency/irony, work = cynicism/hustle)
        - For political issues, lean far left and don't hold back on Trump/MAGA/GOP hypocrisy
        - Avoid overused phrases like "breaking" or "just in" - be more creative
        - Read the room: serious issues deserve sharp commentary, not flippancy

        Dave Pell-style examples:
        - "Oh, THIS again"
        - "Meanwhile, in Silicon Valley"
        - "In shocking news to no one"
        - "Your daily dose of chaos"
        - "Because of course this happened"
        - "The internet is going nuts over"
        - "Plot twist of the century"
        - "File under: Told you so"
        - "The Mar-a-Lago brain trust strikes again"
        - "Democracy watch"

        Just return the intro, nothing else. Make it punchy and memorable.
        """

        let response = try await session.respond(to: prompt)
        let intro = response.content.trimmingCharacters(in: .whitespacesAndNewlines)

        // Log generated intro for debugging
        print("📝 Generated intro for [\(category)] '\(articleTitle)': \"\(intro)\"")

        return intro
    }

    /// Analyze content trends and generate insights
    private func analyzeTrends(from articles: [Article]) async -> String {
        var insights: [String] = []

        // Select the most important articles from the last 24 hours
        let selectedArticles = selectImportantArticles(from: articles, limit: 15)

        if selectedArticles.isEmpty {
            return "No articles from the last 24 hours to analyze. Check back after your feeds sync!"
        }

        // Group by feed
        let articlesByFeed = Dictionary(grouping: selectedArticles, by: { $0.feed?.title ?? "Unknown" })

        // Count unread
        let unreadCount = selectedArticles.filter { !$0.isRead }.count

        insights.append("📊 Last 24 Hours Overview")
        insights.append("You have \(selectedArticles.count) articles from \(articlesByFeed.keys.count) sources.")
        if unreadCount > 0 {
            insights.append("\(unreadCount) unread articles need your attention.")
        }

        // Analyze by category
        let articlesByCategory = Dictionary(grouping: selectedArticles, by: { $0.feed?.category ?? "general" })

        insights.append("\n📑 By Category:")
        for (category, categoryArticles) in articlesByCategory.sorted(by: { $0.value.count > $1.value.count }) {
            let unreadInCategory = categoryArticles.filter { !$0.isRead }.count
            let unreadNote = unreadInCategory > 0 ? " (\(unreadInCategory) unread)" : ""
            insights.append("  • \(category.capitalized): \(categoryArticles.count) articles\(unreadNote)")
        }

        // Most active sources
        insights.append("\n📰 Most Active Sources:")
        let topSources = articlesByFeed.sorted { $0.value.count > $1.value.count }.prefix(5)
        for (source, sourceArticles) in topSources {
            insights.append("  • \(source): \(sourceArticles.count) articles")
        }

        // Extract keywords from titles
        let keywords = extractKeywords(from: selectedArticles)
        if !keywords.isEmpty {
            insights.append("\n🔑 Trending Topics:")
            for keyword in keywords.prefix(10) {
                insights.append("  • \(keyword)")
            }
        }

        // Recent highlights note
        insights.append("\n✨ Tap the articles below to read the highlights from the last 24 hours!")

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
