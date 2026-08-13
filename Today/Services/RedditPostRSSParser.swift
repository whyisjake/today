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

        // Where the post actually points, and whether that is something we can frame.
        // Target comes from the raw content (the scaffold is where the [link] anchor lives);
        // the displayed body is the scaffold-free part.
        let target = Self.linkTarget(in: selftextHTML)
        let displayBody = Self.postBody(in: selftextHTML)
        let embedHTML = target.flatMap(Self.redgifsSlug(in:)).map(Self.redgifsEmbedHTML(for:))
        let videoURL = target.flatMap(Self.redditVideoHLSURL(in:))

        let post = ParsedRedditPost(
            id: Self.strippingPrefix(postEntry.id),
            title: postEntry.title,
            author: Self.strippingUserPrefix(postEntry.authorName),
            subreddit: fallback.redditSubreddit ?? "",
            url: target ?? fallback.link,
            permalink: permalink,
            commentsUrl: permalink,
            selftext: displayBody?.htmlToPlainText,
            selftextHtml: displayBody,
            // Not in the feed. Reported as 0 rather than guessed; the view hides a zero score.
            score: 0,
            numComments: max(entries.count - 1, 0),
            createdUtc: Self.iso8601.date(from: postEntry.updated) ?? fallback.publishedDate,
            imageUrl: fallback.imageUrl,
            // Gallery items are not enumerated in RSS — only the single preview image is.
            galleryImages: [],
            mediaEmbedHtml: embedHTML,
            // RSS carries no dimensions for the linked media, so the player gets a 16:9 box.
            // redgifs' iframe letterboxes to its own aspect inside whatever it is given, so a
            // portrait clip is shown whole rather than cropped — just with bars.
            mediaEmbedWidth: embedHTML == nil ? nil : 640,
            mediaEmbedHeight: embedHTML == nil ? nil : 360,
            videoURL: videoURL
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

    // MARK: - Building a post without a network call

    /// Build a post from the article the subreddit feed already produced.
    ///
    /// The per-post feed is not needed for anything the view renders. The subreddit entry
    /// carries the same content table — title, author, date, permalink, preview image, and the
    /// `[link]` anchor identifying a redgifs or v.redd.it target — so opening a post costs no
    /// request and cannot be rate-limited. Only the comment thread required the extra fetch,
    /// and that now opens on Reddit.
    ///
    /// Returns nil when the article carries no Reddit permalink, which is the one case the view
    /// has nothing to show.
    static func makePost(from article: Article) -> ParsedRedditPost? {
        guard let permalink = article.redditCommentsUrl ?? article.articleURL?.absoluteString else {
            return nil
        }

        // The stored content is the same table the post feed returns; `contentEncoded` wins when
        // both are present, matching how the feed parser fills them.
        let bodyHTML = article.contentEncoded ?? article.content ?? article.articleDescription ?? ""
        let target = linkTarget(in: bodyHTML)
        let displayBody = postBody(in: bodyHTML)

        return ParsedRedditPost(
            id: strippingPrefix(article.redditPostId ?? article.guid),
            title: article.title,
            author: strippingUserPrefix(article.author ?? ""),
            subreddit: article.redditSubreddit ?? "",
            url: target ?? article.link,
            permalink: permalink,
            commentsUrl: permalink,
            selftext: displayBody?.htmlToPlainText,
            selftextHtml: displayBody,
            // RSS carries neither, and the view no longer shows either.
            score: 0,
            numComments: 0,
            createdUtc: article.publishedDate,
            imageUrl: article.imageUrl,
            galleryImages: [],
            mediaEmbedHtml: target.flatMap(redgifsSlug(in:)).map(redgifsEmbedHTML(for:)),
            mediaEmbedWidth: target.flatMap(redgifsSlug(in:)) == nil ? nil : 640,
            mediaEmbedHeight: target.flatMap(redgifsSlug(in:)) == nil ? nil : 360,
            videoURL: target.flatMap(redditVideoHLSURL(in:))
        )
    }

    /// The author's actual post text, with Reddit's scaffolding removed.
    ///
    /// Every RSS entry's content is wrapped in boilerplate Reddit builds for the web view: a
    /// thumbnail table, then `submitted by /u/name`, then `[link]` and `[comments]` anchors.
    /// Rendering that verbatim repeated the author and thumbnail already shown in the header,
    /// and for a link post — an image, a redgifs clip, a v.redd.it video — the scaffold *is* the
    /// whole content, so the body was nothing but duplicate chrome under the media.
    ///
    /// Reddit delimits real self-text with `<!-- SC_OFF -->` / `<!-- SC_ON -->`, so that marker
    /// separates the two cases exactly: text between them is the author's, and its absence means
    /// the post has no body.
    static func postBody(in html: String) -> String? {
        guard let start = html.range(of: "<!-- SC_OFF -->"),
              let end = html.range(of: "<!-- SC_ON -->", range: start.upperBound..<html.endIndex)
        else { return nil }

        let body = html[start.upperBound..<end.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        return body.isEmpty ? nil : body
    }

    // MARK: - Link target and embeds

    /// The URL a Reddit post actually points at, pulled from the `[link]` anchor in its entry.
    ///
    /// Atom's `<link href>` is the *permalink* (the comments page). The post's real destination
    /// — `i.redd.it/…` for a native image, `redgifs.com/watch/…` for a hosted clip — appears
    /// only inside the content table Reddit builds, as the anchor whose text is `[link]`.
    static func linkTarget(in html: String) -> String? {
        // Matches `<a href="TARGET">[link]</a>`, tolerating the whitespace Reddit inserts.
        let pattern = #"<a\s+href="([^"]+)"\s*>\s*\[link\]\s*</a>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(
                in: html, range: NSRange(html.startIndex..., in: html)
              ),
              let range = Range(match.range(at: 1), in: html)
        else { return nil }

        return String(html[range])
    }

    /// A redgifs slug, if this URL is a redgifs watch link.
    ///
    /// Accepts `www.redgifs.com` and the bare `redgifs.com` — feeds carry both — and rejects
    /// anything else, including look-alike hosts such as `redgifs.com.evil.example`.
    static func redgifsSlug(in urlString: String) -> String? {
        guard let url = SafeURL.webOpenable(urlString),
              let host = url.host?.lowercased(),
              host == "redgifs.com" || host == "www.redgifs.com"
        else { return nil }

        let parts = url.path.split(separator: "/").map(String.init)
        guard parts.count >= 2, parts[0].lowercased() == "watch" else { return nil }

        // Slugs are alphanumeric. Validating rather than trusting keeps anything odd out of the
        // iframe URL built below.
        let slug = parts[1]
        guard !slug.isEmpty, slug.allSatisfy({ $0.isLetter || $0.isNumber }) else { return nil }
        return slug
    }

    /// The HLS manifest for a Reddit-hosted clip, or nil when the post is not one.
    ///
    /// A `v.redd.it/<id>` link is a landing page, not a media file, so it cannot be handed to
    /// AVPlayer directly. The playable asset sits at a fixed path beneath it — verified against
    /// a live clip, which returns a master playlist offering several bitrates. AVPlayer speaks
    /// HLS natively, so no extra machinery is needed.
    ///
    /// As with the redgifs embed, the URL is rebuilt from a hardcoded host and a validated id
    /// rather than passing the feed's href through.
    static func redditVideoHLSURL(in urlString: String) -> String? {
        guard let url = SafeURL.webOpenable(urlString),
              url.host?.lowercased() == "v.redd.it"
        else { return nil }

        let id = url.path.split(separator: "/").map(String.init).first ?? ""
        guard !id.isEmpty, id.allSatisfy({ $0.isLetter || $0.isNumber }) else { return nil }

        return "https://v.redd.it/\(id)/HLSPlaylist.m3u8"
    }

    /// The iframe markup for a redgifs clip, or nil when the post is not one.
    ///
    /// The URL is assembled from a hardcoded host and a validated slug — the feed's own href is
    /// never interpolated. That matters because `EmbeddedMediaWebView`, which renders this,
    /// deliberately keeps JavaScript enabled so third-party players work; letting feed content
    /// choose the frame's origin would hand it a scripted context.
    static func redgifsEmbedHTML(for slug: String) -> String {
        "<iframe src=\"https://www.redgifs.com/ifr/\(slug)\" frameborder=\"0\" scrolling=\"no\" allowfullscreen></iframe>"
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
