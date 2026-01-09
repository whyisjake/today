//
//  Article.swift
//  Today
//
//  Article model for storing RSS feed items
//

import Foundation
import SwiftData

@Model
final class Article {
    var title: String
    var link: String
    var articleDescription: String?
    var plainTextDescription: String? // Cached plain text version for list display
    var content: String?
    var contentEncoded: String? // Full content from content:encoded
    var imageUrl: String? // Featured image URL
    var publishedDate: Date
    var author: String?
    var guid: String // Unique identifier from RSS feed
    var isRead: Bool
    var isFavorite: Bool
    var aiSummary: String?
    
    // Reddit-specific metadata
    var redditSubreddit: String? // e.g., "baseball"
    var redditCommentsUrl: String? // Direct link to Reddit comments
    var redditPostId: String? // Reddit post ID (e.g., "t3_abc123")
    
    // Podcast/audio enclosure metadata
    var audioUrl: String? // URL to audio file (e.g., MP3)
    var audioDuration: TimeInterval? // Duration in seconds
    var audioType: String? // MIME type (e.g., "audio/mpeg")

    var feed: Feed?

    // Podcast download tracking
    var podcastDownload: PodcastDownload?

    init(title: String, link: String, articleDescription: String? = nil, content: String? = nil, contentEncoded: String? = nil, imageUrl: String? = nil, publishedDate: Date, author: String? = nil, guid: String, feed: Feed? = nil, redditSubreddit: String? = nil, redditCommentsUrl: String? = nil, redditPostId: String? = nil, audioUrl: String? = nil, audioDuration: TimeInterval? = nil, audioType: String? = nil) {
        self.title = title
        self.link = link
        self.articleDescription = articleDescription
        // Pre-compute plain text version once for performance
        self.plainTextDescription = articleDescription?.htmlToPlainText
        self.content = content
        self.contentEncoded = contentEncoded
        self.imageUrl = imageUrl
        self.publishedDate = publishedDate
        self.author = author
        self.guid = guid
        self.isRead = false
        self.isFavorite = false
        self.aiSummary = nil
        self.redditSubreddit = redditSubreddit
        self.redditCommentsUrl = redditCommentsUrl
        self.redditPostId = redditPostId
        self.audioUrl = audioUrl
        self.audioDuration = audioDuration
        self.audioType = audioType
        self.feed = feed
    }

    /// The article's link as a URL, or nil if the link is empty or invalid
    var articleURL: URL? {
        guard !link.isEmpty else { return nil }
        return URL(string: link)
    }

    /// Returns true if the article has minimal content (short summary only)
    /// These articles should open directly in web view for full content
    var hasMinimalContent: Bool {
        // If we have contentEncoded or substantial content, it's not minimal
        if let encoded = contentEncoded?.htmlToPlainText, !encoded.isEmpty, encoded.count > 300 {
            return false
        }

        if let fullContent = content?.htmlToPlainText, !fullContent.isEmpty, fullContent.count > 300 {
            return false
        }

        // If we only have description and it's short, or no content at all, it's minimal
        if contentEncoded == nil && content == nil {
            return true
        }

        // Check if total available content is less than 300 characters
        let totalContent = [contentEncoded, content, articleDescription]
            .compactMap { $0?.htmlToPlainText }
            .joined()

        return totalContent.count < 300
    }

    /// Returns true if the article is from a Reddit RSS feed
    var isRedditPost: Bool {
        return redditSubreddit != nil || redditCommentsUrl != nil
    }
    
    /// Returns true if the article has an audio enclosure (podcast)
    var hasPodcastAudio: Bool {
        return audioUrl != nil
    }
}
