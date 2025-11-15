//
//  RedditCommentService.swift
//  Today
//
//  Service for fetching and parsing Reddit comments from JSON API
//

import Foundation

struct RedditComment: Identifiable {
    let id: String
    let author: String
    let body: String
    let bodyHtml: String? // Reddit's pre-rendered HTML (includes images, links, formatting)
    let score: Int
    let createdUtc: Date
    let depth: Int
    var replies: [RedditComment]

    var timeAgo: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: createdUtc, relativeTo: Date())
    }
}

class RedditCommentService {
    static let shared = RedditCommentService()

    private init() {}

    /// Fetches and parses comments from a Reddit post
    /// - Parameter url: The Reddit post URL (will be converted to JSON endpoint)
    /// - Returns: Array of top-level comments with nested replies
    func fetchComments(from url: String) async throws -> [RedditComment] {
        // Convert URL to JSON endpoint
        let jsonURL = url.hasSuffix("/") ? url + ".json" : url + ".json"

        guard let requestURL = URL(string: jsonURL) else {
            throw RedditError.invalidURL
        }

        // Reddit requires a User-Agent header
        var request = URLRequest(url: requestURL)
        request.setValue("ios:com.today.app:v1.0 (by /u/TodayApp)", forHTTPHeaderField: "User-Agent")

        let (data, _) = try await URLSession.shared.data(for: request)

        // Parse the JSON response
        return try parseComments(from: data)
    }

    private func parseComments(from data: Data) throws -> [RedditComment] {
        guard let jsonArray = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              jsonArray.count >= 2 else {
            throw RedditError.parsingFailed
        }

        let commentListing = jsonArray[1] as [String: Any]
        guard let commentData = commentListing["data"] as? [String: Any],
              let children = commentData["children"] as? [[String: Any]] else {
            throw RedditError.parsingFailed
        }

        var comments: [RedditComment] = []

        for child in children {
            if let comment = parseComment(from: child, depth: 0) {
                comments.append(comment)
            }
        }

        return comments
    }

    private func parseComment(from json: [String: Any], depth: Int) -> RedditComment? {
        guard let kind = json["kind"] as? String,
              kind == "t1", // t1 is a comment, t3 is a post
              let data = json["data"] as? [String: Any],
              let id = data["id"] as? String,
              let author = data["author"] as? String,
              let body = data["body"] as? String else {
            return nil
        }

        // Use body_html if available (includes images and formatting), fallback to body
        let bodyHtml = data["body_html"] as? String
        let score = data["score"] as? Int ?? 0
        let createdUtc = data["created_utc"] as? Double ?? 0
        let createdDate = Date(timeIntervalSince1970: createdUtc)

        // Parse nested replies
        var replies: [RedditComment] = []
        if let repliesData = data["replies"] as? [String: Any],
           let repliesListing = repliesData["data"] as? [String: Any],
           let repliesChildren = repliesListing["children"] as? [[String: Any]] {
            for replyJson in repliesChildren {
                if let reply = parseComment(from: replyJson, depth: depth + 1) {
                    replies.append(reply)
                }
            }
        }

        return RedditComment(
            id: id,
            author: author,
            body: body,
            bodyHtml: bodyHtml,
            score: score,
            createdUtc: createdDate,
            depth: depth,
            replies: replies
        )
    }

    enum RedditError: LocalizedError {
        case invalidURL
        case parsingFailed

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "Invalid Reddit URL"
            case .parsingFailed:
                return "Failed to parse Reddit comments"
            }
        }
    }
}
