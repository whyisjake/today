//
//  RSSParser.swift
//  Today
//
//  Service for fetching and parsing RSS feeds
//

import Foundation

class RSSParser: NSObject, XMLParserDelegate {
    private var currentElement = ""
    private var currentTitle = ""
    private var currentLink = ""
    private var currentDescription = ""
    private var currentContent = ""
    private var currentContentEncoded = ""
    private var currentImageUrl = ""
    private var currentPubDate = ""
    private var currentAuthor = ""
    private var currentGuid = ""
    private var insideItem = false
    private var feedTitleParsed = false

    private(set) var articles: [ParsedArticle] = []
    private(set) var feedTitle = ""
    private(set) var feedDescription = ""

    struct ParsedArticle {
        let title: String
        let link: String
        let description: String?
        let content: String?
        let contentEncoded: String?
        let imageUrl: String?
        let publishedDate: Date?
        let author: String?
        let guid: String
    }

    func parse(data: Data) -> Bool {
        let parser = XMLParser(data: data)
        parser.delegate = self
        return parser.parse()
    }

    // MARK: - XMLParserDelegate

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        currentElement = elementName

        if elementName == "item" {
            insideItem = true
            currentTitle = ""
            currentLink = ""
            currentDescription = ""
            currentContent = ""
            currentContentEncoded = ""
            currentImageUrl = ""
            currentPubDate = ""
            currentAuthor = ""
            currentGuid = ""
        }

        // Check for image in attributes (media:content, enclosure, etc.)
        if insideItem {
            // Handle <enclosure> tag (common for podcasts and images)
            if elementName == "enclosure", let url = attributeDict["url"], let type = attributeDict["type"], type.contains("image") {
                currentImageUrl = url
            }

            // Handle <media:content> tag
            if elementName == "media:content" || elementName == "content", let url = attributeDict["url"] {
                if currentImageUrl.isEmpty { // Only set if we don't already have an image
                    currentImageUrl = url
                }
            }

            // Handle <media:thumbnail>
            if elementName == "media:thumbnail" || elementName == "thumbnail", let url = attributeDict["url"] {
                if currentImageUrl.isEmpty {
                    currentImageUrl = url
                }
            }
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if insideItem {
            switch currentElement {
            case "title":
                currentTitle += trimmed
            case "link":
                currentLink += trimmed
            case "description":
                currentDescription += trimmed
            case "content":
                currentContent += trimmed
            case "content:encoded", "encoded":
                currentContentEncoded += trimmed
            case "pubDate":
                currentPubDate += trimmed
            case "author", "dc:creator":
                currentAuthor += trimmed
            case "guid":
                currentGuid += trimmed
            default:
                break
            }
        } else {
            // Feed-level metadata
            switch currentElement {
            case "title":
                if !feedTitleParsed {
                    feedTitle += trimmed
                }
            case "description":
                feedDescription += trimmed
            default:
                break
            }
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "item" {
            insideItem = false

            // Use link as guid if guid is not provided
            let finalGuid = currentGuid.isEmpty ? currentLink : currentGuid

            // If no explicit image found, try to extract from HTML content
            var finalImageUrl = currentImageUrl
            if finalImageUrl.isEmpty {
                // Try content:encoded first, then content, then description
                if !currentContentEncoded.isEmpty {
                    finalImageUrl = extractFirstImageUrl(from: currentContentEncoded)
                } else if !currentContent.isEmpty {
                    finalImageUrl = extractFirstImageUrl(from: currentContent)
                } else if !currentDescription.isEmpty {
                    finalImageUrl = extractFirstImageUrl(from: currentDescription)
                }
            }

            let article = ParsedArticle(
                title: currentTitle,
                link: currentLink,
                description: currentDescription.isEmpty ? nil : currentDescription,
                content: currentContent.isEmpty ? nil : currentContent,
                contentEncoded: currentContentEncoded.isEmpty ? nil : currentContentEncoded,
                imageUrl: finalImageUrl.isEmpty ? nil : finalImageUrl,
                publishedDate: parseDate(currentPubDate),
                author: currentAuthor.isEmpty ? nil : currentAuthor,
                guid: finalGuid
            )

            articles.append(article)
        } else if elementName == "title" && !insideItem {
            // Mark feed title as parsed when we finish the feed-level title element
            feedTitleParsed = true
        }
    }

    /// Extract the first image URL from HTML content
    private func extractFirstImageUrl(from html: String) -> String {
        // Look for <img src="..." patterns
        let pattern = "<img[^>]*src=[\"']([^\"']+)[\"'][^>]*>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return ""
        }

        let nsString = html as NSString
        let results = regex.matches(in: html, options: [], range: NSRange(location: 0, length: nsString.length))

        if let match = results.first, match.numberOfRanges > 1 {
            let range = match.range(at: 1)
            return nsString.substring(with: range)
        }

        return ""
    }

    private func parseDate(_ dateString: String) -> Date? {
        let dateFormatters = [
            // RFC 822 format (common in RSS)
            { () -> DateFormatter in
                let formatter = DateFormatter()
                formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
                formatter.locale = Locale(identifier: "en_US_POSIX")
                return formatter
            }(),
            // ISO 8601 format (Atom feeds)
            { () -> DateFormatter in
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
                formatter.locale = Locale(identifier: "en_US_POSIX")
                return formatter
            }()
        ]

        for formatter in dateFormatters {
            if let date = formatter.date(from: dateString) {
                return date
            }
        }

        return nil
    }
}

// MARK: - Feed Fetching Service

class RSSFeedService {
    static let shared = RSSFeedService()

    private init() {}

    func fetchFeed(url: String) async throws -> (feedTitle: String, feedDescription: String, articles: [RSSParser.ParsedArticle]) {
        guard let feedURL = URL(string: url) else {
            throw RSSError.invalidURL
        }

        let (data, _) = try await URLSession.shared.data(from: feedURL)

        let parser = RSSParser()
        guard parser.parse(data: data) else {
            throw RSSError.parsingFailed
        }

        return (parser.feedTitle, parser.feedDescription, parser.articles)
    }

    enum RSSError: LocalizedError {
        case invalidURL
        case parsingFailed

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "Invalid RSS feed URL"
            case .parsingFailed:
                return "Failed to parse RSS feed"
            }
        }
    }
}
