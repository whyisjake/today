import Foundation
import SwiftData

/// Caches preloaded Reddit post data for smooth train-car paging.
/// Used by ArticlePagerView to prefetch adjacent Reddit posts.
@MainActor
class RedditPostCache {
    static let shared = RedditPostCache()

    struct CachedPost {
        let post: ParsedRedditPost
        let comments: [RedditComment]
    }

    private var cache: [PersistentIdentifier: CachedPost] = [:]
    private var inFlightTasks: [PersistentIdentifier: Task<Void, Never>] = [:]

    private init() {}

    /// Get cached data for an article, if available.
    func get(for articleID: PersistentIdentifier) -> CachedPost? {
        cache[articleID]
    }

    /// Preload Reddit post data for an article. No-op if already cached or in flight.
    func preload(article: Article) {
        let articleID = article.persistentModelID
        guard cache[articleID] == nil, inFlightTasks[articleID] == nil else { return }
        guard article.isRedditPost, let commentsUrl = article.redditCommentsUrl else { return }

        inFlightTasks[articleID] = Task {
            do {
                let result = try await Self.fetchRedditPost(commentsUrl: commentsUrl)
                cache[articleID] = result
            } catch {
                // Preload failure is non-fatal — view will fetch on its own
            }
            inFlightTasks[articleID] = nil
        }
    }

    /// Evict entries not in the given set of article IDs.
    func evict(keeping articleIDs: Set<PersistentIdentifier>) {
        for key in cache.keys where !articleIDs.contains(key) {
            cache.removeValue(forKey: key)
        }
        for (key, task) in inFlightTasks where !articleIDs.contains(key) {
            task.cancel()
            inFlightTasks.removeValue(forKey: key)
        }
    }

    /// Shared fetch logic — same as RedditPostView.loadPost() but static.
    static func fetchRedditPost(commentsUrl: String) async throws -> CachedPost {
        let jsonURL = commentsUrl.hasSuffix("/") ? commentsUrl + ".json" : commentsUrl + ".json"
        guard let requestURL = URL(string: jsonURL) else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: requestURL)
        request.setValue("ios:com.today.app:v1.0 (by /u/TodayApp)", forHTTPHeaderField: "User-Agent")

        let (data, _) = try await URLSession.shared.data(for: request)
        let parser = RedditJSONParser()
        let (post, comments) = try parser.parsePostWithComments(data: data)
        return CachedPost(post: post, comments: comments)
    }
}
