//
//  ArticleDerivedFieldsTests.swift
//  TodayTests
//
//  Characterization tests for Article's derived content fields.
//
//  Written BEFORE moving where hasMinimalContent is computed (U6). The classification has
//  subtle behaviour — a 300-character threshold applied to HTML-stripped text, an early
//  return when both content fields are nil, and a concatenation fallback — that is easy to
//  alter by accident. These pin the current answers so the refactor can be checked against
//  them rather than trusted.
//

import XCTest
import SwiftData
@testable import Today

final class ArticleDerivedFieldsTests: XCTestCase {

    private func makeArticle(
        description: String? = nil,
        content: String? = nil,
        contentEncoded: String? = nil
    ) -> Article {
        Article(
            title: "Title",
            link: "https://example.com/1",
            articleDescription: description,
            content: content,
            contentEncoded: contentEncoded,
            publishedDate: Date(),
            guid: "guid-1"
        )
    }

    /// Plain text of a given stripped length, with no HTML.
    private func plainText(count: Int) -> String {
        String(repeating: "a", count: count)
    }

    // MARK: - The nil case

    func testNoContentAndNoEncodedIsMinimal() {
        XCTAssertTrue(makeArticle().hasMinimalContent)
        XCTAssertTrue(makeArticle(description: "short summary").hasMinimalContent)
    }

    func testNoContentAndNoEncodedIsMinimalEvenWithALongDescription() {
        // The nil-nil early return fires before the concatenation check, so a long
        // description alone does NOT make an article non-minimal.
        let article = makeArticle(description: plainText(count: 5_000))
        XCTAssertTrue(
            article.hasMinimalContent,
            "the contentEncoded == nil && content == nil early return takes precedence"
        )
    }

    // MARK: - The 300-character boundary

    func testContentExactlyAtThresholdIsMinimal() {
        // The check is `> 300`, so exactly 300 does not clear it; it then falls through to
        // the concatenation check, which is `< 300` — so 300 is NOT minimal there.
        let article = makeArticle(content: plainText(count: 300))
        XCTAssertFalse(
            article.hasMinimalContent,
            "300 chars fails the > 300 test but also fails the < 300 test"
        )
    }

    func testContentJustBelowThresholdIsMinimal() {
        XCTAssertTrue(makeArticle(content: plainText(count: 299)).hasMinimalContent)
    }

    func testContentJustAboveThresholdIsNotMinimal() {
        XCTAssertFalse(makeArticle(content: plainText(count: 301)).hasMinimalContent)
    }

    func testContentEncodedJustAboveThresholdIsNotMinimal() {
        XCTAssertFalse(makeArticle(contentEncoded: plainText(count: 301)).hasMinimalContent)
    }

    // MARK: - Concatenation fallback

    func testShortFieldsThatSumOverThresholdAreNotMinimal() {
        // Neither field alone exceeds 300, but the joined length does.
        let article = makeArticle(
            description: plainText(count: 150),
            content: plainText(count: 200)
        )
        XCTAssertFalse(
            article.hasMinimalContent,
            "concatenation of contentEncoded + content + description decides the fallback"
        )
    }

    func testShortFieldsThatSumUnderThresholdAreMinimal() {
        let article = makeArticle(
            description: plainText(count: 50),
            content: plainText(count: 100)
        )
        XCTAssertTrue(article.hasMinimalContent)
    }

    // MARK: - HTML is stripped before measuring

    func testMarkupDoesNotCountTowardsTheThreshold() {
        // Long markup wrapping short text must still read as minimal — length is measured
        // after stripping, not before.
        let inner = plainText(count: 50)
        // Enough nested markup that the source comfortably exceeds the threshold while the
        // stripped text stays at 50 characters.
        let wrapper = String(repeating: "<span class=\"decorative-wrapper\">", count: 10)
        let closing = String(repeating: "</span>", count: 10)
        let markup = "<div class=\"a\"><p>\(wrapper)\(inner)\(closing)</p></div>"
        XCTAssertGreaterThan(markup.count, 300, "fixture must actually exceed the threshold")

        let article = makeArticle(content: markup)
        XCTAssertTrue(
            article.hasMinimalContent,
            "the threshold applies to stripped text, so markup must not inflate it"
        )
    }

