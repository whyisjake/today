//
//  JSONFeedTests.swift
//  TodayTests
//
//  Tests for JSON Feed parsing (https://www.jsonfeed.org/version/1.1/)
//

import XCTest
@testable import Today

final class JSONFeedTests: XCTestCase {

    // MARK: - Basic JSON Feed Tests

    func testParseBasicJSONFeed() throws {
        let jsonFeed = """
        {
            "version": "https://jsonfeed.org/version/1.1",
            "title": "My Example Feed",
            "home_page_url": "https://example.org/",
            "feed_url": "https://example.org/feed.json",
            "description": "A sample feed",
            "items": [
                {
                    "id": "2",
                    "url": "https://example.org/second-item",
                    "title": "Second Item",
                    "content_text": "This is the second item.",
                    "date_published": "2024-01-15T10:00:00Z"
                },
                {
                    "id": "1",
                    "url": "https://example.org/first-item",
                    "title": "First Item",
                    "content_html": "<p>Hello, world!</p>",
                    "date_published": "2024-01-10T10:00:00Z"
                }
            ]
        }
        """

        let parser = JSONFeedParser()
        let data = jsonFeed.data(using: .utf8)!
        let success = try parser.parse(data: data)

        XCTAssertTrue(success, "Parser should successfully parse valid JSON Feed")
        XCTAssertEqual(parser.feedTitle, "My Example Feed")
        XCTAssertEqual(parser.feedDescription, "A sample feed")
        XCTAssertEqual(parser.articles.count, 2)

        let firstArticle = parser.articles[0]
        XCTAssertEqual(firstArticle.title, "Second Item")
        XCTAssertEqual(firstArticle.link, "https://example.org/second-item")
        XCTAssertEqual(firstArticle.guid, "2")
        XCTAssertNotNil(firstArticle.publishedDate)

        let secondArticle = parser.articles[1]
        XCTAssertEqual(secondArticle.title, "First Item")
        XCTAssertEqual(secondArticle.contentEncoded, "<p>Hello, world!</p>")
    }

    func testParseJSONFeedVersion1_0() throws {
        let jsonFeed = """
        {
            "version": "https://jsonfeed.org/version/1",
            "title": "Version 1.0 Feed",
            "items": [
                {
                    "id": "1",
                    "url": "https://example.org/item",
                    "title": "Test Item",
                    "author": {
                        "name": "John Doe",
                        "url": "https://example.org/johndoe"
                    }
                }
            ]
        }
        """

        let parser = JSONFeedParser()
        let success = try parser.parse(data: jsonFeed.data(using: .utf8)!)

        XCTAssertTrue(success)
        XCTAssertEqual(parser.feedTitle, "Version 1.0 Feed")
        XCTAssertEqual(parser.articles.count, 1)
        XCTAssertEqual(parser.articles[0].author, "John Doe")
    }

    // MARK: - Author Parsing Tests

    func testParseMultipleAuthors() throws {
        let jsonFeed = """
        {
            "version": "https://jsonfeed.org/version/1.1",
            "title": "Multi Author Feed",
            "items": [
                {
                    "id": "1",
                    "url": "https://example.org/item",
                    "title": "Collaborative Post",
                    "authors": [
                        {"name": "Alice"},
                        {"name": "Bob"},
                        {"name": "Charlie"}
                    ]
                }
            ]
        }
        """

        let parser = JSONFeedParser()
        let success = try parser.parse(data: jsonFeed.data(using: .utf8)!)

        XCTAssertTrue(success)
        // Should use first author
        XCTAssertEqual(parser.articles[0].author, "Alice")
    }

    // MARK: - Content Tests

    func testParseContentHtmlAndText() throws {
        let jsonFeed = """
        {
            "version": "https://jsonfeed.org/version/1.1",
            "title": "Content Test",
            "items": [
                {
                    "id": "1",
                    "url": "https://example.org/item",
                    "title": "Both Content Types",
                    "content_html": "<p><strong>Bold</strong> text</p>",
                    "content_text": "Bold text"
                }
            ]
        }
        """

        let parser = JSONFeedParser()
        let success = try parser.parse(data: jsonFeed.data(using: .utf8)!)

        XCTAssertTrue(success)
        let article = parser.articles[0]
        XCTAssertNotNil(article.contentEncoded)
        XCTAssertNotNil(article.content)
        XCTAssertTrue(article.contentEncoded!.contains("<strong>"))
    }

