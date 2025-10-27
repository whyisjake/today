//
//  OnDeviceAIService.swift
//  Today
//
//  On-device AI text generation using Apple Intelligence
//

import Foundation
import NaturalLanguage

@available(iOS 18.0, *)
class OnDeviceAIService {
    static let shared = OnDeviceAIService()

    private init() {}

    /// Check if on-device AI is available
    var isAvailable: Bool {
        // Check if the device supports Apple Intelligence features
        return true // Will implement proper check
    }

    /// Newsletter item structure for returning structured data
    struct NewsletterItemData {
        let summary: String
        let article: Article?
    }

    /// Generate a newsletter-style summary using on-device AI
    func generateNewsletterSummary(articles: [Article]) async throws -> (String, [NewsletterItemData]) {
        guard !articles.isEmpty else {
            throw AIError.noArticles
        }

        // Get the most interesting articles
        let sortedArticles = articles
            .sorted { a, b in
                if a.isRead != b.isRead {
                    return !a.isRead
                }
                return a.publishedDate > b.publishedDate
            }
            .prefix(10)

        // Generate creative title and intro using AI
        let (title, intro) = await generateNewsletterTitleAndIntro(articles: Array(sortedArticles))

        var newsletter = "✨ \(title)\n\n"
        if !intro.isEmpty {
            newsletter += "\(intro)"
        }

        var newsletterItems: [NewsletterItemData] = []
        var itemNumber = 1

        // Process each article with on-device summarization
        for article in sortedArticles {
            let itemPrefix = "**\(itemNumber).** "

            // Use NaturalLanguage to generate summary
            let summary: String
            if let smartSummary = await generateSmartSummary(for: article, itemNumber: itemNumber) {
                summary = itemPrefix + smartSummary
            } else {
                // Fallback to article title
                summary = itemPrefix + "**\(article.title)**"
            }

            newsletterItems.append(NewsletterItemData(summary: summary, article: article))
            itemNumber += 1
        }

        // Add closing message as the last newsletter item (without an article link)
        let closingMessage = "**That's it for today!** ✌️\n\nTap any article above to read more. See you tomorrow."
        newsletterItems.append(NewsletterItemData(summary: closingMessage, article: nil))

        return (newsletter, newsletterItems)
    }

    /// Generate a smart summary for an article using Apple's NaturalLanguage
    private func generateSmartSummary(for article: Article, itemNumber: Int) async -> String? {
        // Get article content (NOT including title in the summary text)
        var contentText = ""

        // Get the content, preferring content:encoded > content > description
        if let contentEncoded = article.contentEncoded?.htmlToPlainText, !contentEncoded.isEmpty {
            contentText = contentEncoded
        } else if let content = article.content?.htmlToPlainText, !content.isEmpty {
            contentText = content
        } else if let description = article.articleDescription?.htmlToPlainText, !description.isEmpty {
            contentText = description
        }

        // Extract key sentences from content (not title)
        let summary = extractKeyInformation(from: contentText, title: article.title)

        // Generate dynamic, content-aware intro
        let intro = await generateDynamicIntro(title: article.title, content: contentText, category: article.feed?.category ?? "general")

        // Format: Italic intro + em dash + Title (bold) + em dash + summary
        return "*\(intro)* — **\(article.title)** — \(summary)"
    }

    /// Extract key information using NaturalLanguage framework
    private func extractKeyInformation(from text: String, title: String) -> String {
        // Split into sentences
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text

        var sentences: [String] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let sentence = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !sentence.isEmpty && sentence.count > 20 {
                sentences.append(sentence)
            }
            return true
        }

        guard !sentences.isEmpty else {
            return String(text.prefix(150))
        }

        // Score sentences by importance
        let scoredSentences = sentences.map { sentence in
            (sentence: sentence, score: scoreSentence(sentence, title: title, fullText: text))
        }

        // Get top sentences by importance, but respect a reasonable length
        let topSentences = scoredSentences.sorted { $0.score > $1.score }

        var summary = ""
        var totalLength = 0
        let maxLength = 250 // Slightly longer limit

        for sentenceData in topSentences {
            let sentence = sentenceData.sentence
            // Add sentence if it doesn't make the summary too long
            if totalLength + sentence.count <= maxLength {
                if !summary.isEmpty {
                    summary += " "
                }
                summary += sentence
                totalLength = summary.count
            } else if summary.isEmpty {
                // If first sentence is too long, truncate at word boundary
                let words = sentence.split(separator: " ")
                var truncated = ""
                for word in words {
                    if truncated.count + word.count + 1 > maxLength - 3 {
                        break
                    }
                    if !truncated.isEmpty {
                        truncated += " "
                    }
                    truncated += word
                }
                summary = truncated + "..."
                break
            }

            // Stop after we have at least 150 characters and 1-2 sentences
            if summary.count >= 150 && summary.split(separator: ".").count >= 1 {
                break
            }
        }

