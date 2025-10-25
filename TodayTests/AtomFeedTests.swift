//
//  AtomFeedTests.swift
//  TodayTests
//
//  Tests for Atom feed parsing using real-world kottke.org feed data
//

import XCTest
@testable import Today

final class AtomFeedTests: XCTestCase {

    // MARK: - Kottke.org Feed Tests (Real World Data)

    func testParseKottkeFeedBasics() {
        let atomXML = """
        <?xml version="1.0" encoding="utf-8"?>
        <feed xmlns="http://www.w3.org/2005/Atom" xml:base="https://kottke.org/">
            <title>kottke.org</title>
            <link rel="alternate" type="text/html" href="https://kottke.org/" />
            <link rel="self" type="application/atom+xml" href="https://feeds.kottke.org/main" />
            <id>tag:kottke.org,2009-08-11:05118</id>
            <updated>2025-10-23T12:49:15Z</updated>
            <subtitle>Jason Kottke's weblog, home of fine hypertext products since 1998</subtitle>
            <generator uri="http://www.sixapart.com/movabletype/">Movable Type 4.2</generator>
        </feed>
        """

        let parser = RSSParser()
        let success = parser.parse(data: atomXML.data(using: .utf8)!)

        XCTAssertTrue(success)
        XCTAssertEqual(parser.feedTitle, "kottke.org")
        XCTAssertEqual(parser.feedDescription, "Jason Kottke's weblog, home of fine hypertext products since 1998")
    }

    func testParseKottkeArticleWithCDATATitle() {
        let atomXML = """
        <?xml version="1.0" encoding="utf-8"?>
        <feed xmlns="http://www.w3.org/2005/Atom">
            <entry>
                <title type="html"><![CDATA[ Walking the Earth ]]></title>
                <link rel="alternate" type="text/html" href="https://kottke.org/25/10/walking-the-earth" />
                <id>tag:kottke.org,2025://5.47757</id>
                <published>2025-10-23T12:49:15Z</published>
                <author>
                    <name>Jason Kottke</name>
                    <uri>http://www.kottke.org</uri>
                </author>
            </entry>
        </feed>
        """

        let parser = RSSParser()
        parser.parse(data: atomXML.data(using: .utf8)!)

        XCTAssertEqual(parser.articles.count, 1)
        let article = parser.articles[0]
        XCTAssertEqual(article.title, "Walking the Earth")
        XCTAssertEqual(article.author, "Jason Kottke")
    }

    func testParseKottkeArticleWithEntitiesInTitle() {
        let atomXML = """
        <?xml version="1.0" encoding="utf-8"?>
        <feed xmlns="http://www.w3.org/2005/Atom">
            <entry>
                <title type="html"><![CDATA[ &#8220;I fell at the top of a mountain – and knew I... ]]></title>
                <link rel="alternate" type="text/html" href="https://kottke.org/25/10/0047756-i-fell-at-the-top" />
                <id>tag:kottke.org,2025://13.47756</id>
                <published>2025-10-23T11:02:13Z</published>
                <author>
                    <name>Jason Kottke</name>
                </author>
            </entry>
        </feed>
        """

        let parser = RSSParser()
        parser.parse(data: atomXML.data(using: .utf8)!)

        let article = parser.articles[0]
        // &#8220; and &#8221; are left/right double curly quotes
        XCTAssertTrue(article.title.contains("\u{201C}")) // Left double quote
        XCTAssertTrue(article.title.contains("I fell at the top of a mountain"))
    }

    func testParseKottkeContentWithMultipleCDATA() {
        let atomXML = """
        <?xml version="1.0" encoding="utf-8"?>
        <feed xmlns="http://www.w3.org/2005/Atom">
            <entry>
                <title>Test Article</title>
                <link rel="alternate" type="text/html" href="https://example.com/test" />
                <id>test-1</id>
                <published>2025-10-23T12:00:00Z</published>
                <content type="html" xml:lang="en">
                    <![CDATA[<p>Main article content here.</p>]]>
                    <![CDATA[ <p><strong>Tags:</strong> <a href="https://example.com/tag">tag</a></p>]]>
                    <![CDATA[ <p>💬 <a href="https://example.com">Join the discussion</a> →</p>]]>
                </content>
            </entry>
        </feed>
        """

        let parser = RSSParser()
        parser.parse(data: atomXML.data(using: .utf8)!)

        let article = parser.articles[0]
        XCTAssertNotNil(article.content)
        // Content should contain text from all CDATA sections
        XCTAssertTrue(article.content!.contains("Main article content"))
    }

