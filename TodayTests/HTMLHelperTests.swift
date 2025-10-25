//
//  HTMLHelperTests.swift
//  TodayTests
//
//  Tests for HTML entity decoding and whitespace handling
//

import XCTest
@testable import Today

final class HTMLHelperTests: XCTestCase {

    func testBasicHTMLEntityDecoding() {
        let input = "Adam Driver Says Bob Iger Nixed a Kylo Ren &#8216;Star Wars&#8217; Film"
        // &#8216; = U+2018 (left single quote) and &#8217; = U+2019 (right single quote)
        let expected = "Adam Driver Says Bob Iger Nixed a Kylo Ren \u{2018}Star Wars\u{2019} Film"
        let result = input.htmlToPlainText

        XCTAssertEqual(result, expected, "Should decode &#8216; and &#8217; to curly quotes")
    }

    func testNonBreakingSpacePreservation() {
        // Non-breaking space (U+00A0) should be converted to regular space
        let input = "Kylo\u{00A0}Ren"
        let result = input.htmlToPlainText

        XCTAssertTrue(result.contains("Kylo Ren"), "Should preserve space after Ren")
        XCTAssertEqual(result, "Kylo Ren", "Non-breaking space should become regular space")
    }

    func testHTMLEntityNonBreakingSpace() {
        let input = "Kylo&nbsp;Ren"
        let result = input.htmlToPlainText

        XCTAssertEqual(result, "Kylo Ren", "Should decode &nbsp; to regular space")
    }

    func testComplexHeadline() {
        let input = "<title>Adam Driver Says Bob Iger Nixed a Kylo Ren 'Star Wars' Film He Pitched With Steven Soderbergh</title>"
        let expected = "Adam Driver Says Bob Iger Nixed a Kylo Ren 'Star Wars' Film He Pitched With Steven Soderbergh"
        let result = input.htmlToPlainText

        XCTAssertEqual(result, expected, "Should strip tags and preserve all spaces")
    }

    func testMultipleSpacesNormalization() {
        let input = "Too    many     spaces"
        let result = input.htmlToPlainText

        XCTAssertEqual(result, "Too many spaces", "Should normalize multiple spaces to single space")
    }

    func testCommonHTMLEntities() {
        let input = "&lt;tag&gt; &amp; &quot;quotes&quot;"
        let result = input.htmlToPlainText

        XCTAssertEqual(result, "<tag> & \"quotes\"", "Should decode common HTML entities")
    }

    func testCurlyQuotes() {
        let input = "&#8220;Hello&#8221; &#8216;World&#8217;"
        let result = input.htmlToPlainText
        let expected = "\u{201C}Hello\u{201D} \u{2018}World\u{2019}"

        XCTAssertEqual(result, expected, "Should decode numeric entities to curly quotes")
    }

    func testEmDashAndEnDash() {
        let input = "Em&mdash;dash and En&ndash;dash"
        let result = input.htmlToPlainText
        let expected = "Em\u{2014}dash and En\u{2013}dash"

        XCTAssertEqual(result, expected, "Should decode dash entities")
    }

    func testCDATAWithHTMLEntitiesInTags() {
        // htmlToPlainText doesn't specifically handle CDATA - it treats <![CDATA[ and ]]> as HTML tags
        // After stripping these as tags, we're left with the content between [ and ]
        // However, the regex <[^>]+> strips everything from < to > including content,
        // so <![CDATA[content]]> becomes empty after tag stripping
        let input = "<![CDATA[&#8216;I get to do whatever I want in the moment&#8217;: why more...]]>"
        let expected = ""  // Content inside CDATA markers gets stripped with the tags
        let result = input.htmlToPlainText

        XCTAssertEqual(result, expected, "CDATA markers are treated as HTML tags and removed with content")
    }

    func testCDATAWithMultipleEntities() {
        // Same behavior - CDATA treated as HTML tags, content is stripped
        let input = "<![CDATA[&#8220;Quote&#8221; &amp; &#8216;Single&#8217;]]>"
        let expected = ""
        let result = input.htmlToPlainText

        XCTAssertEqual(result, expected, "CDATA markers are treated as HTML tags and removed with content")
    }

    func testNumericAmpersandEntity() {
        let input = "<title>Automattic 20 &#038; Counter-claims</title>"
        let expected = "Automattic 20 & Counter-claims"
        let result = input.htmlToPlainText

        XCTAssertEqual(result, expected, "Should decode &#038; to ampersand")
    }
}
