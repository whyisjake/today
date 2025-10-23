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
        let article: Article
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

        var newsletter = "📰 **Today's Brief**\n\n"
        newsletter += "Here's what you need to know from your feeds today.\n\n"

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

        newsletter += "That's it for today! ✌️"

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
        let intro = generateDynamicIntro(title: article.title, content: contentText, category: article.feed?.category ?? "general")

        // Format: Intro + Title (bold) + em dash + summary
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

    /// Generate dynamic, content-aware intro based on article analysis
    private func generateDynamicIntro(title: String, content: String, category: String) -> String {
        let combinedText = title + " " + content

        // Analyze sentiment and key themes using NLTagger
        let tagger = NLTagger(tagSchemes: [.nameType, .lexicalClass])
        tagger.string = combinedText

        var hasPersonName = false
        var hasPlaceName = false
        var hasOrganization = false
        var keyVerbs: [String] = []

        // Detect named entities
        tagger.enumerateTags(in: combinedText.startIndex..<combinedText.endIndex,
                            unit: .word,
                            scheme: .nameType) { tag, range in
            if let tag = tag {
                switch tag {
                case .personalName:
                    hasPersonName = true
                case .placeName:
                    hasPlaceName = true
                case .organizationName:
                    hasOrganization = true
                default:
                    break
                }
            }
            return true
        }

        // Detect action verbs to understand story type
        tagger.enumerateTags(in: title.startIndex..<title.endIndex,
                            unit: .word,
                            scheme: .lexicalClass) { tag, range in
            if tag == .verb {
                let verb = String(title[range]).lowercased()
                if !["is", "are", "was", "were", "be", "been", "being", "has", "have", "had"].contains(verb) {
                    keyVerbs.append(verb)
                }
            }
            return true
        }

        // Detect urgency/breaking news indicators
        let urgentWords = ["breaking", "urgent", "alert", "warning", "crisis", "emergency"]
        let isUrgent = urgentWords.contains { title.lowercased().contains($0) }

        // Detect controversial/debate topics
        let controversialWords = ["controversy", "debate", "battle", "clash", "dispute", "fight", "conflict"]
        let isControversial = controversialWords.contains { title.lowercased().contains($0) }

        // Detect announcement/launch
        let announcementWords = ["announces", "launches", "reveals", "unveils", "introduces"]
        let isAnnouncement = announcementWords.contains { title.lowercased().contains($0) }

        // Detect study/research
        let researchWords = ["study", "research", "report", "survey", "finds", "shows"]
        let isResearch = researchWords.contains { title.lowercased().contains($0) }

        // Generate contextual intro based on content analysis
        if isUrgent {
            return "Breaking:"
        } else if isAnnouncement {
            return "Just announced:"
        } else if isResearch {
            return "New findings:"
        } else if isControversial {
            return "Here we go again..."
        } else if hasPersonName && keyVerbs.contains(where: { ["says", "claims", "argues", "warns"].contains($0) }) {
            return "Quote of the day:"
        } else if hasPlaceName && hasPersonName {
            return "Making headlines:"
        } else if hasOrganization {
            return category == "tech" ? "From the tech world:" : "In the news:"
        } else if keyVerbs.contains(where: { ["plans", "proposes", "considering"].contains($0) }) {
            return "Looking ahead:"
        } else if keyVerbs.contains(where: { ["wins", "loses", "defeats", "beats"].contains($0) }) {
            return "The result:"
        } else {
            // Fallback to category-based intros with some variety
            let fallbacks: [String: [String]] = [
                "tech": ["In tech news,", "From Silicon Valley,", "Tech update:"],
                "news": ["Worth knowing:", "In case you missed it,", "Today's story:"],
                "work": ["Career news:", "From the workplace,", "Business update:"],
                "social": ["Trending now:", "What people are saying:", "Social update:"],
                "general": ["Interesting:", "Check this out:", "Worth a read:"]
            ]

            let options = fallbacks[category.lowercased()] ?? fallbacks["general"]!
            return options.randomElement()!
        }
    }

    // Keep old function for backward compatibility/fallback
    private func getContextualIntro(for category: String, itemNumber: Int) -> String {
        let intros: [String: [String]] = [
            "tech": [
                "In tech news,",
                "Silicon Valley strikes again:",
                "From the world of tech,",
                "Here's what's buzzing in tech:",
                "Tech news that matters:"
            ],
            "news": [
                "Making headlines:",
                "Worth knowing:",
                "In case you missed it,",
                "Here's what's happening:",
                "From the news desk:"
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
                "Check this out:"
            ]
        ]

        let categoryIntros = intros[category.lowercased()] ?? intros["general"]!
        let index = (itemNumber - 1) % categoryIntros.count
        return categoryIntros[index]
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