    func testParseKottkeImageInContent() {
        let atomXML = """
        <?xml version="1.0" encoding="utf-8"?>
        <feed xmlns="http://www.w3.org/2005/Atom">
            <entry>
                <title>Article with Image</title>
                <link rel="alternate" type="text/html" href="https://kottke.org/test" />
                <id>img-test</id>
                <published>2025-10-23T12:00:00Z</published>
                <content type="html">
                    <![CDATA[<p><img src="/cdn-cgi/image/format=auto/plus/misc/images/test.jpg" width="1300" height="1054" /></p><p>Article text.</p>]]>
                </content>
            </entry>
        </feed>
        """

        let parser = RSSParser()
        parser.parse(data: atomXML.data(using: .utf8)!)

        let article = parser.articles[0]
        XCTAssertNotNil(article.imageUrl)
        XCTAssertTrue(article.imageUrl!.contains("test.jpg"))
    }

    func testParseKottkeSrcsetImage() {
        let atomXML = """
        <?xml version="1.0" encoding="utf-8"?>
        <feed xmlns="http://www.w3.org/2005/Atom">
            <entry>
                <title>Srcset Test</title>
                <link rel="alternate" type="text/html" href="https://kottke.org/test" />
                <id>srcset-test</id>
                <published>2025-10-23T12:00:00Z</published>
                <content type="html">
                    <![CDATA[<img src="/small.jpg" srcset="/large.jpg 1200w, /medium.jpg 500w" />]]>
                </content>
            </entry>
        </feed>
        """

        let parser = RSSParser()
        parser.parse(data: atomXML.data(using: .utf8)!)

        let article = parser.articles[0]
        // Should extract from src attribute
        XCTAssertNotNil(article.imageUrl)
        XCTAssertTrue(article.imageUrl!.contains(".jpg"))
    }

    func testParseKottkeWithIframe() {
        let atomXML = """
        <?xml version="1.0" encoding="utf-8"?>
        <feed xmlns="http://www.w3.org/2005/Atom">
            <entry>
                <title>Video Article</title>
                <link rel="alternate" type="text/html" href="https://kottke.org/video" />
                <id>video-test</id>
                <published>2025-10-23T12:00:00Z</published>
                <content type="html">
                    <![CDATA[<p><iframe src="https://www.youtube.com/embed/test" width="640" height="360"></iframe></p><p>Video description.</p>]]>
                </content>
            </entry>
        </feed>
        """

        let parser = RSSParser()
        parser.parse(data: atomXML.data(using: .utf8)!)

        let article = parser.articles[0]
        XCTAssertNotNil(article.content)
        XCTAssertTrue(article.content!.contains("iframe"))
    }

    func testParseKottkeAuthorWithUri() {
        let atomXML = """
        <?xml version="1.0" encoding="utf-8"?>
        <feed xmlns="http://www.w3.org/2005/Atom">
            <entry>
                <title>Author Test</title>
                <link rel="alternate" type="text/html" href="https://example.com" />
                <id>author-test</id>
                <published>2025-10-23T12:00:00Z</published>
                <author>
                    <name>Jason Kottke</name>
                    <uri>http://www.kottke.org</uri>
                </author>
            </entry>
        </feed>
        """

        let parser = RSSParser()
        parser.parse(data: atomXML.data(using: .utf8)!)

        let article = parser.articles[0]
        XCTAssertEqual(article.author, "Jason Kottke")
    }

    func testParseKottkeComplexTitle() {
        let atomXML = """
        <?xml version="1.0" encoding="utf-8"?>
        <feed xmlns="http://www.w3.org/2005/Atom">
            <entry>
                <title type="html"><![CDATA[ &#8216;I get to do whatever I want in the moment&#8217;: why more... ]]></title>
                <link rel="alternate" type="text/html" href="https://kottke.org/test" />
                <id>complex-title</id>
                <published>2025-10-22T17:54:26Z</published>
            </entry>
        </feed>
        """

        let parser = RSSParser()
        parser.parse(data: atomXML.data(using: .utf8)!)

        let article = parser.articles[0]
        // &#8216; and &#8217; are left/right single curly quotes
        XCTAssertTrue(article.title.contains("\u{2018}")) // Left single quote
        XCTAssertTrue(article.title.contains("\u{2019}")) // Right single quote
        XCTAssertTrue(article.title.contains("I get to do whatever I want"))
    }

