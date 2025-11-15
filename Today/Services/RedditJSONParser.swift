//
//  RedditJSONParser.swift
//  Today
//
//  Service for parsing Reddit JSON feeds and posts
//

import Foundation

class RedditJSONParser {

    /// Parse a subreddit JSON feed (list of posts)
    func parseSubredditFeed(data: Data) throws -> (feedTitle: String, feedDescription: String, articles: [ParsedRedditPost]) {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let data = json["data"] as? [String: Any],
              let children = data["children"] as? [[String: Any]] else {
            throw RedditError.parsingFailed
        }

        var posts: [ParsedRedditPost] = []
        var feedTitle = ""
        var subreddit = ""

        for child in children {
            if let post = parsePost(from: child) {
                posts.append(post)
                // Extract subreddit from first post if available
                if subreddit.isEmpty {
                    subreddit = post.subreddit
                    feedTitle = "r/\(post.subreddit)"
                }
            }
        }

        return (feedTitle, "Reddit feed for r/\(subreddit)", posts)
    }

    /// Parse a single Reddit post JSON (includes comments)
    func parsePostWithComments(data: Data) throws -> (post: ParsedRedditPost, comments: [RedditComment]) {
        guard let jsonArray = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              jsonArray.count >= 2 else {
            throw RedditError.parsingFailed
        }

        // First element is the post
        let postListing = jsonArray[0] as [String: Any]
        guard let postData = postListing["data"] as? [String: Any],
              let postChildren = postData["children"] as? [[String: Any]],
              let firstPost = postChildren.first,
              let post = parsePost(from: firstPost) else {
            throw RedditError.parsingFailed
        }

        // Second element is comments
        let commentListing = jsonArray[1] as [String: Any]
        guard let commentData = commentListing["data"] as? [String: Any],
              let commentChildren = commentData["children"] as? [[String: Any]] else {
            return (post, []) // Return post with no comments
        }

        var comments: [RedditComment] = []
        for child in commentChildren {
            if let comment = parseComment(from: child, depth: 0) {
                comments.append(comment)
            }
        }

        return (post, comments)
    }

    private func parsePost(from json: [String: Any]) -> ParsedRedditPost? {
        guard let kind = json["kind"] as? String,
              kind == "t3", // t3 is a post
              let data = json["data"] as? [String: Any],
              let id = data["id"] as? String,
              let title = data["title"] as? String,
              let author = data["author"] as? String,
              let subreddit = data["subreddit"] as? String,
              let permalink = data["permalink"] as? String,
              let createdUtc = data["created_utc"] as? Double else {
            return nil
        }

        let url = data["url"] as? String ?? ""
        let selftext = data["selftext"] as? String // Post body (for text posts)
        let selftextHtml = data["selftext_html"] as? String // HTML version (includes images, formatting)
        let score = data["score"] as? Int ?? 0
        let numComments = data["num_comments"] as? Int ?? 0

        // Extract thumbnail/preview image
        var imageUrl: String? = nil
        if let thumbnail = data["thumbnail"] as? String,
           thumbnail.hasPrefix("http") {
            imageUrl = thumbnail
        } else if let preview = data["preview"] as? [String: Any],
                  let images = preview["images"] as? [[String: Any]],
                  let firstImage = images.first,
                  let source = firstImage["source"] as? [String: Any],
                  let sourceUrl = source["url"] as? String {
            // Decode HTML entities in URL
            imageUrl = sourceUrl.replacingOccurrences(of: "&amp;", with: "&")
        }

        let postUrl = "https://www.reddit.com\(permalink)"
        let commentsUrl = postUrl

        return ParsedRedditPost(
            id: id,
            title: title,
            author: author,
            subreddit: subreddit,
            url: url,
            permalink: postUrl,
            commentsUrl: commentsUrl,
            selftext: selftext,
            selftextHtml: selftextHtml,
            score: score,
            numComments: numComments,
            createdUtc: Date(timeIntervalSince1970: createdUtc),
            imageUrl: imageUrl
        )
    }

    private func parseComment(from json: [String: Any], depth: Int) -> RedditComment? {
        guard let kind = json["kind"] as? String,
              kind == "t1", // t1 is a comment
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
        case parsingFailed

        var errorDescription: String? {
            switch self {
            case .parsingFailed:
                return "Failed to parse Reddit JSON"
            }
        }
    }
}

// MARK: - Parsed Reddit Post Model

struct ParsedRedditPost {
    let id: String
    let title: String
    let author: String
    let subreddit: String
    let url: String // Link URL (external or reddit URL)
    let permalink: String // Reddit post URL
    let commentsUrl: String // Same as permalink
    let selftext: String? // Post body (text posts) - plain text
    let selftextHtml: String? // Post body (text posts) - HTML with images, formatting
    let score: Int
    let numComments: Int
    let createdUtc: Date
    let imageUrl: String?

    /// Convert to RSSParser.ParsedArticle format for compatibility
    func toArticle() -> RSSParser.ParsedArticle {
        // For link posts, use the external URL
        // For text posts, use the Reddit permalink
        let linkUrl = selftext?.isEmpty == false ? permalink : url

        return RSSParser.ParsedArticle(
            title: title,
            link: linkUrl,
            description: selftext,
            content: selftext,
            contentEncoded: nil,
            imageUrl: imageUrl,
            publishedDate: createdUtc,
            author: "/u/\(author)",
            guid: "t3_\(id)",
            redditSubreddit: subreddit,
            redditCommentsUrl: commentsUrl,
            redditPostId: "t3_\(id)"
        )
    }
}

// MARK: - String Extension for HTML Decoding

extension String {
    func decodeHTMLEntities() -> String {
        var result = self

        // Decode common HTML entities
        result = result.replacingOccurrences(of: "&lt;", with: "<")
        result = result.replacingOccurrences(of: "&gt;", with: ">")
        result = result.replacingOccurrences(of: "&amp;", with: "&")
        result = result.replacingOccurrences(of: "&quot;", with: "\"")
        result = result.replacingOccurrences(of: "&#39;", with: "'")
        result = result.replacingOccurrences(of: "&nbsp;", with: " ")

        return result
    }
}