    func testEntitiesAreDecodedBeforeMeasuring() {
        // &amp; is 5 characters of source for 1 character of text.
        let source = String(repeating: "&amp;", count: 100) // 500 source chars -> 100 text
        let article = makeArticle(content: source)
        XCTAssertGreaterThan(source.count, 300)
        XCTAssertTrue(
            article.hasMinimalContent,
            "entity decoding happens before the length check"
        )
    }

    // MARK: - plainTextDescription is precomputed at init

    func testPlainTextDescriptionIsPopulatedAtInit() {
        let article = makeArticle(description: "<p>Hello &amp; goodbye</p>")
        XCTAssertEqual(article.plainTextDescription, "Hello & goodbye")
    }

    func testPlainTextDescriptionIsNilWhenThereIsNoDescription() {
        XCTAssertNil(makeArticle().plainTextDescription)
    }

    func testPlainTextDescriptionMatchesHtmlToPlainText() {
        let html = "<div>Some <b>bold</b> text with &#8220;quotes&#8221;</div>"
        let article = makeArticle(description: html)
        XCTAssertEqual(article.plainTextDescription, html.htmlToPlainText)
    }

    // MARK: - The cached flag must agree with the computation

    func testIsMinimalContentCachedIsPopulatedAtInit() {
        XCTAssertNotNil(makeArticle(content: plainText(count: 400)).isMinimalContentCached)
        XCTAssertNotNil(makeArticle().isMinimalContentCached)
    }

    /// The whole point of U6: reading the stored flag must give the same answer as computing
    /// it. Swept across the cases the characterization tests above cover.
    func testCachedFlagAgreesWithComputationAcrossCases() {
        let cases: [(String, Article)] = [
            ("no content", makeArticle()),
            ("short description only", makeArticle(description: plainText(count: 10))),
            ("long description only", makeArticle(description: plainText(count: 5_000))),
            ("content at threshold", makeArticle(content: plainText(count: 300))),
            ("content below threshold", makeArticle(content: plainText(count: 299))),
            ("content above threshold", makeArticle(content: plainText(count: 301))),
            ("encoded above threshold", makeArticle(contentEncoded: plainText(count: 301))),
            ("summing over threshold", makeArticle(
                description: plainText(count: 150), content: plainText(count: 200))),
            ("summing under threshold", makeArticle(
                description: plainText(count: 50), content: plainText(count: 100))),
            ("markup heavy", makeArticle(content: "<p><b>\(plainText(count: 20))</b></p>")),
        ]

        for (label, article) in cases {
            let computed = Article.computeIsMinimalContent(
                contentEncoded: article.contentEncoded,
                content: article.content,
                articleDescription: article.articleDescription
            )
            XCTAssertEqual(article.isMinimalContentCached, computed, "cache mismatch: \(label)")
            XCTAssertEqual(article.hasMinimalContent, computed, "accessor mismatch: \(label)")
        }
    }

    /// Articles predating the cache read as nil and must fall back to computing, not to a
    /// default. A wrong default would silently change which articles open in the web view.
    func testAccessorFallsBackToComputationWhenCacheIsNil() {
        let article = makeArticle(content: plainText(count: 301))
        article.isMinimalContentCached = nil

        XCTAssertFalse(
            article.hasMinimalContent,
            "with no cached value the accessor must compute, not assume"
        )

        let minimal = makeArticle(description: "short")
        minimal.isMinimalContentCached = nil
        XCTAssertTrue(minimal.hasMinimalContent)
    }

    func testCachedValueIsPreferredOverRecomputation() {
        // Deliberately poison the cache: the accessor must trust it rather than recompute,
        // which is what makes the row view cheap.
        let article = makeArticle(content: plainText(count: 301)) // computes to false
        article.isMinimalContentCached = true
        XCTAssertTrue(article.hasMinimalContent)
    }