    func testParseSummary() throws {
        let jsonFeed = """
        {
            "version": "https://jsonfeed.org/version/1.1",
            "title": "Summary Test",
            "items": [
                {
                    "id": "1",
                    "url": "https://example.org/item",
                    "title": "Article with Summary",
                    "summary": "This is a brief summary of the article.",
                    "content_html": "<p>This is the full content of the article with much more detail.</p>"
                }
            ]
        }
        """

        let parser = JSONFeedParser()
        let success = try parser.parse(data: jsonFeed.data(using: .utf8)!)

        XCTAssertTrue(success)
        let article = parser.articles[0]
        XCTAssertEqual(article.description, "This is a brief summary of the article.")
    }

    // MARK: - External URL Tests

    func testParseExternalUrl() throws {
        let jsonFeed = """
        {
            "version": "https://jsonfeed.org/version/1.1",
            "title": "Link Blog",
            "items": [
                {
                    "id": "1",
                    "url": "https://example.org/posts/link-1",
                    "external_url": "https://external-site.com/interesting-article",
                    "title": "Interesting External Article"
                }
            ]
        }
        """

        let parser = JSONFeedParser()
        let success = try parser.parse(data: jsonFeed.data(using: .utf8)!)

        XCTAssertTrue(success)
        // Should use external_url as the link
        XCTAssertEqual(parser.articles[0].link, "https://external-site.com/interesting-article")
    }

    // MARK: - Image Tests

    func testParseImage() throws {
        let jsonFeed = """
        {
            "version": "https://jsonfeed.org/version/1.1",
            "title": "Image Test",
            "items": [
                {
                    "id": "1",
                    "url": "https://example.org/item",
                    "title": "Article with Image",
                    "image": "https://example.org/images/featured.jpg"
                }
            ]
        }
        """

        let parser = JSONFeedParser()
        let success = try parser.parse(data: jsonFeed.data(using: .utf8)!)

        XCTAssertTrue(success)
        XCTAssertEqual(parser.articles[0].imageUrl, "https://example.org/images/featured.jpg")
    }

    func testParseBannerImage() throws {
        let jsonFeed = """
        {
            "version": "https://jsonfeed.org/version/1.1",
            "title": "Banner Image Test",
            "items": [
                {
                    "id": "1",
                    "url": "https://example.org/item",
                    "title": "Article with Banner",
                    "banner_image": "https://example.org/images/banner.jpg"
                }
            ]
        }
        """

        let parser = JSONFeedParser()
        let success = try parser.parse(data: jsonFeed.data(using: .utf8)!)

        XCTAssertTrue(success)
        XCTAssertEqual(parser.articles[0].imageUrl, "https://example.org/images/banner.jpg")
    }

    func testExtractImageFromContentHtml() throws {
        let jsonFeed = """
        {
            "version": "https://jsonfeed.org/version/1.1",
            "title": "Embedded Image Test",
            "items": [
                {
                    "id": "1",
                    "url": "https://example.org/item",
                    "title": "Article with Embedded Image",
                    "content_html": "<p>Some text <img src='https://example.org/images/embedded.png' alt='test'/> more text</p>"
                }
            ]
        }
        """

        let parser = JSONFeedParser()
        let success = try parser.parse(data: jsonFeed.data(using: .utf8)!)

        XCTAssertTrue(success)
        XCTAssertEqual(parser.articles[0].imageUrl, "https://example.org/images/embedded.png")
    }

    // MARK: - Date Tests

    func testParseISO8601Date() throws {
        let jsonFeed = """
        {
            "version": "https://jsonfeed.org/version/1.1",
            "title": "Date Test",
            "items": [
                {
                    "id": "1",
                    "url": "https://example.org/item",
                    "title": "Dated Article",
                    "date_published": "2024-03-15T14:30:00Z"
                }
            ]
        }
        """

        let parser = JSONFeedParser()
        let success = try parser.parse(data: jsonFeed.data(using: .utf8)!)

        XCTAssertTrue(success)
        let article = parser.articles[0]
        XCTAssertNotNil(article.publishedDate)

        if let date = article.publishedDate {
            let calendar = Calendar.current
            let components = calendar.dateComponents(in: TimeZone(identifier: "UTC")!, from: date)
            XCTAssertEqual(components.year, 2024)
            XCTAssertEqual(components.month, 3)
            XCTAssertEqual(components.day, 15)
        }
    }

