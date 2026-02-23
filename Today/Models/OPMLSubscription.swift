import Foundation
import SwiftData

/// Represents a subscription to a remote OPML URL.
/// The app periodically fetches the OPML and syncs the feed list to match it.
@Model
final class OPMLSubscription {
    var title: String
    var url: String
    var lastFetched: Date?
    var isActive: Bool
    var defaultCategory: String

    // HTTP caching headers for conditional GET
    var httpLastModified: String?
    var httpEtag: String?

    init(title: String, url: String, defaultCategory: String = "General", isActive: Bool = true) {
        self.title = title
        self.url = url
        self.defaultCategory = defaultCategory
        self.isActive = isActive
    }
}
