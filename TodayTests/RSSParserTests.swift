//
//  RSSParserTests.swift
//  TodayTests
//
//  Comprehensive tests for RSS and Atom feed parsing
//

import XCTest
@testable import Today

final class RSSParserTests: XCTestCase {

    // MARK: - Basic RSS 2.0 Feed Tests

    func testParseBasicRSSFeed() {
        let rssXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0">
            <channel>
                <title>Test Feed</title>
                <description>A test RSS feed</description>
                <item>
                    <title>Test Article</title>
                    <link>https://example.com/article1</link>
                    <description>This is a test article</description>
                    <pubDate>Mon, 23 Oct 2023 10:00:00 +0000</pubDate>
                    <guid>article-1</guid>
                </item>
            </channel>
        </rss>
        """

        let parser = RSSParser()
        let data = rssXML.data(using: .utf8)!
        let success = parser.parse(data: data)

        XCTAssertTrue(success, "Parser should successfully parse valid RSS")
        XCTAssertEqual(parser.feedTitle, "Test Feed")
        XCTAssertEqual(parser.feedDescription, "A test RSS feed")
        XCTAssertEqual(parser.articles.count, 1)

        let article = parser.articles[0]
        XCTAssertEqual(article.title, "Test Article")
        XCTAssertEqual(article.link, "https://example.com/article1")
        XCTAssertEqual(article.description, "This is a test article")
        XCTAssertEqual(article.guid, "article-1")
        XCTAssertNotNil(article.publishedDate)
    }

    func testParseRSSFeedWithMultipleItems() {
        let rssXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0">
            <channel>
                <title>Multi Item Feed</title>
                <item>
                    <title>Article 1</title>
                    <link>https://example.com/1</link>
                    <guid>1</guid>
                </item>
                <item>
                    <title>Article 2</title>
                    <link>https://example.com/2</link>
                    <guid>2</guid>
                </item>
                <item>
                    <title>Article 3</title>
                    <link>https://example.com/3</link>
                    <guid>3</guid>
                </item>
            </channel>
        </rss>
        """

        let parser = RSSParser()
        let success = parser.parse(data: rssXML.data(using: .utf8)!)

        XCTAssertTrue(success)
        XCTAssertEqual(parser.articles.count, 3)
        XCTAssertEqual(parser.articles[0].title, "Article 1")
        XCTAssertEqual(parser.articles[1].title, "Article 2")
        XCTAssertEqual(parser.articles[2].title, "Article 3")
    }

    // MARK: - Atom Feed Tests

    func testParseBasicAtomFeed() {
        let atomXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <feed xmlns="http://www.w3.org/2005/Atom">
            <title>Atom Test Feed</title>
            <subtitle>Testing Atom feeds</subtitle>
            <entry>
                <title>Atom Article</title>
                <link href="https://example.com/atom1"/>
                <id>atom-1</id>
                <summary>This is an Atom article</summary>
                <published>2023-10-23T10:00:00Z</published>
                <author><name>John Doe</name></author>
            </entry>
        </feed>
        """

        let parser = RSSParser()
        let success = parser.parse(data: atomXML.data(using: .utf8)!)

        XCTAssertTrue(success)
        XCTAssertEqual(parser.feedTitle, "Atom Test Feed")
        XCTAssertEqual(parser.articles.count, 1)

        let article = parser.articles[0]
        XCTAssertEqual(article.title, "Atom Article")
        XCTAssertEqual(article.link, "https://example.com/atom1")
        XCTAssertEqual(article.description, "This is an Atom article")
        XCTAssertEqual(article.guid, "atom-1")
        XCTAssertEqual(article.author, "John Doe")
        XCTAssertNotNil(article.publishedDate)
    }

    // MARK: - GUID Fallback Tests

    func testGuidFallsBackToLink() {
        let rssXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0">
            <channel>
                <item>
                    <title>No GUID Article</title>
                    <link>https://example.com/no-guid</link>
                </item>
            </channel>
        </rss>
        """

        let parser = RSSParser()
        _ = parser.parse(data: rssXML.data(using: .utf8)!)

        XCTAssertEqual(parser.articles.count, 1)
        // When no GUID provided, should use link as GUID
        XCTAssertEqual(parser.articles[0].guid, "https://example.com/no-guid")
    }

