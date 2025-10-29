//
//  RedditRSSTests.swift
//  TodayTests
//
//  Tests for Reddit RSS feed parsing and metadata extraction
//

import XCTest
@testable import Today

final class RedditRSSTests: XCTestCase {

    // MARK: - Reddit Feed Detection Tests
    
    func testRedditFeedDetection() {
        let redditRSSXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <feed xmlns="http://www.w3.org/2005/Atom">
            <title>/r/baseball</title>
            <link href="https://www.reddit.com/r/baseball" />
            <entry>
                <title>Yankees win the World Series!</title>
                <link href="https://www.reddit.com/r/baseball/comments/abc123/yankees_win_the_world_series/" />
                <id>t3_abc123</id>
                <updated>2023-10-23T10:00:00Z</updated>
                <author><name>/u/baseballfan123</name></author>
                <content type="html">
                    &lt;!-- SC_OFF --&gt;&lt;div class="md"&gt;&lt;p&gt;What an amazing game!&lt;/p&gt;
                    &lt;p&gt;&lt;a href="https://www.reddit.com/r/baseball/comments/abc123/yankees_win_the_world_series/"&gt;[comments]&lt;/a&gt;&lt;/p&gt;
                    &lt;/div&gt;&lt;!-- SC_ON --&gt;
                </content>
            </entry>
        </feed>
        """

        let parser = RSSParser()
        let data = redditRSSXML.data(using: .utf8)!
        let success = parser.parse(data: data)

        XCTAssertTrue(success, "Parser should successfully parse Reddit RSS feed")
        XCTAssertEqual(parser.articles.count, 1)

        let article = parser.articles[0]
        
        // Verify Reddit metadata was extracted
        XCTAssertNotNil(article.redditSubreddit, "Reddit subreddit should be extracted")
        XCTAssertEqual(article.redditSubreddit, "baseball", "Subreddit should be 'baseball'")
        
        XCTAssertNotNil(article.redditCommentsUrl, "Reddit comments URL should be extracted")
        XCTAssertEqual(article.redditCommentsUrl, "https://www.reddit.com/r/baseball/comments/abc123/yankees_win_the_world_series/")
        
        XCTAssertNotNil(article.redditPostId, "Reddit post ID should be extracted")
        XCTAssertEqual(article.redditPostId, "t3_abc123")
    }
    
    func testRedditSubredditExtraction() {
        let redditRSSXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <feed xmlns="http://www.w3.org/2005/Atom">
            <title>/r/technology</title>
            <entry>
                <title>New AI breakthrough</title>
                <link href="https://www.reddit.com/r/technology/comments/xyz789/new_ai_breakthrough/" />
                <id>t3_xyz789</id>
                <updated>2023-10-24T10:00:00Z</updated>
            </entry>
        </feed>
        """

        let parser = RSSParser()
        let success = parser.parse(data: redditRSSXML.data(using: .utf8)!)

        XCTAssertTrue(success)
        XCTAssertEqual(parser.articles.count, 1)
        
        let article = parser.articles[0]
        XCTAssertEqual(article.redditSubreddit, "technology")
    }
    
    func testNonRedditFeedHasNoMetadata() {
        let regularRSSXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0">
            <channel>
                <title>Regular Feed</title>
                <item>
                    <title>Regular Article</title>
                    <link>https://example.com/article</link>
                    <guid>article-1</guid>
                </item>
            </channel>
        </rss>
        """

        let parser = RSSParser()
        let success = parser.parse(data: regularRSSXML.data(using: .utf8)!)

        XCTAssertTrue(success)
        XCTAssertEqual(parser.articles.count, 1)
        
        let article = parser.articles[0]
        
        // Non-Reddit feeds should have no Reddit metadata
        XCTAssertNil(article.redditSubreddit)
        XCTAssertNil(article.redditCommentsUrl)
        XCTAssertNil(article.redditPostId)
    }
    
    func testMultipleRedditPosts() {
        let redditRSSXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <feed xmlns="http://www.w3.org/2005/Atom">
            <title>/r/programming</title>
            <entry>
                <title>First Post</title>
                <link href="https://www.reddit.com/r/programming/comments/aaa111/first_post/" />
                <id>t3_aaa111</id>
            </entry>
            <entry>
                <title>Second Post</title>
                <link href="https://www.reddit.com/r/programming/comments/bbb222/second_post/" />
                <id>t3_bbb222</id>
            </entry>
            <entry>
                <title>Third Post</title>
                <link href="https://www.reddit.com/r/programming/comments/ccc333/third_post/" />
                <id>t3_ccc333</id>
            </entry>
        </feed>
        """

        let parser = RSSParser()
        let success = parser.parse(data: redditRSSXML.data(using: .utf8)!)

        XCTAssertTrue(success)
        XCTAssertEqual(parser.articles.count, 3)
        
        // Verify all posts have Reddit metadata
        for article in parser.articles {
            XCTAssertEqual(article.redditSubreddit, "programming")
            XCTAssertNotNil(article.redditCommentsUrl)
            XCTAssertNotNil(article.redditPostId)
            XCTAssertTrue(article.redditPostId!.hasPrefix("t3_"))
        }
    }
    
    func testRedditPostIdExtractionFromLink() {
        let redditRSSXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <feed xmlns="http://www.w3.org/2005/Atom">
            <title>/r/test</title>
            <entry>
                <title>Test Post</title>
                <link href="https://www.reddit.com/r/test/comments/def456/test_post/" />
                <id>simple_id</id>
            </entry>
        </feed>
        """

        let parser = RSSParser()
        let success = parser.parse(data: redditRSSXML.data(using: .utf8)!)

        XCTAssertTrue(success)
        XCTAssertEqual(parser.articles.count, 1)
        
        let article = parser.articles[0]
        
        // Even if the id doesn't contain t3_, we should extract post ID from link
        XCTAssertNotNil(article.redditPostId)
        XCTAssertEqual(article.redditPostId, "t3_def456")
    }
}
