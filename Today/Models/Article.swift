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
    var content: String?
    var contentEncoded: String? // Full content from content:encoded
    var imageUrl: String? // Featured image URL
    var publishedDate: Date
    var author: String?
    var guid: String // Unique identifier from RSS feed
    var isRead: Bool
    var isFavorite: Bool
    var aiSummary: String?

    var feed: Feed?

    init(title: String, link: String, articleDescription: String? = nil, content: String? = nil, contentEncoded: String? = nil, imageUrl: String? = nil, publishedDate: Date, author: String? = nil, guid: String, feed: Feed? = nil) {
        self.title = title
        self.link = link
        self.articleDescription = articleDescription
        self.content = content
        self.contentEncoded = contentEncoded
        self.imageUrl = imageUrl
        self.publishedDate = publishedDate
        self.author = author
        self.guid = guid
        self.isRead = false
        self.isFavorite = false
        self.aiSummary = nil
        self.feed = feed
    }
}
