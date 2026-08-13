//
//  HTMLEntityDecodingTests.swift
//  TodayTests
//
//  Characterization + security tests for the canonical HTML entity decoder.
//
//  These were written BEFORE consolidating the four separate `decodeHTMLEntities`
//  implementations (HTMLHelper / RSSParser / JSONFeedParser / RedditJSONParser) so the
//  merge is provably behavior-preserving except for the intended fixes:
//    1. no single pass may chain one entity into another (`&amp;lt;` stays `&lt;`)
//    2. no call site decodes twice
//    3. every call site gets the union of named + numeric entity support
//

import XCTest
@testable import Today

final class HTMLEntityDecodingTests: XCTestCase {

    // MARK: - Happy path: each supported entity decodes, exactly once

    func testDecodesCommonNamedEntities() {
        XCTAssertEqual("AT&amp;T".decodeHTMLEntities(), "AT&T")
        XCTAssertEqual("&lt;b&gt;".decodeHTMLEntities(), "<b>")
        XCTAssertEqual("&quot;quoted&quot;".decodeHTMLEntities(), "\"quoted\"")
        XCTAssertEqual("it&apos;s".decodeHTMLEntities(), "it's")
        XCTAssertEqual("Kylo&nbsp;Ren".decodeHTMLEntities(), "Kylo Ren")
    }

    func testDecodesTypographicNamedEntities() {
        XCTAssertEqual("&ldquo;x&rdquo;".decodeHTMLEntities(), "\u{201C}x\u{201D}")
        XCTAssertEqual("&lsquo;x&rsquo;".decodeHTMLEntities(), "\u{2018}x\u{2019}")
        XCTAssertEqual("a&mdash;b&ndash;c&hellip;".decodeHTMLEntities(), "a\u{2014}b\u{2013}c\u{2026}")
    }

    func testDecodesNumericAndHexEntities() {
        XCTAssertEqual("&#39;".decodeHTMLEntities(), "'")
        XCTAssertEqual("&#8217;".decodeHTMLEntities(), "\u{2019}")
        XCTAssertEqual("&#x27;".decodeHTMLEntities(), "'")
        XCTAssertEqual("&#X2019;".decodeHTMLEntities(), "\u{2019}")
        XCTAssertEqual(
            "Kylo Ren &#8216;Star Wars&#8217;".decodeHTMLEntities(),
            "Kylo Ren \u{2018}Star Wars\u{2019}"
        )
    }

    func testLeavesUnknownAndMalformedEntitiesAlone() {
        XCTAssertEqual("5 &frobnicate; 6".decodeHTMLEntities(), "5 &frobnicate; 6")
        XCTAssertEqual("bare & ampersand".decodeHTMLEntities(), "bare & ampersand")
        XCTAssertEqual("unterminated &amp".decodeHTMLEntities(), "unterminated &amp")
        XCTAssertEqual("&#999999999999;".decodeHTMLEntities(), "&#999999999999;")
        XCTAssertEqual("".decodeHTMLEntities(), "")
    }

    // MARK: - Edge case: the ordering fix

    /// A single pass must not decode `&amp;` into `&` and then let a later rule consume the
    /// result. `&amp;lt;` is an author writing the literal text `&lt;`.
    func testSinglePassCannotChainEntities() {
        XCTAssertEqual("&amp;lt;".decodeHTMLEntities(), "&lt;")
        XCTAssertEqual("&amp;gt;".decodeHTMLEntities(), "&gt;")
        XCTAssertEqual("&amp;quot;".decodeHTMLEntities(), "&quot;")
        XCTAssertEqual("&amp;nbsp;".decodeHTMLEntities(), "&nbsp;")
        XCTAssertEqual("&amp;#39;".decodeHTMLEntities(), "&#39;")
        // Numeric-first chaining: `&#38;` is `&`, and must not seed a named entity either.
        XCTAssertEqual("&#38;lt;".decodeHTMLEntities(), "&lt;")
        XCTAssertEqual("&#x26;lt;".decodeHTMLEntities(), "&lt;")
    }

    // MARK: - Error path: escaped markup stays escaped

    func testEscapedScriptPayloadIsNotReconstructedInOnePass() {
        let onceEscaped = "&amp;lt;script&amp;gt;alert(1)&amp;lt;/script&amp;gt;"
        let decoded = onceEscaped.decodeHTMLEntities()

        XCTAssertEqual(decoded, "&lt;script&gt;alert(1)&lt;/script&gt;")
        XCTAssertFalse(decoded.contains("<script"), "one decode must not produce live markup")
    }

