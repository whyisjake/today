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
        let expected = "Adam Driver Says Bob Iger Nixed a Kylo Ren 'Star Wars' Film"
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

        XCTAssertEqual(result, ""Hello" 'World'", "Should decode numeric entities to curly quotes")
    }

    func testEmDashAndEnDash() {
        let input = "Em&mdash;dash and En&ndash;dash"
        let result = input.htmlToPlainText

        XCTAssertEqual(result, "Em—dash and En–dash", "Should decode dash entities")
    }

    func testCDATAWithHTMLEntities() {
        let input = "<title type=\"html\"><![CDATA[ &#8216;I get to do whatever I want in the moment&#8217;: why more... ]]></title>"
        let expected = "'I get to do whatever I want in the moment': why more..."
        let result = input.htmlToPlainText

        XCTAssertEqual(result, expected, "Should strip CDATA, HTML tags, and decode entities")
    }

    func testCDATAWithMultipleEntities() {
        let input = "<![CDATA[ &#8220;Quote&#8221; &amp; &#8216;Single&#8217; ]]>"
        let expected = "\"Quote\" & 'Single'"
        let result = input.htmlToPlainText

        XCTAssertEqual(result, expected, "Should handle CDATA with multiple entity types")
    }
}
