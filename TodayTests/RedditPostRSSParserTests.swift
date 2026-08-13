//
//  RedditPostRSSParserTests.swift
//  TodayTests
//
//  Covers parsing a Reddit post's Atom feed into the post and its comments.
//

import XCTest
import SwiftData
@testable import Today

final class RedditPostRSSParserTests: XCTestCase {

    /// A trimmed copy of a real `https://www.reddit.com/r/<sub>/comments/<id>/<slug>/.rss`
    /// response — same element order, namespaces and entity encoding Reddit actually emits,
    /// including the `<!-- SC_OFF -->` wrapper and the `&lt;`-escaped comment HTML.
    private let feed = """
    <?xml version="1.0" encoding="UTF-8"?>
    <feed xmlns="http://www.w3.org/2005/Atom" xmlns:media="http://search.yahoo.com/mrss/">
    <category term="itookapicture" label="r/itookapicture"/>
    <updated>2026-08-12T18:00:00+00:00</updated>
    <title>ITAP of a splash</title>
    <entry>
      <author><name>/u/Lower_Context3517</name><uri>https://www.reddit.com/user/Lower_Context3517</uri></author>
      <category term="itookapicture" label="r/itookapicture"/>
      <content type="html">&lt;table&gt; &lt;tr&gt;&lt;td&gt; &lt;a href="https://www.reddit.com/r/itookapicture/comments/1vn4sxk/itap_of_a_splash/"&gt;&lt;img src="https://preview.redd.it/xhfay7t4r3jh1.jpeg" alt="ITAP of a splash" /&gt;&lt;/a&gt; &lt;/td&gt;&lt;/tr&gt;&lt;/table&gt;</content>
      <id>t3_1vn4sxk</id>
      <link href="https://www.reddit.com/r/itookapicture/comments/1vn4sxk/itap_of_a_splash/"/>
      <updated>2026-08-12T17:30:00+00:00</updated>
      <title>ITAP of a splash</title>
    </entry>
    <entry>
      <author><name>/u/AutoModerator</name><uri>https://www.reddit.com/user/AutoModerator</uri></author>
      <category term="itookapicture" label="r/itookapicture"/>
      <content type="html">&lt;!-- SC_OFF --&gt;&lt;div class="md"&gt;&lt;p&gt;Welcome to &lt;a href="/r/itookapicture"&gt;/r/itookapicture&lt;/a&gt;! Rules &amp;amp; guidelines apply.&lt;/p&gt;&lt;/div&gt;</content>
      <id>t1_aaa111</id>
      <link href="https://www.reddit.com/r/itookapicture/comments/1vn4sxk/itap_of_a_splash/aaa111/"/>
      <updated>2026-08-12T17:31:00+00:00</updated>
      <title>/u/AutoModerator on ITAP of a splash</title>
    </entry>
    <entry>
      <author><name>/u/Lower_Context3517</name><uri>https://www.reddit.com/user/Lower_Context3517</uri></author>
      <category term="itookapicture" label="r/itookapicture"/>
      <content type="html">&lt;div class="md"&gt;&lt;p&gt;Shot at 1/2000s. Thanks!&lt;/p&gt;&lt;/div&gt;</content>
      <id>t1_bbb222</id>
      <link href="https://www.reddit.com/r/itookapicture/comments/1vn4sxk/itap_of_a_splash/bbb222/"/>
      <updated>2026-08-12T17:45:00+00:00</updated>
      <title>/u/Lower_Context3517 on ITAP of a splash</title>
    </entry>
    </feed>
    """

    private func makeArticle() -> Article {
        Article(
            title: "ITAP of a splash",
            link: "https://www.reddit.com/r/itookapicture/comments/1vn4sxk/itap_of_a_splash/",
            imageUrl: "https://preview.redd.it/xhfay7t4r3jh1.jpeg",
            publishedDate: Date(timeIntervalSince1970: 1_000_000),
            guid: "t3_1vn4sxk",
            redditSubreddit: "itookapicture",
            redditCommentsUrl: "https://www.reddit.com/r/itookapicture/comments/1vn4sxk/itap_of_a_splash/",
            redditPostId: "t3_1vn4sxk"
        )
    }

    private func parse() throws -> RedditPostRSSParser.Result {
        try RedditPostRSSParser().parse(
            data: Data(feed.utf8),
            fallback: makeArticle()
        )
    }

    // MARK: - Happy path

    func testFirstEntryBecomesThePostAndTheRestBecomeComments() throws {
        let result = try parse()

        XCTAssertEqual(result.post.id, "1vn4sxk", "the t3_ prefix is stripped; toArticle() re-adds it")
        XCTAssertEqual(result.post.title, "ITAP of a splash")
        XCTAssertEqual(result.post.author, "Lower_Context3517", "the /u/ prefix is stripped")
        XCTAssertEqual(result.post.subreddit, "itookapicture", "carried from the article, not the feed")
        XCTAssertEqual(result.comments.count, 2, "every entry after the first is a comment")
        XCTAssertTrue(result.hasComments)
    }