    func testDoubleEscapedScriptPayloadIsNotReconstructedInOnePass() {
        let twiceEscaped = "&amp;amp;lt;script&amp;amp;gt;alert(1)&amp;amp;lt;/script&amp;amp;gt;"
        let decoded = twiceEscaped.decodeHTMLEntities()

        XCTAssertEqual(decoded, "&amp;lt;script&amp;gt;alert(1)&amp;lt;/script&amp;gt;")
        XCTAssertFalse(decoded.contains("<script"))
    }

    /// The property that makes the single-decode rule at the render seams matter.
    func testDecodingIsNotAppliedTwiceAnywhere() {
        let payload = "&amp;lt;script&amp;gt;alert(1)&amp;lt;/script&amp;gt;"

        XCTAssertFalse(WebViewSecurity.decodeForRendering(payload).contains("<script"))
        XCTAssertEqual(WebViewSecurity.decodeForRendering(payload), payload.decodeHTMLEntities())
    }

    // MARK: - strippingHTML shares the canonical decoder

    func testStrippingHTMLUsesTheCanonicalDecoder() {
        XCTAssertEqual("Kylo&nbsp;Ren".htmlToPlainText, "Kylo Ren")
        XCTAssertEqual(
            "Adam Driver &#8216;Star Wars&#8217;".htmlToPlainText,
            "Adam Driver \u{2018}Star Wars\u{2019}"
        )
        // Escaped markup in a feed body must stay escaped text, not become a tag.
        XCTAssertEqual("&amp;lt;b&amp;gt;bold&amp;lt;/b&amp;gt;".htmlToPlainText,
                       "&lt;b&gt;bold&lt;/b&gt;")
    }

    // MARK: - Composed call-site behavior: RSSParser

    /// CDATA keeps `XMLParser` from decoding the entities itself, so what lands in
    /// `ParsedArticle` is exactly `decodeHTMLEntities(normalizeWhitespace(_)).texturize()`.
    func testRSSParserComposedEntityHandling() {
        let rssXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0">
            <channel>
                <title>Entities</title>
                <item>
                    <title><![CDATA[AT&amp;T &#8216;Star Wars&#8217; &amp;lt;b&amp;gt;]]></title>
                    <link>https://example.com/1</link>
                    <description><![CDATA[Kylo&nbsp;Ren   spaced]]></description>
                    <content:encoded xmlns:content="http://purl.org/rss/1.0/modules/content/"><![CDATA[<p>AT&amp;T &amp;lt;script&amp;gt;alert(1)&amp;lt;/script&amp;gt;</p>]]></content:encoded>
                    <guid>1</guid>
                </item>
            </channel>
        </rss>
        """

        let parser = RSSParser()
        XCTAssertTrue(parser.parse(data: rssXML.data(using: .utf8)!))
        let article = parser.articles[0]

        XCTAssertEqual(article.title, "AT&T \u{2018}Star Wars\u{2019} &lt;b&gt;")
        XCTAssertEqual(article.description, "Kylo Ren spaced")
        XCTAssertEqual(article.contentEncoded, "<p>AT&T &lt;script&gt;alert(1)&lt;/script&gt;</p>")
        XCTAssertFalse(article.contentEncoded?.contains("<script") ?? false)
    }

    // MARK: - Composed call-site behavior: JSONFeedParser

    func testJSONFeedParserComposedEntityHandling() throws {
        let jsonFeed = """
        {
            "version": "https://jsonfeed.org/version/1.1",
            "title": "Entities",
            "items": [
                {
                    "id": "1",
                    "url": "https://example.org/1",
                    "title": "AT&amp;T &#8216;Star Wars&#8217; &amp;lt;b&amp;gt;",
                    "summary": "Kylo&nbsp;Ren",
                    "content_html": "<p>AT&amp;T &amp;lt;script&amp;gt;alert(1)&amp;lt;/script&amp;gt;</p>"
                }
            ]
        }
        """

        let parser = JSONFeedParser()
        XCTAssertTrue(try parser.parse(data: jsonFeed.data(using: .utf8)!))
        let article = parser.articles[0]

        XCTAssertEqual(article.title, "AT&T \u{2018}Star Wars\u{2019} &lt;b&gt;")
        XCTAssertEqual(article.description, "Kylo Ren")
        XCTAssertEqual(article.contentEncoded, "<p>AT&T &lt;script&gt;alert(1)&lt;/script&gt;</p>")
        XCTAssertFalse(article.contentEncoded?.contains("<script") ?? false)
    }
}
