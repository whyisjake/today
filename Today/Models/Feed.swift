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

    @Relationship(deleteRule: .cascade, inverse: \Article.feed)
    var articles: [Article]?

    init(title: String, url: String, feedDescription: String? = nil, category: String = "general", isActive: Bool = true) {
        self.title = title
        self.url = url
        self.feedDescription = feedDescription
        self.category = category
        self.isActive = isActive
        self.lastFetched = nil
        self.articles = []
    }
}