    /// The whole point of the switch: comments come back from RSS, with their authors and bodies.
    func testCommentsCarryAuthorAndDecodedBody() throws {
        let result = try parse()

        XCTAssertEqual(result.comments[0].author, "AutoModerator")
        XCTAssertEqual(result.comments[1].author, "Lower_Context3517")

        let body = try XCTUnwrap(result.comments[1].bodyHtml)
        XCTAssertTrue(body.contains("<p>"), "entity-escaped HTML is decoded once into real markup: \(body)")
        XCTAssertTrue(result.comments[1].decodedBody.contains("1/2000s"), "plain-text body is readable")
    }

    func testCommentByThePosterIsMarkedAsOP() throws {
        let result = try parse()

        XCTAssertFalse(result.comments[0].isOP, "AutoModerator is not the poster")
        XCTAssertTrue(result.comments[1].isOP, "the post author's own comment is flagged")
    }

    func testPostBodyAndImageSurvive() throws {
        let result = try parse()

        let html = try XCTUnwrap(result.post.selftextHtml)
        XCTAssertTrue(html.contains("<img"), "the preview image markup is decoded, not left escaped")
        XCTAssertEqual(result.post.imageUrl, "https://preview.redd.it/xhfay7t4r3jh1.jpeg")
        XCTAssertEqual(
            result.post.permalink,
            "https://www.reddit.com/r/itookapicture/comments/1vn4sxk/itap_of_a_splash/"
        )
    }

    func testDatesComeFromTheFeedNotTheArticle() throws {
        let result = try parse()

        // 2026-08-12T17:30:00Z, not the article's 1970-era fallback.
        XCTAssertGreaterThan(result.post.createdUtc.timeIntervalSince1970, 1_700_000_000)
        XCTAssertGreaterThan(result.comments[1].createdUtc, result.comments[0].createdUtc)
    }

    // MARK: - Documented limitations
    //
    // These pin what RSS *cannot* provide, so a future reader does not mistake the zeros for
    // a parsing bug. Recovering either one requires the authenticated Data API.

    func testScoreIsZeroBecauseRSSDoesNotCarryIt() throws {
        let result = try parse()

        XCTAssertEqual(result.post.score, 0)
        XCTAssertTrue(result.comments.allSatisfy { $0.score == 0 })
    }

    func testCommentsAreFlatBecauseRedditOmitsAtomThreading() throws {
        let result = try parse()

        XCTAssertTrue(result.comments.allSatisfy { $0.depth == 0 })
        XCTAssertTrue(result.comments.allSatisfy { $0.replies.isEmpty })
    }

    func testNumCommentsCountsTheEntriesActuallyReturned() throws {
        let result = try parse()

        // Reddit caps the feed well below a large thread's real reply count.
        XCTAssertEqual(result.post.numComments, 2)
    }

    // MARK: - Decoding happens exactly once

    /// `XMLParser` resolves entity references in character data, so the parser must not decode
    /// again. A user posting escaped markup — text meant to display literally — arrives from
    /// XMLParser as inert `&lt;script&gt;`; a second decode would make it live inside the
    /// WebView that renders comment HTML.
    func testEscapedMarkupInACommentIsNotDecodedIntoLiveTags() throws {
        // Doubly escaped in the raw feed, which is how Reddit transports a comment whose *text*
        // is `&lt;script&gt;alert(1)&lt;/script&gt;`.
        let hostile = """
        <?xml version="1.0" encoding="UTF-8"?>
        <feed xmlns="http://www.w3.org/2005/Atom">
        <entry>
          <author><name>/u/op</name></author>
          <content type="html">&amp;lt;p&amp;gt;post&amp;lt;/p&amp;gt;</content>
          <id>t3_x</id><updated>2026-08-12T17:30:00+00:00</updated><title>t</title>
        </entry>
        <entry>
          <author><name>/u/someone</name></author>
          <content type="html">&amp;lt;script&amp;gt;alert(1)&amp;lt;/script&amp;gt;</content>
          <id>t1_y</id><updated>2026-08-12T17:31:00+00:00</updated><title>c</title>
        </entry>
        </feed>
        """

        let result = try RedditPostRSSParser().parse(data: Data(hostile.utf8), fallback: makeArticle())
        let body = try XCTUnwrap(result.comments[0].bodyHtml)

        XCTAssertFalse(
            body.contains("<script"),
            "escaped text must stay escaped — a second decode would make it executable markup: \(body)"
        )
        XCTAssertTrue(body.contains("&lt;script&gt;"), "it should still read as literal text: \(body)")
    }

    /// The other side of the same rule: what Reddit sends as real markup must arrive as real
    /// markup, so images and links in a post body still render.
    func testGenuineMarkupSurvivesAsMarkup() throws {
        let result = try parse()
        let html = try XCTUnwrap(result.post.selftextHtml)

        XCTAssertTrue(html.contains("<img"), "a real <img> must not be left escaped: \(html.prefix(120))")
        XCTAssertFalse(html.contains("&lt;img"), "…and must not be double-escaped either")
    }

    // MARK: - Link target and redgifs embeds