    func testParseDateModifiedFallback() throws {
        let jsonFeed = """
        {
            "version": "https://jsonfeed.org/version/1.1",
            "title": "Modified Date Test",
            "items": [
                {
                    "id": "1",
                    "url": "https://example.org/item",
                    "title": "Updated Article",
                    "date_modified": "2024-03-20T10:00:00Z"
                }
            ]
        }
        """

        let parser = JSONFeedParser()
        let success = try parser.parse(data: jsonFeed.data(using: .utf8)!)

        XCTAssertTrue(success)
        // Should fallback to date_modified when date_published is missing
        XCTAssertNotNil(parser.articles[0].publishedDate)
    }

    // MARK: - Edge Cases

    func testEmptyFeed() throws {
        let jsonFeed = """
        {
            "version": "https://jsonfeed.org/version/1.1",
            "title": "Empty Feed",
            "items": []
        }
        """

        let parser = JSONFeedParser()
        let success = try parser.parse(data: jsonFeed.data(using: .utf8)!)

        XCTAssertTrue(success)
        XCTAssertEqual(parser.feedTitle, "Empty Feed")
        XCTAssertEqual(parser.articles.count, 0)
    }

    func testFeedWithoutItems() throws {
        let jsonFeed = """
        {
            "version": "https://jsonfeed.org/version/1.1",
            "title": "No Items Feed"
        }
        """

        let parser = JSONFeedParser()
        let success = try parser.parse(data: jsonFeed.data(using: .utf8)!)

        XCTAssertTrue(success)
        XCTAssertEqual(parser.articles.count, 0)
    }

    func testInvalidJSON() throws {
        let badJSON = """
        { invalid json data
        """

        let parser = JSONFeedParser()
        let success = try parser.parse(data: badJSON.data(using: .utf8)!)

        XCTAssertFalse(success, "Parser should fail on invalid JSON")
    }

    func testNonJSONFeedJSON() throws {
        let notJSONFeed = """
        {
            "data": "This is valid JSON but not a JSON Feed"
        }
        """

        let parser = JSONFeedParser()
        let success = try parser.parse(data: notJSONFeed.data(using: .utf8)!)

        XCTAssertFalse(success, "Parser should fail on JSON that's not a JSON Feed")
    }

    func testItemWithMinimalFields() throws {
        let jsonFeed = """
        {
            "version": "https://jsonfeed.org/version/1.1",
            "title": "Minimal Item Feed",
            "items": [
                {
                    "id": "minimal-1",
                    "url": "https://example.org/minimal"
                }
            ]
        }
        """

        let parser = JSONFeedParser()
        let success = try parser.parse(data: jsonFeed.data(using: .utf8)!)

        XCTAssertTrue(success)
        XCTAssertEqual(parser.articles.count, 1)
        let article = parser.articles[0]
        XCTAssertEqual(article.guid, "minimal-1")
        XCTAssertEqual(article.link, "https://example.org/minimal")
        XCTAssertTrue(article.title.isEmpty)
        XCTAssertNil(article.author)
        XCTAssertNil(article.publishedDate)
    }

    func testItemIdFallbackToUrl() throws {
        let jsonFeed = """
        {
            "version": "https://jsonfeed.org/version/1.1",
            "title": "Missing ID Feed",
            "items": [
                {
                    "url": "https://example.org/no-id-item",
                    "title": "Item Without ID"
                }
            ]
        }
        """

        let parser = JSONFeedParser()
        let success = try parser.parse(data: jsonFeed.data(using: .utf8)!)

        XCTAssertTrue(success)
        XCTAssertEqual(parser.articles.count, 1)
        // Should use URL as guid fallback
        XCTAssertEqual(parser.articles[0].guid, "https://example.org/no-id-item")
    }

    // MARK: - HTML Entity Tests

    func testHTMLEntitiesInTitle() throws {
        let jsonFeed = """
        {
            "version": "https://jsonfeed.org/version/1.1",
            "title": "Entity Test",
            "items": [
                {
                    "id": "1",
                    "url": "https://example.org/item",
                    "title": "Article &amp; Title with &lt;special&gt; chars"
                }
            ]
        }
        """

        let parser = JSONFeedParser()
        let success = try parser.parse(data: jsonFeed.data(using: .utf8)!)

        XCTAssertTrue(success)
        XCTAssertEqual(parser.articles[0].title, "Article & Title with <special> chars")
    }

