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
    // Indexes backing the bounded read-path queries.
    //
    // - publishedDate: the sort and the date-window predicate on every article query
    // - guid: dedup lookup during sync insertion. NOT a uniqueness constraint — GUIDs are
    //   only unique within a feed, and two feeds may legitimately carry the same GUID
    // - (isRead, publishedDate) / (isFavorite, publishedDate): back the unread and favorite
    //   fetchCount aggregates, which are windowed by date and filtered by flag
    //
    // IMPORTANT: these are created on a *fresh* store only. SwiftData's lightweight
    // migration does not add indexes to a store that already exists, so upgrading users
    // keep an unindexed store until a versioned SchemaMigrationPlan is introduced.
    // Verified by inspecting sqlite_master: a fresh store has
    // Z_Article_SwiftDataIndexOnBinary* entries, a migrated one has only the
    // ZARTICLE_ZFEED_INDEX relationship index.
    //
    // The bounded queries are still a large win without them — they avoid materialising
    // every Article and faulting its feed relationship in Swift — so this is a
    // "less fast than it could be" gap, not a correctness or regression issue.
    #Index<Article>(
        [\.publishedDate],
        [\.guid],
        [\.isRead, \.publishedDate],
        [\.isFavorite, \.publishedDate]
    )

    var title: String
    var link: String
    var articleDescription: String?
    var plainTextDescription: String? // Cached plain text version for list display

    /// `hasMinimalContent` computed once at insert. Optional so articles written before this
    /// field existed read as nil and fall back to computing it. Its inputs (content,
    /// contentEncoded, articleDescription) do not change after insert.
    var isMinimalContentCached: Bool?
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

    init(title: String, link: String, articleDescription: String? = nil, content: String? = nil, contentEncoded: String? = nil, imageUrl: String? = nil, publishedDate: Date, author: String? = nil, guid: String, feed: Feed? = nil, redditSubreddit: String? = nil, redditCommentsUrl: String? = nil, redditPostId: String? = nil, audioUrl: String? = nil, audioDuration: TimeInterval? = nil, audioType: String? = nil) {
        self.title = title
        self.link = link
        self.articleDescription = articleDescription
        // Pre-compute the derived text fields once, so the row view never has to strip HTML
        // while scrolling.
        self.plainTextDescription = articleDescription?.htmlToPlainText
        self.isMinimalContentCached = Self.computeIsMinimalContent(
            contentEncoded: contentEncoded,
            content: content,
            articleDescription: articleDescription
        )
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
    ///
    /// Reads the value computed at insert time. Falls back to computing it for articles
    /// that predate `isMinimalContentCached`; `DatabaseMigration.backfillDerivedArticleFields`
    /// fills those in off the main actor.
    ///
    /// The fallback matters because this is read per visible row while scrolling, and
    /// computing it costs up to three `htmlToPlainText` passes — five regular expressions
    /// and a dozen string replacements each.
    var hasMinimalContent: Bool {
        if let cached = isMinimalContentCached { return cached }
        return Self.computeIsMinimalContent(
            contentEncoded: contentEncoded,
            content: content,
            articleDescription: articleDescription
        )
    }

    /// The classification itself, kept as a pure function so the initializer, the backfill,
    /// and the tests all agree by construction.
    ///
    /// Behaviour is deliberately unchanged from the original computed property, including
    /// the quirk that an article with no `content` and no `contentEncoded` is minimal
    /// regardless of how long its description is.
    nonisolated static func computeIsMinimalContent(
        contentEncoded: String?,
        content: String?,
        articleDescription: String?
    ) -> Bool {
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