    /// Atom's `<link href>` is the permalink; the post's real destination is the `[link]`
    /// anchor inside the content table. Native image posts point at `i.redd.it`.
    func testLinkTargetIsTakenFromTheLinkAnchorNotThePermalink() {
        let html = """
        <table><tr><td><a href="https://www.reddit.com/r/x/comments/abc/slug/"><img src="p.jpg"/></a></td><td>
        <span><a href="https://i.redd.it/abc123.jpeg">[link]</a></span>
        <span><a href="https://www.reddit.com/r/x/comments/abc/slug/">[comments]</a></span>
        </td></tr></table>
        """
        XCTAssertEqual(RedditPostRSSParser.linkTarget(in: html), "https://i.redd.it/abc123.jpeg")
    }

    func testRedgifsSlugIsExtractedFromBothHostForms() {
        XCTAssertEqual(
            RedditPostRSSParser.redgifsSlug(in: "https://www.redgifs.com/watch/wingedbreakablegonolek"),
            "wingedbreakablegonolek"
        )
        // Feeds carry the bare host too.
        XCTAssertEqual(
            RedditPostRSSParser.redgifsSlug(in: "https://redgifs.com/watch/fonddarkolivegreencollardlizard"),
            "fonddarkolivegreencollardlizard"
        )
    }

    /// The iframe lands in `EmbeddedMediaWebView`, which keeps JavaScript enabled so third-party
    /// players work. Feed content must therefore not be able to choose the frame's origin.
    func testNonRedgifsAndLookalikeHostsProduceNoEmbed() {
        let rejected = [
            "https://i.redd.it/abc.jpeg",
            "https://redgifs.com.evil.example/watch/abc",   // look-alike host
            "https://evil.example/watch/abc",
            "https://www.redgifs.com/users/someone",         // not a watch URL
            "javascript:alert(1)",
            "file:///etc/passwd",
        ]
        for url in rejected {
            XCTAssertNil(RedditPostRSSParser.redgifsSlug(in: url), "\(url) must not yield an embed")
        }
    }

    func testEmbedURLIsBuiltFromTheHardcodedHostAndValidatedSlug() {
        let embed = RedditPostRSSParser.redgifsEmbedHTML(for: "wingedbreakablegonolek")

        XCTAssertTrue(embed.contains("https://www.redgifs.com/ifr/wingedbreakablegonolek"))
        XCTAssertTrue(embed.hasPrefix("<iframe"), "the view renders this as embedded media")
    }

    /// End to end: a redgifs post yields a playable embed; a native image post does not.
    func testRedgifsPostProducesAnEmbedAndImagePostDoesNot() throws {
        let redgifsFeed = feed.replacingOccurrences(
            of: "https://www.reddit.com/r/itookapicture/comments/1vn4sxk/itap_of_a_splash/&lt;/a&gt;&lt;/td&gt;",
            with: "https://www.reddit.com/r/itookapicture/comments/1vn4sxk/itap_of_a_splash/&lt;/a&gt;&lt;/td&gt;"
        ).replacingOccurrences(
            of: "&lt;table&gt; &lt;tr&gt;&lt;td&gt;",
            with: "&lt;table&gt; &lt;tr&gt;&lt;td&gt;&lt;span&gt;&lt;a href=&quot;https://www.redgifs.com/watch/wingedbreakablegonolek&quot;&gt;[link]&lt;/a&gt;&lt;/span&gt;"
        )

        let withEmbed = try RedditPostRSSParser().parse(
            data: Data(redgifsFeed.utf8), fallback: makeArticle()
        )
        let embed = try XCTUnwrap(withEmbed.post.mediaEmbedHtml, "a redgifs post should be framable")
        XCTAssertTrue(embed.contains("redgifs.com/ifr/wingedbreakablegonolek"))
        XCTAssertEqual(withEmbed.post.url, "https://www.redgifs.com/watch/wingedbreakablegonolek")
        XCTAssertNotNil(withEmbed.post.mediaEmbedWidth)
        XCTAssertNotNil(withEmbed.post.mediaEmbedHeight)

        // The plain image fixture has no [link] anchor at all, so no embed and no dimensions.
        let plain = try parse()
        XCTAssertNil(plain.post.mediaEmbedHtml)
        XCTAssertNil(plain.post.mediaEmbedWidth)
    }

    // MARK: - Error paths

    func testNonFeedPayloadThrowsRatherThanProducingAnEmptyPost() {
        let html = Data("<html><body>Blocked</body></html>".utf8)

        XCTAssertThrowsError(try RedditPostRSSParser().parse(data: html, fallback: makeArticle())) { error in
            XCTAssertEqual(error as? RedditPostRSSParser.ParseError, .notAFeed)
        }
    }

    func testFeedWithNoEntriesThrows() {
        let empty = Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <feed xmlns="http://www.w3.org/2005/Atom"><title>nothing</title></feed>
        """.utf8)

        XCTAssertThrowsError(try RedditPostRSSParser().parse(data: empty, fallback: makeArticle())) { error in
            XCTAssertEqual(error as? RedditPostRSSParser.ParseError, .noEntries)
        }
    }
}