    // MARK: - Whitespace Normalization Tests

    func testWhitespaceNormalization() throws {
        let jsonFeed = """
        {
            "version": "https://jsonfeed.org/version/1.1",
            "title": "Whitespace   Test",
            "items": [
                {
                    "id": "1",
                    "url": "https://example.org/item",
                    "title": "Title  with   multiple    spaces\\nand\\nnewlines"
                }
            ]
        }
        """

        let parser = JSONFeedParser()
        let success = try parser.parse(data: jsonFeed.data(using: .utf8)!)

        XCTAssertTrue(success)
        XCTAssertEqual(parser.feedTitle, "Whitespace Test")
        // Note: Swift string escaping means \n becomes literal newline in JSON
    }

    // MARK: - Real-World Feed Structure Tests
    
    func testMantonOrgStyleFeed() throws {
        // Simulating the structure of manton.org's JSON Feed
        let jsonFeed = """
        {
            "version": "https://jsonfeed.org/version/1.1",
            "title": "Manton Reece",
            "home_page_url": "https://www.manton.org/",
            "feed_url": "https://www.manton.org/feed.json",
            "authors": [
                {
                    "name": "Manton Reece",
                    "url": "https://www.manton.org/"
                }
            ],
            "items": [
                {
                    "id": "https://www.manton.org/2024/01/15/post.html",
                    "url": "https://www.manton.org/2024/01/15/post.html",
                    "content_html": "<p>This is a microblog post.</p>",
                    "date_published": "2024-01-15T10:00:00-06:00"
                }
            ]
        }
        """

        let parser = JSONFeedParser()
        let success = try parser.parse(data: jsonFeed.data(using: .utf8)!)

        XCTAssertTrue(success)
        XCTAssertEqual(parser.feedTitle, "Manton Reece")
        XCTAssertEqual(parser.articles.count, 1)
    }

    func testDaringFireballStyleFeed() throws {
        // Simulating Daring Fireball's JSON Feed structure (link blog style)
        let jsonFeed = """
        {
            "version": "https://jsonfeed.org/version/1.1",
            "title": "Daring Fireball",
            "home_page_url": "https://daringfireball.net/",
            "feed_url": "https://daringfireball.net/feeds/json",
            "items": [
                {
                    "id": "https://daringfireball.net/linked/2024/01/15/link-post",
                    "url": "https://daringfireball.net/linked/2024/01/15/link-post",
                    "external_url": "https://external-site.com/article",
                    "title": "Linked Post Title",
                    "content_html": "<p>Commentary about the linked article.</p>",
                    "date_published": "2024-01-15T14:30:00Z",
                    "authors": [
                        {"name": "John Gruber"}
                    ]
                }
            ]
        }
        """

        let parser = JSONFeedParser()
        let success = try parser.parse(data: jsonFeed.data(using: .utf8)!)

        XCTAssertTrue(success)
        XCTAssertEqual(parser.feedTitle, "Daring Fireball")
        XCTAssertEqual(parser.articles.count, 1)
        
        let article = parser.articles[0]
        XCTAssertEqual(article.title, "Linked Post Title")
        // Should use external_url as the link
        XCTAssertEqual(article.link, "https://external-site.com/article")
        XCTAssertEqual(article.author, "John Gruber")
    }

    func testHackerNewsRSSJSONFeed() throws {
        // Simulating hnrss.org's JSON Feed structure
        let jsonFeed = """
        {
            "version": "https://jsonfeed.org/version/1.1",
            "title": "Hacker News: Newest",
            "home_page_url": "https://news.ycombinator.com/newest",
            "feed_url": "https://hnrss.org/newest.jsonfeed",
            "items": [
                {
                    "id": "hn-12345678",
                    "url": "https://news.ycombinator.com/item?id=12345678",
                    "external_url": "https://example.com/tech-article",
                    "title": "Show HN: Cool Tech Project",
                    "content_html": "<p>Points: 42 | Comments: 15</p>",
                    "date_published": "2024-01-15T16:00:00Z"
                }
            ]
        }
        """

        let parser = JSONFeedParser()
        let success = try parser.parse(data: jsonFeed.data(using: .utf8)!)

        XCTAssertTrue(success)
        XCTAssertEqual(parser.feedTitle, "Hacker News: Newest")
        XCTAssertEqual(parser.articles.count, 1)
        XCTAssertEqual(parser.articles[0].link, "https://example.com/tech-article")
    }
}