    // MARK: - Content Field Tests

    func testParseContentEncoded() {
        let rssXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0" xmlns:content="http://purl.org/rss/1.0/modules/content/">
            <channel>
                <item>
                    <title>Article with Content</title>
                    <link>https://example.com/article</link>
                    <description>Short description</description>
                    <content:encoded><![CDATA[<p>Full HTML content here</p>]]></content:encoded>
                    <guid>content-test</guid>
                </item>
            </channel>
        </rss>
        """

        let parser = RSSParser()
        _ = parser.parse(data: rssXML.data(using: .utf8)!)

        let article = parser.articles[0]
        XCTAssertEqual(article.description, "Short description")
        XCTAssertEqual(article.contentEncoded, "<p>Full HTML content here</p>")
    }

    // MARK: - Author Parsing Tests

    func testParseAuthorDCCreator() {
        let rssXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0" xmlns:dc="http://purl.org/dc/elements/1.1/">
            <channel>
                <item>
                    <title>Article</title>
                    <link>https://example.com/article</link>
                    <dc:creator>Jane Smith</dc:creator>
                    <guid>1</guid>
                </item>
            </channel>
        </rss>
        """

        let parser = RSSParser()
        _ = parser.parse(data: rssXML.data(using: .utf8)!)

        XCTAssertEqual(parser.articles[0].author, "Jane Smith")
    }

    // MARK: - Date Parsing Tests

    func testParseRFC822Date() {
        let rssXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0">
            <channel>
                <item>
                    <title>Date Test</title>
                    <link>https://example.com/date</link>
                    <pubDate>Mon, 23 Oct 2023 14:30:00 +0000</pubDate>
                    <guid>date-1</guid>
                </item>
            </channel>
        </rss>
        """

        let parser = RSSParser()
        _ = parser.parse(data: rssXML.data(using: .utf8)!)

        let article = parser.articles[0]
        XCTAssertNotNil(article.publishedDate)

        // Verify it's approximately the right date (Oct 23, 2023)
        if let date = article.publishedDate {
            let calendar = Calendar.current
            let components = calendar.dateComponents([.year, .month, .day], from: date)
            XCTAssertEqual(components.year, 2023)
            XCTAssertEqual(components.month, 10)
            XCTAssertEqual(components.day, 23)
        }
    }

    func testParseRFC822DateWithTimezoneAbbreviation() {
        // Test date format used by The Talk Show podcast: "Thu, 22 May 2014 18:00:00 EDT"
        let rssXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0">
            <channel>
                <item>
                    <title>Timezone Abbrev Test</title>
                    <link>https://example.com/tz</link>
                    <pubDate>Thu, 22 May 2014 18:00:00 EDT</pubDate>
                    <guid>tz-1</guid>
                </item>
            </channel>
        </rss>
        """

        let parser = RSSParser()
        _ = parser.parse(data: rssXML.data(using: .utf8)!)

        let article = parser.articles[0]
        XCTAssertNotNil(article.publishedDate, "Should parse date with timezone abbreviation like EDT")

        // Verify it's the right date (May 22, 2014)
        if let date = article.publishedDate {
            let calendar = Calendar.current
            let components = calendar.dateComponents([.year, .month, .day], from: date)
            XCTAssertEqual(components.year, 2014)
            XCTAssertEqual(components.month, 5)
            XCTAssertEqual(components.day, 22)
        }
    }

