//
//  RedditPostRSSParser.swift
//  Today
//
//  Parses a Reddit post's Atom feed (`<permalink>.rss`) into the post and its comments.
//

import Foundation

/// Parses `https://www.reddit.com/r/<sub>/comments/<id>/<slug>/.rss`.
///
/// This exists because Reddit now answers unauthenticated `.json` with 403 and an HTML block
/// page — the shutdown is deliberate ("Deprecating unauthenticated JSON access", r/modnews).
/// The per-post `.rss` endpoint still answers 200 and carries the post plus its comments, so
/// the thread survives without the authenticated Data API.
///
/// The feed is Atom. Its first `<entry>` is the post itself; every entry after it is a comment.
/// A comment entry looks like:
///
///     <entry>
///       <author><name>/u/someone</name><uri>…</uri></author>
///       <content type="html">&lt;div class="md"&gt;…&lt;/div&gt;</content>
///       <id>t1_abc123</id>
///       <link href="https://www.reddit.com/r/…/comment/abc123/"/>
///       <updated>2026-08-12T…</updated>
///     </entry>
///
/// Two things the JSON API provided are simply not in this feed, and are not recoverable here:
///
/// - **Score.** No vote counts, so every comment reports 0.
/// - **Threading.** Reddit does not emit the Atom threading extension (`thr:in-reply-to`), so
///   replies arrive flat, in the order Reddit chose. Every comment is depth 0; nesting is not
///   inferable from the feed.
///
/// Comment count is also capped by Reddit at roughly the top few dozen rather than the whole
/// thread.
final class RedditPostRSSParser: NSObject, XMLParserDelegate {

    struct Result {
        let post: ParsedRedditPost
        let comments: [RedditComment]
        /// True when Reddit returned the post but no comment entries.
        var hasComments: Bool { !comments.isEmpty }
    }

    enum ParseError: LocalizedError {
        case notAFeed
        case noEntries

        var errorDescription: String? {
            switch self {
            case .notAFeed: return "That Reddit page did not return a feed"
            case .noEntries: return "That Reddit feed contained no post"
            }
        }
    }

    // MARK: - Accumulated entry state

    private struct Entry {
        var id = ""
        var title = ""
        var authorName = ""
        var content = ""
        var link = ""
        var updated = ""
    }

    private var entries: [Entry] = []
    private var current: Entry?
    private var element = ""
    private var insideAuthor = false
    private var sawFeedRoot = false

    private static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// Parse the post feed. `fallback` supplies the fields Atom does not carry (subreddit and
    /// the preview image already derived by the feed parser).
    func parse(data: Data, fallback: Article) throws -> Result {
        let parser = XMLParser(data: data)
        parser.delegate = self
        guard parser.parse(), sawFeedRoot else { throw ParseError.notAFeed }
        guard let postEntry = entries.first else { throw ParseError.noEntries }

        let permalink = postEntry.link.isEmpty
            ? (fallback.redditCommentsUrl ?? fallback.link)
            : postEntry.link

        // NOT decoded here. `XMLParser` already resolves entity references in character data,
        // so what `foundCharacters` handed us is the final HTML — verified against a live
        // response: the raw feed carries `&lt;img`, and what arrives is `<img`, with
        // `&amp;crop=smart` correctly left escaped because an `&` inside an HTML attribute must
        // be. Decoding again would be the double-decode this codebase removed elsewhere: text a
        // user deliberately escaped (`&amp;lt;script&amp;gt;`) would arrive as `&lt;script&gt;`
        // — inert markup meant to display literally — and a second pass would make it live.
        let selftextHTML = postEntry.content
        let post = ParsedRedditPost(
            id: Self.strippingPrefix(postEntry.id),
            title: postEntry.title,
            author: Self.strippingUserPrefix(postEntry.authorName),
            subreddit: fallback.redditSubreddit ?? "",
            url: fallback.link,
            permalink: permalink,
            commentsUrl: permalink,
            selftext: selftextHTML.htmlToPlainText,
            selftextHtml: selftextHTML.isEmpty ? nil : selftextHTML,
            // Not in the feed. Reported as 0 rather than guessed; the view hides a zero score.
            score: 0,
            numComments: max(entries.count - 1, 0),
            createdUtc: Self.iso8601.date(from: postEntry.updated) ?? fallback.publishedDate,
            imageUrl: fallback.imageUrl,
            // Gallery items are not enumerated in RSS — only the single preview image is.
            galleryImages: [],
            mediaEmbedHtml: nil,
            mediaEmbedWidth: nil,
            mediaEmbedHeight: nil
        )

        let opName = Self.strippingUserPrefix(postEntry.authorName)
        let comments = entries.dropFirst().map { entry -> RedditComment in
            let author = Self.strippingUserPrefix(entry.authorName)
            // Already decoded by XMLParser — see the note on the post body above.
            let bodyHTML = entry.content
            return RedditComment(
                id: entry.id.isEmpty ? UUID().uuidString : entry.id,
                author: author,
                body: bodyHTML.htmlToPlainText,
                decodedBody: bodyHTML.htmlToPlainText,
                bodyHtml: bodyHTML.isEmpty ? nil : bodyHTML,
                score: 0,
                createdUtc: Self.iso8601.date(from: entry.updated) ?? Date(),
                // Flat: Reddit omits the Atom threading extension, so depth is not inferable.
                depth: 0,
                isOP: !author.isEmpty && author == opName,
                replies: []
            )
        }

        return Result(post: post, comments: comments)
    }

    /// `t3_abc123` / `t1_abc123` → `abc123`. `ParsedRedditPost.toArticle()` re-adds the prefix.
    private static func strippingPrefix(_ id: String) -> String {
        guard let underscore = id.firstIndex(of: "_") else { return id }
        return String(id[id.index(after: underscore)...])
    }

    /// `/u/name` → `name`.
    private static func strippingUserPrefix(_ name: String) -> String {
        name.hasPrefix("/u/") ? String(name.dropFirst(3)) : name
    }

    // MARK: - XMLParserDelegate

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        element = elementName

        switch elementName {
        case "feed":
            sawFeedRoot = true
        case "entry":
            current = Entry()
        case "author":
            insideAuthor = true
        case "link":
            // The post entry's link is its permalink; comment entries link to the comment.
            if current != nil, current?.link.isEmpty == true, let href = attributeDict["href"] {
                current?.link = href
            }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard current != nil else { return }

        switch element {
        case "id": current?.id += string
        case "title": current?.title += string
        case "updated": current?.updated += string
        case "content": current?.content += string
        // `<name>` appears inside `<author>`; ignore any other use.
        case "name" where insideAuthor: current?.authorName += string
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        guard current != nil, element == "content",
              let text = String(data: CDATABlock, encoding: .utf8) else { return }
        current?.content += text
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        switch elementName {
        case "entry":
            if let entry = current { entries.append(entry) }
            current = nil
        case "author":
            insideAuthor = false
        default:
            break
        }
        element = ""
    }
}
