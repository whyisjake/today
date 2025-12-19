//
//  Feed.swift
//  Today
//
//  RSS Feed model for storing feed subscriptions
//

import Foundation
import SwiftData

@Model
final class Feed {
    var title: String
    var url: String
    var feedDescription: String?
    var category: String // e.g., "work", "social", "tech"
    var lastFetched: Date?
    var isActive: Bool

    // Podcast download settings (nil = use global default)
    var downloadEpisodeLimit: Int?

    @Relationship(deleteRule: .cascade, inverse: \Article.feed)
    var articles: [Article]?

    init(title: String, url: String, feedDescription: String? = nil, category: String = "general", isActive: Bool = true) {
        self.title = title
        self.url = url
        self.feedDescription = feedDescription
        self.category = category
        self.isActive = isActive
        self.lastFetched = nil
        self.downloadEpisodeLimit = nil
        self.articles = []
    }

    /// Returns true if this feed has podcast episodes (any article with audio)
    var isPodcastFeed: Bool {
        return articles?.contains { $0.hasPodcastAudio } ?? false
    }
    
    /// Returns true if this feed is from Reddit
    var isRedditFeed: Bool {
        return url.contains("reddit.com/r/") && url.hasSuffix(".rss")
    }
    
    /// Extracts the subreddit name from the feed URL if it's a Reddit feed
    var redditSubreddit: String? {
        guard isRedditFeed else { return nil }
        let pattern = "reddit\\.com/r/([^/\\.]+)"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
              let match = regex.firstMatch(in: url, options: [], range: NSRange(location: 0, length: url.utf16.count)),
              match.numberOfRanges > 1 else {
            return nil
        }
        let range = match.range(at: 1)
        guard let swiftRange = Range(range, in: url) else { return nil }
        return String(url[swiftRange])
    }
}