    // MARK: - Backfill

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Feed.self, Article.self, OPMLSubscription.self])
        return try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
    }

    func testBackfillPopulatesMissingDerivedFieldsAndTerminates() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        // Enough rows to span more than one batch, mixed so both passes have work.
        for index in 0..<1_100 {
            let article = Article(
                title: "A\(index)",
                link: "https://example.com/\(index)",
                articleDescription: index % 3 == 0 ? nil : "<p>Body &amp; text \(index)</p>",
                content: index % 5 == 0 ? plainText(count: 400) : nil,
                publishedDate: Date(),
                guid: "guid-\(index)"
            )
            // Simulate rows written before the derived fields existed.
            article.plainTextDescription = nil
            article.isMinimalContentCached = nil
            context.insert(article)
        }
        try context.save()

        // Fresh key so the guard does not short-circuit.
        let key = "hasCompletedDerivedArticleFieldsBackfill_v1"
        UserDefaults.standard.removeObject(forKey: key)
        defer { UserDefaults.standard.removeObject(forKey: key) }

        await DatabaseMigration.shared.backfillDerivedArticleFields(container: container)

        let verifyContext = ModelContext(container)
        let all = try verifyContext.fetch(FetchDescriptor<Article>())
        XCTAssertEqual(all.count, 1_100)

        // Every article has the flag; only those with a description have plain text.
        XCTAssertTrue(
            all.allSatisfy { $0.isMinimalContentCached != nil },
            "the minimal-content flag must be set on every article"
        )
        for article in all {
            if article.articleDescription != nil {
                XCTAssertNotNil(article.plainTextDescription, "\(article.guid) missing plain text")
            } else {
                XCTAssertNil(article.plainTextDescription)
            }
        }

        // And the values must match the computation, not just be non-nil.
        for article in all {
            XCTAssertEqual(
                article.isMinimalContentCached,
                Article.computeIsMinimalContent(
                    contentEncoded: article.contentEncoded,
                    content: article.content,
                    articleDescription: article.articleDescription
                ),
                "backfilled flag disagrees with computation for \(article.guid)"
            )
        }
    }

    func testBackfillIsANoOpOnceComplete() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let article = Article(
            title: "A", link: "https://example.com/a",
            articleDescription: "<p>text</p>", publishedDate: Date(), guid: "g"
        )
        article.plainTextDescription = nil
        article.isMinimalContentCached = nil
        context.insert(article)
        try context.save()

        let key = "hasCompletedDerivedArticleFieldsBackfill_v1"
        UserDefaults.standard.set(true, forKey: key)
        defer { UserDefaults.standard.removeObject(forKey: key) }

        await DatabaseMigration.shared.backfillDerivedArticleFields(container: container)

        let verify = try ModelContext(container).fetch(FetchDescriptor<Article>()).first
        XCTAssertNil(
            verify?.plainTextDescription,
            "with the completion flag set the backfill must not touch anything"
        )
    }

    func testBackfillOnAnEmptyStoreCompletesWithoutError() async throws {
        let container = try makeContainer()
        let key = "hasCompletedDerivedArticleFieldsBackfill_v1"
        UserDefaults.standard.removeObject(forKey: key)
        defer { UserDefaults.standard.removeObject(forKey: key) }

        await DatabaseMigration.shared.backfillDerivedArticleFields(container: container)

        XCTAssertTrue(
            UserDefaults.standard.bool(forKey: key),
            "an empty store should mark the backfill complete rather than retry forever"
        )
    }

    // MARK: - Reddit and podcast flags (cheap, but adjacent in the row view)

    func testIsRedditPostRequiresRedditMetadata() {
        XCTAssertFalse(makeArticle().isRedditPost)

        let reddit = Article(
            title: "T", link: "https://example.com/r", publishedDate: Date(),
            guid: "g", redditSubreddit: "baseball"
        )
        XCTAssertTrue(reddit.isRedditPost)
    }

    func testHasPodcastAudioRequiresAnAudioURL() {
        XCTAssertFalse(makeArticle().hasPodcastAudio)

        let podcast = Article(
            title: "T", link: "https://example.com/p", publishedDate: Date(),
            guid: "g", audioUrl: "https://example.com/a.mp3"
        )
        XCTAssertTrue(podcast.hasPodcastAudio)
    }
}
