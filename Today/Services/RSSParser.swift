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
    private var currentAudioUrl = ""
    private var currentAudioDuration: TimeInterval?
    private var currentAudioDurationString = ""
    private var currentAudioType = ""
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
        
        // Reddit-specific fields
        let redditSubreddit: String?
        let redditCommentsUrl: String?
        let redditPostId: String?
        
        // Podcast/audio enclosure fields
        let audioUrl: String?
        let audioDuration: TimeInterval?
        let audioType: String?
    }

    func parse(data: Data) -> Bool {
        let parser = XMLParser(data: data)
        parser.delegate = self
        let success = parser.parse()

        // Normalize feed-level fields after parsing completes
        if success {
            feedTitle = normalizeWhitespace(feedTitle)
            feedDescription = normalizeWhitespace(feedDescription)
        }

        return success
    }

    // MARK: - XMLParserDelegate

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        currentElement = elementName

        // Support both RSS <item> and Atom <entry>
        if elementName == "item" || elementName == "entry" {
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
            currentAudioUrl = ""
            currentAudioDuration = nil
            currentAudioDurationString = ""
            currentAudioType = ""
        }

        // Handle Atom <link> tags which use attributes instead of text content
        if insideItem && elementName == "link" {
            // Atom feeds have: <link rel="alternate" type="text/html" href="..." />
            if let href = attributeDict["href"], let rel = attributeDict["rel"], rel == "alternate" {
                currentLink = href
            } else if let href = attributeDict["href"], attributeDict["rel"] == nil {
                // Some Atom feeds don't specify rel, just use href
                if currentLink.isEmpty {
                    currentLink = href
                }
            }
        }

        // Check for image in attributes (media:content, enclosure, etc.)
        if insideItem {
            // Handle <enclosure> tag (common for podcasts and images)
            if elementName == "enclosure", let url = attributeDict["url"], let type = attributeDict["type"] {
                if type.contains("audio") {
                    // Audio enclosure (podcast)
                    currentAudioUrl = url
                    currentAudioType = type
                    // Duration is parsed from itunes:duration element, not from length attribute
                } else if type.contains("image") {
                    currentImageUrl = url
                }
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
        // Don't trim whitespace here! XMLParser calls this method multiple times for text
        // containing HTML entities. Trimming would strip spaces around entities like &#8216;
        // We'll normalize whitespace later in the processing pipeline.
        //
        // Example: "<title>Biden &#8216;Dark Days&#8217; Trump</title>" triggers:
        //   1. foundCharacters("Biden ")
        //   2. foundCharacters("&#8216;")
        //   3. foundCharacters("Dark Days")
        //   4. foundCharacters("&#8217;")
        //   5. foundCharacters(" Trump")
        // If we trim each, we lose the spaces!

        if insideItem {
            switch currentElement {
            case "title":
                currentTitle += string
            case "link":
                // RSS feeds use text content for link, Atom uses attributes (handled in didStartElement)
                if currentLink.isEmpty {
                    currentLink += string
                }
            case "description", "summary": // Atom uses <summary>, RSS uses <description>
                currentDescription += string
            case "content":
                currentContent += string
            case "content:encoded", "encoded":
                currentContentEncoded += string
            case "pubDate", "published", "updated": // Atom uses <published> or <updated>
                if currentPubDate.isEmpty { // Prefer published over updated
                    currentPubDate += string
                }
            case "author", "dc:creator":
                currentAuthor += string
            case "name": // Atom feeds have <author><name>...</name></author>
                if !currentAuthor.isEmpty {
                    currentAuthor += " "
                }
                currentAuthor += string
            case "guid", "id": // Atom uses <id>
                currentGuid += string
            case "itunes:duration", "duration": // Podcast episode duration
                currentAudioDurationString += string
            default:
                break
            }
        } else {
            // Feed-level metadata
            switch currentElement {
            case "title":
                if !feedTitleParsed {
                    feedTitle += string
                }
            case "description", "subtitle": // Atom uses <subtitle>, RSS uses <description>
                feedDescription += string
            default:
                break
            }
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        // Support both RSS <item> and Atom <entry>
        if elementName == "item" || elementName == "entry" {
            insideItem = false

            // Normalize link and guid (trim whitespace that may have been accumulated from XML)
            currentLink = normalizeWhitespace(currentLink)
            currentGuid = normalizeWhitespace(currentGuid)

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

            // Debug: log title processing steps
            let normalizedTitle = normalizeWhitespace(currentTitle)
            let decodedTitle = decodeHTMLEntities(normalizedTitle)
            let processedTitle = decodedTitle.texturize()

            if currentTitle.contains("&#") || currentTitle.contains("Dark Days") {
                print("🔍 Title processing:")
                print("   Raw:        '\(currentTitle)'")
                print("   Normalized: '\(normalizedTitle)'")
                print("   Decoded:    '\(decodedTitle)'")
                print("   Texturized: '\(processedTitle)'")
            }
            let processedDescription = currentDescription.isEmpty ? nil : decodeHTMLEntities(normalizeWhitespace(currentDescription)).texturize()

            var processedContent: String? = nil
            if !currentContent.isEmpty {
                let decoded = decodeHTMLEntities(normalizeWhitespace(currentContent))
                print("🔍 Content before texturize (first 200 chars): '\(decoded.prefix(200))'")
                processedContent = decoded.texturize()
            }

            var processedContentEncoded: String? = nil
            if !currentContentEncoded.isEmpty {
                let decoded = decodeHTMLEntities(normalizeWhitespace(currentContentEncoded))
                print("🔍 ContentEncoded before texturize (first 200 chars): '\(decoded.prefix(200))'")
                processedContentEncoded = decoded.texturize()
            }

            // Extract Reddit metadata if this is a Reddit post
            let redditMetadata = extractRedditMetadata(from: processedContentEncoded ?? processedContent, link: currentLink)
            
            // Parse audio duration if available
            let audioDuration: TimeInterval? = currentAudioDurationString.isEmpty ? nil : parseDuration(currentAudioDurationString)

            let article = ParsedArticle(
                title: processedTitle,
                link: currentLink,
                description: processedDescription,
                content: processedContent,
                contentEncoded: processedContentEncoded,
                imageUrl: finalImageUrl.isEmpty ? nil : finalImageUrl,
                publishedDate: parseDate(currentPubDate),
                author: currentAuthor.isEmpty ? nil : normalizeWhitespace(currentAuthor),
                guid: finalGuid,
                redditSubreddit: redditMetadata.subreddit,
                redditCommentsUrl: redditMetadata.commentsUrl,
                redditPostId: redditMetadata.postId,
                audioUrl: currentAudioUrl.isEmpty ? nil : currentAudioUrl,
                audioDuration: audioDuration,
                audioType: currentAudioType.isEmpty ? nil : currentAudioType
            )

            articles.append(article)
        } else if elementName == "title" && !insideItem {
            // Mark feed title as parsed when we finish the feed-level title element
            feedTitleParsed = true
        }
    }

    /// Normalize whitespace in text - collapses multiple spaces/newlines into single space and trims
    private func normalizeWhitespace(_ text: String) -> String {
        // First, convert non-breaking spaces to regular spaces
        var normalized = text.replacingOccurrences(of: "\u{00A0}", with: " ")

        // Replace all sequences of whitespace (spaces, tabs, newlines) with a single space
        normalized = normalized.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return normalized.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Decode HTML entities (numeric and named) in text
    /// This is needed because XMLParser doesn't decode entities within CDATA sections
    private func decodeHTMLEntities(_ text: String) -> String {
        var result = text

        // Decode numeric entities (&#xxx;)
        let numericEntityPattern = "&#(\\d+);"
        if let regex = try? NSRegularExpression(pattern: numericEntityPattern, options: []) {
            let nsString = result as NSString
            let matches = regex.matches(in: result, options: [], range: NSRange(location: 0, length: nsString.length))

            // Process matches in reverse to avoid index shifting
            for match in matches.reversed() {
                if match.numberOfRanges == 2 {
                    let numberRange = match.range(at: 1)
                    if let numberString = nsString.substring(with: numberRange) as String?,
                       let codePoint = Int(numberString),
                       let scalar = UnicodeScalar(codePoint) {
                        let character = String(scalar)
                        let fullRange = match.range
                        result = (result as NSString).replacingCharacters(in: fullRange, with: character)
                    }
                }
            }
        }

        // Decode hexadecimal entities (&#xHHHH;)
        let hexEntityPattern = "&#[xX]([0-9A-Fa-f]+);"
        if let regex = try? NSRegularExpression(pattern: hexEntityPattern, options: []) {
            let nsString = result as NSString
            let matches = regex.matches(in: result, options: [], range: NSRange(location: 0, length: nsString.length))

            // Process matches in reverse to avoid index shifting
            for match in matches.reversed() {
                if match.numberOfRanges == 2 {
                    let hexRange = match.range(at: 1)
                    if let hexString = nsString.substring(with: hexRange) as String?,
                       let codePoint = Int(hexString, radix: 16),
                       let scalar = UnicodeScalar(codePoint) {
                        let character = String(scalar)
                        let fullRange = match.range
                        result = (result as NSString).replacingCharacters(in: fullRange, with: character)
                    }
                }
            }
        }

        // Decode common named entities
        result = result.replacingOccurrences(of: "&nbsp;", with: " ")
        result = result.replacingOccurrences(of: "&amp;", with: "&")
        result = result.replacingOccurrences(of: "&lt;", with: "<")
        result = result.replacingOccurrences(of: "&gt;", with: ">")
        result = result.replacingOccurrences(of: "&quot;", with: "\"")
        result = result.replacingOccurrences(of: "&#39;", with: "'")
        result = result.replacingOccurrences(of: "&apos;", with: "'")
        result = result.replacingOccurrences(of: "&rdquo;", with: "\u{201D}") // Right double quote
        result = result.replacingOccurrences(of: "&ldquo;", with: "\u{201C}") // Left double quote
        result = result.replacingOccurrences(of: "&rsquo;", with: "\u{2019}") // Right single quote
        result = result.replacingOccurrences(of: "&lsquo;", with: "\u{2018}") // Left single quote
        result = result.replacingOccurrences(of: "&mdash;", with: "\u{2014}") // Em dash
        result = result.replacingOccurrences(of: "&ndash;", with: "\u{2013}") // En dash
        result = result.replacingOccurrences(of: "&hellip;", with: "\u{2026}") // Ellipsis

        return result
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
        // Try ISO 8601 decoder first (Atom feeds) - handles various formats
        if #available(iOS 15.0, *) {
            let isoFormatter = ISO8601DateFormatter()
            isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = isoFormatter.date(from: dateString) {
                return date
            }
            // Try without fractional seconds
            isoFormatter.formatOptions = [.withInternetDateTime]
            if let date = isoFormatter.date(from: dateString) {
                return date
            }
        }

        let dateFormatters = [
            // RFC 822 format with numeric timezone (common in RSS)
            { () -> DateFormatter in
                let formatter = DateFormatter()
                formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
                formatter.locale = Locale(identifier: "en_US_POSIX")
                return formatter
            }(),
            // RFC 822 format with timezone abbreviation (e.g., EDT, PST)
            { () -> DateFormatter in
                let formatter = DateFormatter()
                formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
                formatter.locale = Locale(identifier: "en_US_POSIX")
                return formatter
            }(),
            // ISO 8601 format variations (Atom feeds)
            { () -> DateFormatter in
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
                formatter.locale = Locale(identifier: "en_US_POSIX")
                return formatter
            }(),
            { () -> DateFormatter in
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
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
    
    /// Extract Reddit metadata from the article content and link
    private func extractRedditMetadata(from content: String?, link: String) -> (subreddit: String?, commentsUrl: String?, postId: String?) {
        var subreddit: String? = nil
        var commentsUrl: String? = nil
        var postId: String? = nil
        
        // Extract subreddit from link (e.g., https://www.reddit.com/r/baseball/comments/...)
        if link.contains("reddit.com/r/") {
            let pattern = "reddit\\.com/r/([^/]+)"
            if let regex = try? NSRegularExpression(pattern: pattern, options: []),
               let match = regex.firstMatch(in: link, options: [], range: NSRange(location: 0, length: link.utf16.count)),
               match.numberOfRanges > 1 {
                let range = match.range(at: 1)
                if let swiftRange = Range(range, in: link) {
                    subreddit = String(link[swiftRange])
                }
            }
            
            // The link itself is usually the comments URL for Reddit posts
            commentsUrl = link
        }
        
        // Extract post ID from content (e.g., "t3_abc123" in the id field) or link
        if let content = content {
            // Look for Reddit post ID pattern in content
            let idPattern = "t3_[a-zA-Z0-9]+"
            if let regex = try? NSRegularExpression(pattern: idPattern, options: []),
               let match = regex.firstMatch(in: content, options: [], range: NSRange(location: 0, length: content.utf16.count)) {
                let range = match.range
                if let swiftRange = Range(range, in: content) {
                    postId = String(content[swiftRange])
                }
            }
        }
        
        // Also try to extract post ID from link
        if postId == nil && link.contains("reddit.com") {
            let pattern = "comments/([a-zA-Z0-9]+)"
            if let regex = try? NSRegularExpression(pattern: pattern, options: []),
               let match = regex.firstMatch(in: link, options: [], range: NSRange(location: 0, length: link.utf16.count)),
               match.numberOfRanges > 1 {
                let range = match.range(at: 1)
                if let swiftRange = Range(range, in: link) {
                    postId = "t3_" + String(link[swiftRange])
                }
            }
        }
        
        return (subreddit, commentsUrl, postId)
    }
    
    /// Parse iTunes duration format into seconds
    /// Supports formats: "HH:MM:SS", "MM:SS", or just seconds "1234"
    private func parseDuration(_ durationString: String) -> TimeInterval? {
        let trimmed = durationString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        
        // If it's just a number (seconds), parse directly
        if let seconds = TimeInterval(trimmed) {
            return seconds
        }
        
        // Split by colons for HH:MM:SS or MM:SS format
        let components = trimmed.split(separator: ":")
        guard !components.isEmpty else { return nil }
        
        var totalSeconds: TimeInterval = 0
        
        if components.count == 3 {
            // HH:MM:SS format
            guard let hours = TimeInterval(components[0]),
                  let minutes = TimeInterval(components[1]),
                  let seconds = TimeInterval(components[2]) else {
                return nil
            }
            totalSeconds = hours * 3600 + minutes * 60 + seconds
        } else if components.count == 2 {
            // MM:SS format
            guard let minutes = TimeInterval(components[0]),
                  let seconds = TimeInterval(components[1]) else {
                return nil
            }
            totalSeconds = minutes * 60 + seconds
        } else if components.count == 1 {
            // Just seconds
            guard let seconds = TimeInterval(components[0]) else {
                return nil
            }
            totalSeconds = seconds
        }
        
        return totalSeconds
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
