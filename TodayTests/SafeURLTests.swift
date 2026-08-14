//
//  SafeURLTests.swift
//  TodayTests
//
//  Pins the URL scheme allow-list (U3).
//
//  Feed content controls `article.link`, Reddit hrefs, OPML `xmlUrl` and ID3 chapter URLs, and
//  all of them used to reach `openURL` / `NSWorkspace.open` / `webView.load` unchecked.
//  `URL(string:)` accepts `file:`, `data:`, `javascript:` and `ftp:` quite happily, so the
//  rejections below are the whole point of the utility.
//

import XCTest
@testable import Today

final class SafeURLTests: XCTestCase {

    // MARK: - webOpenable(String)

    func testHTTPSURLPasses() {
        XCTAssertEqual(
            SafeURL.webOpenable("https://example.com/feed")?.absoluteString,
            "https://example.com/feed"
        )
    }

    func testHTTPURLPasses() {
        XCTAssertEqual(
            SafeURL.webOpenable("http://example.com/feed")?.absoluteString,
            "http://example.com/feed"
        )
    }

    func testHTTPOnlyDomainOverPlainHTTPPasses() {
        // These domains have ATS exceptions precisely because they cannot do HTTPS, so the
        // allow-list must not break them.
        for host in FeedURLNormalizer.httpOnlyDomains {
            XCTAssertNotNil(
                SafeURL.webOpenable("http://\(host)/rss.xml"),
                "\(host) must remain openable over plain http"
            )
        }
    }

    func testUppercaseSchemeIsAccepted() {
        XCTAssertNotNil(SafeURL.webOpenable("HTTP://example.com"))
        XCTAssertNotNil(SafeURL.webOpenable("HTTPS://example.com"))
        XCTAssertNotNil(SafeURL.webOpenable("HtTpS://example.com"))
    }

    func testEmptyAndWhitespaceStringsAreRejected() {
        XCTAssertNil(SafeURL.webOpenable(""))
        XCTAssertNil(SafeURL.webOpenable("   "))
        XCTAssertNil(SafeURL.webOpenable("\n"))
        XCTAssertNil(SafeURL.webOpenable(nil as String?))
    }

    func testMissingSchemeIsRejected() {
        // `URL(string:)` returns a perfectly good relative URL for these; without a scheme
        // there is nothing to allow-list, so they are refused.
        XCTAssertNil(SafeURL.webOpenable("example.com/feed"))
        XCTAssertNil(SafeURL.webOpenable("/etc/passwd"))
        XCTAssertNil(SafeURL.webOpenable("//example.com/feed"))
    }

    func testDisallowedSchemesAreRejected() {
        let hostile = [
            "file:///etc/passwd",
            "file://localhost/etc/passwd",
            "FILE:///etc/passwd",
            "data:text/html;base64,PHNjcmlwdD5hbGVydCgxKTwvc2NyaXB0Pg==",
            "javascript:alert(document.cookie)",
            "JavaScript:alert(1)",
            "ftp://example.com/payload",
            "tel:+15551234567",
            "facetime:user@example.com",
            "sms:+15551234567",
            "mailto:someone@example.com",
            "today://open?feed=1",
            "itms-apps://apps.apple.com/app/id1"
        ]
        for candidate in hostile {
            XCTAssertNil(SafeURL.webOpenable(candidate), "\(candidate) must not be openable")
        }
    }

    // MARK: - webOpenable(URL)

    func testURLOverloadMirrorsTheStringOverload() {
        XCTAssertNotNil(SafeURL.webOpenable(URL(string: "https://example.com")))
        XCTAssertNil(SafeURL.webOpenable(URL(string: "file:///etc/passwd")))
        XCTAssertNil(SafeURL.webOpenable(nil as URL?))
    }

    func testIsAllowedMatchesWebOpenable() {
        XCTAssertTrue(SafeURL.isAllowed(URL(string: "https://example.com")!))
        XCTAssertFalse(SafeURL.isAllowed(URL(string: "file:///etc/passwd")!))
    }

    // MARK: - feedIngestable

    func testFeedIngestableCanonicalisesAllowedURLs() {
        // Same transforms as FeedURLNormalizer.canonical: scheme upgrade + Reddit .json.
        XCTAssertEqual(SafeURL.feedIngestable("http://example.com/feed"), "https://example.com/feed")
        XCTAssertEqual(
            SafeURL.feedIngestable("https://www.reddit.com/r/swift"),
            "https://www.reddit.com/r/swift.json"
        )
        XCTAssertEqual(
            SafeURL.feedIngestable("  https://example.com/feed  "),
            "https://example.com/feed"
        )
    }

    func testFeedIngestablePreservesHTTPOnlyDomains() {
        XCTAssertEqual(
            SafeURL.feedIngestable("http://scripting.com/rss.xml"),
            "http://scripting.com/rss.xml"
        )
    }

    func testFeedIngestableRejectsDisallowedSchemes() {
        XCTAssertNil(SafeURL.feedIngestable("file:///etc/passwd"))
        XCTAssertNil(SafeURL.feedIngestable("data:text/xml,<opml/>"))
        XCTAssertNil(SafeURL.feedIngestable("javascript:alert(1)"))
        XCTAssertNil(SafeURL.feedIngestable("ftp://example.com/feed.xml"))
        XCTAssertNil(SafeURL.feedIngestable(""))
        XCTAssertNil(SafeURL.feedIngestable("example.com/feed"))
    }

    // MARK: - Article.articleURL gate

    func testArticleURLIsNilForDisallowedSchemes() {
        let article = Article(
            title: "Hostile",
            link: "file:///etc/passwd",
            articleDescription: nil,
            publishedDate: Date(),
            author: nil,
            guid: "1"
        )
        XCTAssertNil(article.articleURL)
    }

    func testArticleURLPassesThroughHTTPS() {
        let article = Article(
            title: "Fine",
            link: "https://example.com/post",
            articleDescription: nil,
            publishedDate: Date(),
            author: nil,
            guid: "2"
        )
        XCTAssertEqual(article.articleURL?.absoluteString, "https://example.com/post")
    }

    func testArticleURLIsNilForEmptyLink() {
        let article = Article(
            title: "Empty",
            link: "",
            articleDescription: nil,
            publishedDate: Date(),
            author: nil,
            guid: "3"
        )
        XCTAssertNil(article.articleURL)
    }
}
