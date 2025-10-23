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

    /// Generate a newsletter-style summary using on-device AI
    func generateNewsletterSummary(articles: [Article]) async throws -> (String, [Article]?) {
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

        var newsletter = "📰 **Today's Brief**\n\n"
        newsletter += "Here's what you need to know from your feeds today.\n\n"

        var featuredArticles: [Article] = []
        var itemNumber = 1

        // Process each article with on-device summarization
        for article in sortedArticles {
            newsletter += "**\(itemNumber).** "

            // Use NaturalLanguage to generate summary
            if let summary = await generateSmartSummary(for: article) {
                newsletter += summary
            } else {
                // Fallback to article title
                newsletter += "**\(article.title)**"
            }

            newsletter += "\n\n"
            featuredArticles.append(article)
            itemNumber += 1
        }

        newsletter += "\n---\n\n"
        newsletter += "That's it for today! Tap any article below to read more. ✌️"

        return (newsletter, featuredArticles)
    }

    /// Generate a smart summary for an article using Apple's NaturalLanguage
    private func generateSmartSummary(for article: Article) async -> String? {
        // Combine article text for analysis
        var fullText = article.title

        // Get the content, preferring content:encoded > content > description
        if let contentEncoded = article.contentEncoded?.htmlToPlainText {
            fullText = article.title + ". " + contentEncoded
        } else if let content = article.content?.htmlToPlainText {
            fullText = article.title + ". " + content
        } else if let description = article.articleDescription?.htmlToPlainText {
            fullText = article.title + ". " + description
        }

        // Extract key themes and important sentences
        let summary = extractKeyInformation(from: fullText, title: article.title)

        let category = article.feed?.category ?? "general"
        let intro = getContextualIntro(for: category)

        return "\(intro) **\(article.title)** — \(summary)"
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

        // Get top 2 most important sentences
        let topSentences = scoredSentences
            .sorted { $0.score > $1.score }
            .prefix(2)
            .map { $0.sentence }

        // Combine and format
        let summary = topSentences.joined(separator: " ")
        return String(summary.prefix(200)) + (summary.count > 200 ? "..." : "")
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

    private func getContextualIntro(for category: String) -> String {
        let intros: [String: String] = [
            "tech": "In tech news,",
            "news": "Worth knowing:",
            "work": "For your career,",
            "social": "Trending now:",
            "general": "Interesting read:"
        ]
        return intros[category.lowercased()] ?? intros["general"]!
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