    func testParseISO8601Date() {
        let atomXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <feed xmlns="http://www.w3.org/2005/Atom">
            <entry>
                <title>ISO Date Test</title>
                <link href="https://example.com/iso"/>
                <published>2023-10-23T14:30:00Z</published>
                <id>iso-1</id>
            </entry>
        </feed>
        """

        let parser = RSSParser()
        _ = parser.parse(data: atomXML.data(using: .utf8)!)

        let article = parser.articles[0]
        XCTAssertNotNil(article.publishedDate)
    }

    // MARK: - Whitespace Normalization Tests

    func testWhitespaceNormalization() {
        let rssXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0">
            <channel>
                <item>
                    <title>Title  with   multiple    spaces</title>
                    <link>https://example.com/spaces</link>
                    <description>Description
                    with
                    newlines</description>
                    <guid>spaces-1</guid>
                </item>
            </channel>
        </rss>
        """

        let parser = RSSParser()
        _ = parser.parse(data: rssXML.data(using: .utf8)!)

        let article = parser.articles[0]
        XCTAssertEqual(article.title, "Title with multiple spaces")
        XCTAssertEqual(article.description, "Description with newlines")
    }

    // MARK: - Image Extraction Tests

    func testImageExtractionFromDescription() {
        let rssXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0">
            <channel>
                <item>
                    <title>Article with Image</title>
                    <link>https://example.com/img</link>
                    <description><![CDATA[<p>Some text <img src="https://example.com/image.jpg" alt="test"/> more text</p>]]></description>
                    <guid>img-1</guid>
                </item>
            </channel>
        </rss>
        """

        let parser = RSSParser()
        _ = parser.parse(data: rssXML.data(using: .utf8)!)

        let article = parser.articles[0]
        XCTAssertEqual(article.imageUrl, "https://example.com/image.jpg")
    }

    func testMediaContentImageExtraction() {
        let rssXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0" xmlns:media="http://search.yahoo.com/mrss/">
            <channel>
                <item>
                    <title>Media Article</title>
                    <link>https://example.com/media</link>
                    <media:content url="https://example.com/media-image.jpg" medium="image"/>
                    <guid>media-1</guid>
                </item>
            </channel>
        </rss>
        """

        let parser = RSSParser()
        _ = parser.parse(data: rssXML.data(using: .utf8)!)

        let article = parser.articles[0]
        XCTAssertEqual(article.imageUrl, "https://example.com/media-image.jpg")
    }

    // MARK: - Edge Cases

    func testEmptyFeed() {
        let rssXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0">
            <channel>
                <title>Empty Feed</title>
            </channel>
        </rss>
        """

        let parser = RSSParser()
        let success = parser.parse(data: rssXML.data(using: .utf8)!)

        XCTAssertTrue(success)
        XCTAssertEqual(parser.articles.count, 0)
        XCTAssertEqual(parser.feedTitle, "Empty Feed")
    }

    func testMalformedXML() {
        let badXML = """
        <?xml version="1.0"?>
        <rss><channel><item><title>Unclosed
        """

        let parser = RSSParser()
        let success = parser.parse(data: badXML.data(using: .utf8)!)

        XCTAssertFalse(success, "Parser should fail on malformed XML")
    }

    func testItemWithMinimalFields() {
        let rssXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0">
            <channel>
                <item>
                    <title>Minimal Item</title>
                    <link>https://example.com/minimal</link>
                </item>
            </channel>
        </rss>
        """

        let parser = RSSParser()
        _ = parser.parse(data: rssXML.data(using: .utf8)!)

        XCTAssertEqual(parser.articles.count, 1)
        let article = parser.articles[0]
        XCTAssertEqual(article.title, "Minimal Item")
        XCTAssertEqual(article.link, "https://example.com/minimal")
        XCTAssertNil(article.description)
        XCTAssertNil(article.author)
        XCTAssertNil(article.publishedDate)
        // GUID should fall back to link
        XCTAssertEqual(article.guid, "https://example.com/minimal")
    }

    func testHTMLEntitiesInTitle() {
        let rssXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0">
            <channel>
                <item>
                    <title>Article &amp; Title with &lt;tags&gt;</title>
                    <link>https://example.com/entities</link>
                    <guid>entities-1</guid>
                </item>
            </channel>
        </rss>
        """

        let parser = RSSParser()
        _ = parser.parse(data: rssXML.data(using: .utf8)!)

        let article = parser.articles[0]
        // XMLParser decodes entities and preserves spaces around them
        XCTAssertEqual(article.title, "Article & Title with <tags>")
    }
}