        return summary.isEmpty ? String(text.prefix(150)) : summary
    }

    /// Score a sentence for importance using NaturalLanguage features
    private func scoreSentence(_ sentence: String, title: String, fullText: String) -> Double {
        var score = 0.0

        // Use NLTagger to extract key terms
        let tagger = NLTagger(tagSchemes: [.lexicalClass, .nameType])
        tagger.string = sentence

        // Count important words (nouns, proper nouns, verbs)
        tagger.enumerateTags(in: sentence.startIndex..<sentence.endIndex,
                            unit: .word,
                            scheme: .lexicalClass) { tag, range in
            let word = String(sentence[range]).lowercased()

            if let tag = tag {
                switch tag {
                case .noun, .verb:
                    score += 1.0
                case .adjective:
                    score += 0.5
                default:
                    break
                }
            }

            // Boost if word appears in title
            if title.lowercased().contains(word) && word.count > 4 {
                score += 2.0
            }

            return true
        }

        // Check for named entities (people, places, organizations)
        tagger.enumerateTags(in: sentence.startIndex..<sentence.endIndex,
                            unit: .word,
                            scheme: .nameType) { tag, range in
            if tag != nil {
                score += 3.0 // Named entities are very important
            }
            return true
        }

        // Prefer sentences earlier in the text
        if let sentenceRange = fullText.range(of: sentence) {
            let position = Double(fullText.distance(from: fullText.startIndex, to: sentenceRange.lowerBound))
            let totalLength = Double(fullText.count)
            let normalizedPosition = position / totalLength

            // Earlier sentences get higher scores (inverse)
            score += (1.0 - normalizedPosition) * 2.0
        }

        // Normalize by sentence length
        let wordCount = sentence.components(separatedBy: .whitespaces).count
        return score / Double(max(wordCount, 1))
    }

    /// Generate dynamic intro using AI - delegate to AIService which has Apple Intelligence
    private func generateDynamicIntro(title: String, content: String, category: String) async -> String {
        // Try using AIService's Apple Intelligence integration if available (iOS 26+)
        if #available(iOS 26.0, *) {
            if let aiIntro = await AIService.shared.generateIntro(for: category, articleTitle: title, articleContent: content) {
                return aiIntro
            }
        }

        // Fallback to Dave Pell-style static intros when AI isn't available
        // No trailing punctuation - formatting added in output
        let fallbacks: [String: [String]] = [
            "tech": ["Oh, THIS again", "Meanwhile, in Silicon Valley", "The tech bros are at it", "Plot twist from the Valley"],
            "news": ["Your daily dose of chaos", "File under: Yikes", "In case you blinked", "Making headlines today"],
            "work": ["The hustle is real", "Boss makes a dollar", "Meanwhile, at work", "Career advice incoming"],
            "social": ["The internet is melting down over", "File under: Very Online", "Going viral right now", "Everyone's talking about"],
            "general": ["Plot twist", "Here's the deal", "Worth knowing about", "File this one away"]
        ]

        let options = fallbacks[category.lowercased()] ?? fallbacks["general"]!
        return options.randomElement()!
    }

    // Dave Pell-style intros for fallback/backward compatibility
    // No trailing punctuation - formatting added in output
    private func getContextualIntro(for category: String, itemNumber: Int) -> String {
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

    /// Generate creative newsletter title and intro paragraph using AI
    /// Inspired by Dave Pell's NextDraft style - clever titles and personality-driven intros
    private func generateNewsletterTitleAndIntro(articles: [Article]) async -> (title: String, intro: String) {
        // Try using AIService's Apple Intelligence integration if available (iOS 26+)
        if #available(iOS 26.0, *) {
            if let (aiTitle, aiIntro) = await AIService.shared.generateNewsletterHeader(articles: articles) {
                return (aiTitle, aiIntro)
            }
        }

        // Fallback to static title and intro
        let titles = [
            "Today's Brief",
            "The Daily Digest",
            "Your Morning Read",
            "What You Need to Know",
            "The Rundown"
        ]

        let intros = [
            "Here's what you need to know from your feeds today. I've curated the highlights with a bit of context.",
            "Your daily dose of the internet, distilled and served with commentary.",
            "The news that matters, minus the noise. Let's dive in.",
            "Another day, another batch of stories worth your time. Here's what's happening."
        ]

        return (titles.randomElement()!, intros.randomElement()!)
    }

    enum AIError: LocalizedError {
        case noArticles
        case notAvailable
        case generationFailed

        var errorDescription: String? {
            switch self {
            case .noArticles:
                return "No articles to summarize"
            case .notAvailable:
                return "On-device AI not available on this device"
            case .generationFailed:
                return "Failed to generate summary"
            }
        }
    }
}