    func testParseKottkeXmlBaseAttribute() {
        let atomXML = """
        <?xml version="1.0" encoding="utf-8"?>
        <feed xmlns="http://www.w3.org/2005/Atom" xml:base="https://kottke.org/">
            <title>Test Feed</title>
            <subtitle>Test subtitle</subtitle>
        </feed>
        """

        let parser = RSSParser()
        let success = parser.parse(data: atomXML.data(using: .utf8)!)

        XCTAssertTrue(success)
        XCTAssertEqual(parser.feedTitle, "Test Feed")
        XCTAssertEqual(parser.feedDescription, "Test subtitle")
    }

    func testParseKottkeMultipleArticles() {
        let atomXML = """
        <?xml version="1.0" encoding="utf-8"?>
        <feed xmlns="http://www.w3.org/2005/Atom">
            <entry>
                <title>First Article</title>
                <link rel="alternate" type="text/html" href="https://kottke.org/1" />
                <id>1</id>
                <published>2025-10-23T12:00:00Z</published>
            </entry>
            <entry>
                <title>Second Article</title>
                <link rel="alternate" type="text/html" href="https://kottke.org/2" />
                <id>2</id>
                <published>2025-10-23T11:00:00Z</published>
            </entry>
            <entry>
                <title>Third Article</title>
                <link rel="alternate" type="text/html" href="https://kottke.org/3" />
                <id>3</id>
                <published>2025-10-23T10:00:00Z</published>
            </entry>
        </feed>
        """

        let parser = RSSParser()
        parser.parse(data: atomXML.data(using: .utf8)!)

        XCTAssertEqual(parser.articles.count, 3)
        XCTAssertEqual(parser.articles[0].title, "First Article")
        XCTAssertEqual(parser.articles[1].title, "Second Article")
        XCTAssertEqual(parser.articles[2].title, "Third Article")
    }

    func testParseKottkeWithContentAndTags() {
        let atomXML = """
        <?xml version="1.0" encoding="utf-8"?>
        <feed xmlns="http://www.w3.org/2005/Atom">
            <entry>
                <title>Tagged Article</title>
                <link rel="alternate" type="text/html" href="https://kottke.org/test" />
                <id>tagged-test</id>
                <published>2025-10-23T12:00:00Z</published>
                <content type="html" xml:lang="en" xml:base="https://kottke.org/">
                    <![CDATA[<p>Main content here.</p>]]>
                    <![CDATA[ <p><strong>Tags:</strong> <a href="https://kottke.org/tag/art">art</a> · <a href="https://kottke.org/tag/design">design</a></p>]]>
                </content>
            </entry>
        </feed>
        """

        let parser = RSSParser()
        parser.parse(data: atomXML.data(using: .utf8)!)

        let article = parser.articles[0]
        XCTAssertNotNil(article.content)
        XCTAssertTrue(article.content!.contains("Main content"))
        XCTAssertTrue(article.content!.contains("Tags:"))
    }

    func testParseKottkeEmptyTitle() {
        let atomXML = """
        <?xml version="1.0" encoding="utf-8"?>
        <feed xmlns="http://www.w3.org/2005/Atom">
            <entry>
                <title type="html"><![CDATA[  ]]></title>
                <link rel="alternate" type="text/html" href="https://kottke.org/test" />
                <id>empty-title</id>
                <published>2025-10-23T12:00:00Z</published>
                <content type="html">
                    <![CDATA[<p>Content without a real title.</p>]]>
                </content>
            </entry>
        </feed>
        """

        let parser = RSSParser()
        parser.parse(data: atomXML.data(using: .utf8)!)

        let article = parser.articles[0]
        // Title should be empty or whitespace only after normalization
        XCTAssertTrue(article.title.isEmpty)
    }

    func testParseAtomLinkWithHrefAttribute() {
        let atomXML = """
        <?xml version="1.0" encoding="utf-8"?>
        <feed xmlns="http://www.w3.org/2005/Atom">
            <entry>
                <title>Link Test</title>
                <link rel="alternate" type="text/html" href="https://example.com/article" />
                <id>link-test</id>
                <published>2025-10-23T12:00:00Z</published>
            </entry>
        </feed>
        """

        let parser = RSSParser()
        parser.parse(data: atomXML.data(using: .utf8)!)

        let article = parser.articles[0]
        XCTAssertEqual(article.link, "https://example.com/article")
    }
}
