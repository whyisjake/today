//
//  JSONFeedParser.swift
//  Today
//
//  Service for parsing JSON Feed format (https://www.jsonfeed.org/version/1.1/)
//

import Foundation

// MARK: - JSON Feed Parser

class JSONFeedParser {
    
    private(set) var articles: [RSSParser.ParsedArticle] = []
    private(set) var feedTitle = ""
    private(set) var feedDescription = ""
    
    /// Parse JSON Feed data
    /// Supports both JSON Feed 1.0 and 1.1
    func parse(data: Data) throws -> Bool {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }
        
        // Validate it's a JSON Feed by checking for version field
        guard let version = json["version"] as? String,
              version.contains("jsonfeed.org") else {
            return false
        }
        
        // Parse feed metadata
        feedTitle = normalizeWhitespace(json["title"] as? String ?? "")
        feedDescription = normalizeWhitespace(json["description"] as? String ?? "")
        
        // Parse items
        guard let items = json["items"] as? [[String: Any]] else {
            return true // Valid feed with no items
        }
        
        for item in items {
            if let article = parseItem(item) {
                articles.append(article)
            }
        }
        
        return true
    }
    
    private func parseItem(_ item: [String: Any]) -> RSSParser.ParsedArticle? {
        // id is required in JSON Feed spec
        guard let id = item["id"] as? String else {
            // Fallback to url if id is missing (some feeds do this)
            guard let url = item["url"] as? String else {
                return nil
            }
            return parseItemWithId(item, id: url)
        }
        
        return parseItemWithId(item, id: id)
    }
    
    private func parseItemWithId(_ item: [String: Any], id: String) -> RSSParser.ParsedArticle {
        let title = normalizeWhitespace(item["title"] as? String ?? "")
        let url = item["url"] as? String ?? ""
        let externalUrl = item["external_url"] as? String
        
        // Use external_url if available, otherwise use url
        let link = externalUrl ?? url
        
        // Content: prefer content_html, fallback to content_text
        let contentHtml = item["content_html"] as? String
        let contentText = item["content_text"] as? String
        
        // Summary is typically shorter than content
        let summary = item["summary"] as? String
        
        // Description uses summary if available, otherwise a truncated content_text
        var description: String? = nil
        if let summaryText = summary, !summaryText.isEmpty {
            description = normalizeWhitespace(summaryText)
        } else if let text = contentText, !text.isEmpty {
            // Truncate to reasonable description length
            let truncated = String(text.prefix(500))
            description = normalizeWhitespace(truncated)
        }
        
        // Parse date
        var publishedDate: Date? = nil
        if let datePublished = item["date_published"] as? String {
            publishedDate = parseDate(datePublished)
        } else if let dateModified = item["date_modified"] as? String {
            publishedDate = parseDate(dateModified)
        }
        
        // Parse author(s)
        var author: String? = nil
        if let authors = item["authors"] as? [[String: Any]], let firstAuthor = authors.first {
            author = firstAuthor["name"] as? String
        } else if let authorDict = item["author"] as? [String: Any] {
            // JSON Feed 1.0 used singular "author"
            author = authorDict["name"] as? String
        }
        
        // Parse image
        var imageUrl: String? = nil
        if let image = item["image"] as? String {
            imageUrl = image
        } else if let bannerImage = item["banner_image"] as? String {
            imageUrl = bannerImage
        } else if let contentHtml = contentHtml {
            // Extract image from HTML content
            imageUrl = extractFirstImageUrl(from: contentHtml)
        }
        
        // Process content
        var processedContent: String? = nil
        var processedContentEncoded: String? = nil
        
        if let html = contentHtml, !html.isEmpty {
            processedContentEncoded = decodeHTMLEntities(html).texturize()
        }
        
        if let text = contentText, !text.isEmpty {
            processedContent = normalizeWhitespace(text).texturize()
        }
        
        return RSSParser.ParsedArticle(
            title: decodeHTMLEntities(title).texturize(),
            link: link,
            description: description != nil ? decodeHTMLEntities(description!).texturize() : nil,
            content: processedContent,
            contentEncoded: processedContentEncoded,
            imageUrl: imageUrl,
            publishedDate: publishedDate,
            author: author != nil ? normalizeWhitespace(author!) : nil,
            guid: id,
            redditSubreddit: nil,
            redditCommentsUrl: nil,
            redditPostId: nil
        )
    }
    
    // MARK: - Helper Methods
    
    private func normalizeWhitespace(_ text: String) -> String {
        var normalized = text.replacingOccurrences(of: "\u{00A0}", with: " ")
        normalized = normalized.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return normalized.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func decodeHTMLEntities(_ text: String) -> String {
        var result = text
        
        // Decode numeric entities (&#xxx;)
        let numericEntityPattern = "&#(\\d+);"
        if let regex = try? NSRegularExpression(pattern: numericEntityPattern, options: []) {
            let nsString = result as NSString
            let matches = regex.matches(in: result, options: [], range: NSRange(location: 0, length: nsString.length))
            
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
        result = result.replacingOccurrences(of: "&rdquo;", with: "\u{201D}")
        result = result.replacingOccurrences(of: "&ldquo;", with: "\u{201C}")
        result = result.replacingOccurrences(of: "&rsquo;", with: "\u{2019}")
        result = result.replacingOccurrences(of: "&lsquo;", with: "\u{2018}")
        result = result.replacingOccurrences(of: "&mdash;", with: "\u{2014}")
        result = result.replacingOccurrences(of: "&ndash;", with: "\u{2013}")
        result = result.replacingOccurrences(of: "&hellip;", with: "\u{2026}")
        
        return result
    }
    
    private func extractFirstImageUrl(from html: String) -> String? {
        let pattern = "<img[^>]*src=[\"']([^\"']+)[\"'][^>]*>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        
        let nsString = html as NSString
        let results = regex.matches(in: html, options: [], range: NSRange(location: 0, length: nsString.length))
        
        if let match = results.first, match.numberOfRanges > 1 {
            let range = match.range(at: 1)
            return nsString.substring(with: range)
        }
        
        return nil
    }
    
    private func parseDate(_ dateString: String) -> Date? {
        // JSON Feed uses ISO 8601 format
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
        
        // Try additional formats
        let dateFormatters = [
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
            }(),
            { () -> DateFormatter in
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssXXXXX"
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
    
    enum JSONFeedError: LocalizedError {
        case invalidFormat
        case parsingFailed
        
        var errorDescription: String? {
            switch self {
            case .invalidFormat:
                return "Invalid JSON Feed format"
            case .parsingFailed:
                return "Failed to parse JSON Feed"
            }
        }
    }
}

// MARK: - JSON Feed Service

class JSONFeedService {
    static let shared = JSONFeedService()
    
    private init() {}
    
    func fetchFeed(url: String) async throws -> (feedTitle: String, feedDescription: String, articles: [RSSParser.ParsedArticle]) {
        guard let feedURL = URL(string: url) else {
            throw JSONFeedParser.JSONFeedError.invalidFormat
        }
        
        let (data, _) = try await URLSession.shared.data(from: feedURL)
        
        let parser = JSONFeedParser()
        guard try parser.parse(data: data) else {
            throw JSONFeedParser.JSONFeedError.parsingFailed
        }
        
        return (parser.feedTitle, parser.feedDescription, parser.articles)
    }
}
