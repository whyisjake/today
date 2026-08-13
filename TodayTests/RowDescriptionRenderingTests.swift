//
//  RowDescriptionRenderingTests.swift
//  TodayTests
//
//  U15: article descriptions must never be rendered through the WebKit HTML importer
//  (`NSAttributedString(documentType: .html)`).
//
//  Two defects motivated the change. The importer runs a full WebKit parse on the main
//  actor, and — the security half — it synchronously fetches externally referenced
//  subresources. A feed description containing `<img src="http://tracker/beacon">` therefore
//  turned a render into an outbound request from the reader's device: a read receipt, an IP
//  leak, and a request to an arbitrary host chosen by feed content.
//
//  These tests render the real views (`ArticleRowView`, `ArticleDetailView`) through
//  `ImageRenderer` with a URLProtocol installed that records every request the process
//  makes, and assert the recorder stays empty. The recorder is proved live by a control
//  test that issues one real request and sees it recorded, so an empty count means "no
//  request happened", not "the recorder was never wired up".
//

import XCTest
import SwiftUI
@testable import Today

/// Records every URL the process tries to load, and fails the load.
///
/// Registered globally with `URLProtocol.registerClass`, which puts it in front of
/// `URLSession.shared` and the legacy NSURLConnection-style loading the HTML importer uses
/// for subresources — the exact path the beacon would travel.
final class RecordingURLProtocol: URLProtocol {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var recorded: [URL] = []

    static func reset() {
        lock.lock()
        recorded = []
        lock.unlock()
    }

    static func recordedURLs() -> [URL] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    override class func canInit(with request: URLRequest) -> Bool {
        if let url = request.url {
            lock.lock()
            recorded.append(url)
            lock.unlock()
        }
        return true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
    }

    override func stopLoading() {}
}

@MainActor
final class RowDescriptionRenderingTests: XCTestCase {

    /// A description that would make the WebKit importer reach out to the network.
    private let beaconDescription = """
    <p>Story summary.</p><img src="http://tracker.example/beacon?u=1">
    """

    override func setUp() {
        super.setUp()
        RecordingURLProtocol.reset()
        URLProtocol.registerClass(RecordingURLProtocol.self)
    }

    override func tearDown() {
        URLProtocol.unregisterClass(RecordingURLProtocol.self)
        RecordingURLProtocol.reset()
        super.tearDown()
    }

    private func makeArticle(description: String?, cachePlainText: Bool = true) -> Article {
        let article = Article(
            title: "Headline",
            link: "https://example.com/1",
            articleDescription: description,
            publishedDate: Date(),
            guid: "guid-1"
        )
        if !cachePlainText {
            // Model an article written before `plainTextDescription` existed and not yet
            // backfilled by DatabaseMigration.
            article.plainTextDescription = nil
        }
        return article
    }

    /// Force a full render of a view, the way scrolling would.
    private func render(_ view: some View) {
        let renderer = ImageRenderer(content: view.frame(width: 320, height: 200))
        #if os(macOS)
        XCTAssertNotNil(renderer.nsImage, "View failed to render")
        #else
        XCTAssertNotNil(renderer.uiImage, "View failed to render")
        #endif
    }

    // MARK: - The recorder actually records (control)

    /// Without this, "zero requests observed" could just mean the recorder was never in the
    /// loading path. One real request must show up.
    func testRecorderObservesARealRequest() {
        let expectation = expectation(description: "request finished")
        let url = URL(string: "http://tracker.example/control")!
        URLSession.shared.dataTask(with: url) { _, _, _ in
            expectation.fulfill()
        }.resume()
        wait(for: [expectation], timeout: 10)

        XCTAssertTrue(
            RecordingURLProtocol.recordedURLs().contains { $0.absoluteString.contains("tracker.example") },
            "The recorder must see a genuine request, otherwise the no-request assertions prove nothing"
        )
    }

    // MARK: - Error path: no network request during rendering

    func testRowRenderIssuesNoNetworkRequestForBeaconDescription() {
        let article = makeArticle(description: beaconDescription)

        render(ArticleRowView(article: article, fontOption: .serif))

        XCTAssertEqual(
            RecordingURLProtocol.recordedURLs(), [],
            "Rendering a row must not fetch anything referenced by feed HTML"
        )
    }

    func testDetailRenderIssuesNoNetworkRequestForBeaconDescription() {
        let article = makeArticle(description: beaconDescription)

        render(ArticleDetailView(article: article))

        XCTAssertEqual(
            RecordingURLProtocol.recordedURLs(), [],
            "Rendering the description must not fetch anything referenced by feed HTML"
        )
    }

    func testRowRenderWithUncachedBeaconDescriptionIssuesNoNetworkRequest() {
        // The fallback path (`articleDescription?.htmlToPlainText`) must be just as inert.
        let article = makeArticle(description: beaconDescription, cachePlainText: false)

        render(ArticleRowView(article: article, fontOption: .serif))

        XCTAssertEqual(RecordingURLProtocol.recordedURLs(), [])
    }

    // MARK: - Happy path: the text a row shows

    func testFormattedDescriptionBecomesReadablePlainText() {
        let html = "<p>An <em>emphatic</em> &amp; <strong>bold</strong> take&#8230;</p>"
        let article = makeArticle(description: html)

        let shown = article.plainTextDescription ?? article.articleDescription?.htmlToPlainText

        XCTAssertEqual(shown, "An emphatic & bold take\u{2026}")
        XCTAssertFalse(shown?.contains("<") ?? true, "No markup should survive into the row")

        render(ArticleRowView(article: article, fontOption: .serif))
        XCTAssertEqual(RecordingURLProtocol.recordedURLs(), [])
    }

    // MARK: - Edge case: older row with no cached plain text

    func testNilPlainTextDescriptionFallsBackToStrippingOnDemand() {
        let html = "<p>An <em>emphatic</em> take</p>"
        let article = makeArticle(description: html, cachePlainText: false)

        XCTAssertNil(article.plainTextDescription)

        let shown = article.plainTextDescription ?? article.articleDescription?.htmlToPlainText
        XCTAssertEqual(shown, "An emphatic take")

        render(ArticleRowView(article: article, fontOption: .serif))
        XCTAssertEqual(RecordingURLProtocol.recordedURLs(), [])
    }

    func testNilDescriptionRendersWithoutText() {
        let article = makeArticle(description: nil)

        XCTAssertNil(article.plainTextDescription)
        render(ArticleRowView(article: article, fontOption: .serif))

        XCTAssertEqual(RecordingURLProtocol.recordedURLs(), [])
    }
}
