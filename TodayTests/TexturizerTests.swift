//
//  TexturizerTests.swift
//  TodayTests
//
//  Tests for smart quote conversion and text beautification
//  Based on WordPress wptexturize() functionality
//

import XCTest
@testable import Today

final class TexturizerTests: XCTestCase {

    // MARK: - Basic Quote Conversion Tests

    func testDoubleQuotesAtStartAndEnd() {
        let input = "\"Hello world\""
        let expected = "\u{201C}Hello world\u{201D}"
        let result = input.texturize()
        XCTAssertEqual(result, expected, "Should convert straight double quotes to curly quotes")
    }

    func testSingleQuotesAtStartAndEnd() {
        let input = "'Hello world'"
        let expected = "\u{2018}Hello world\u{2019}"
        let result = input.texturize()
        XCTAssertEqual(result, expected, "Should convert straight single quotes to curly quotes")
    }

    func testMultipleQuotedPhrases() {
        let input = "He said \"hello\" and she said \"goodbye\""
        let expected = "He said \u{201C}hello\u{201D} and she said \u{201C}goodbye\u{201D}"
        let result = input.texturize()
        XCTAssertEqual(result, expected, "Should convert multiple quoted phrases")
    }

    func testNestedQuotes() {
        let input = "\"She said 'hello' to me\""
        let expected = "\u{201C}She said \u{2018}hello\u{2019} to me\u{201D}"
        let result = input.texturize()
        XCTAssertEqual(result, expected, "Should handle nested quotes correctly")
    }

    // MARK: - Apostrophe Tests

    func testApostrophesInContractions() {
        let input = "can't won't don't it's"
        let expected = "can\u{2019}t won\u{2019}t don\u{2019}t it\u{2019}s"
        let result = input.texturize()
        XCTAssertEqual(result, expected, "Should convert apostrophes in contractions")
    }

    func testPossessiveApostrophes() {
        let input = "John's book, the dogs' toys"
        let expected = "John\u{2019}s book, the dogs\u{2019} toys"
        let result = input.texturize()
        XCTAssertEqual(result, expected, "Should convert possessive apostrophes")
    }

    func testCockneyExpressions() {
        let input = "'twas 'til 'bout 'cause 'em"
        let expected = "\u{2019}twas \u{2019}til \u{2019}bout \u{2019}cause \u{2019}em"
        let result = input.texturize()
        XCTAssertEqual(result, expected, "Should convert cockney expressions with leading apostrophes")
    }

    // MARK: - Dash Tests

    func testEnDash() {
        let input = "Pages 5--10"
        let expected = "Pages 5\u{2013}10"
        let result = input.texturize()
        XCTAssertEqual(result, expected, "Should convert -- to en dash")
    }

    func testEmDash() {
        let input = "Hello---world"
        let expected = "Hello\u{2014}world"
        let result = input.texturize()
        XCTAssertEqual(result, expected, "Should convert --- to em dash")
    }

    func testEmDashWithSpaces() {
        let input = "Hello -- world"
        let expected = "Hello \u{2014} world"
        let result = input.texturize()
        XCTAssertEqual(result, expected, "Should convert -- with spaces to em dash")
    }

    func testEnDashWithSpaces() {
        let input = "The years 2020 - 2021"
        let expected = "The years 2020 \u{2013} 2021"
        let result = input.texturize()
        XCTAssertEqual(result, expected, "Should convert single dash with spaces to en dash")
    }

    func testDoNotConvertXnDash() {
        let input = "xn--domain.com"
        let expected = "xn--domain.com"
        let result = input.texturize()
        XCTAssertEqual(result, expected, "Should not convert -- in xn-- (internationalized domain names)")
    }

    // MARK: - Ellipsis Tests

    func testEllipsis() {
        let input = "Wait..."
        let expected = "Wait\u{2026}"
        let result = input.texturize()
        XCTAssertEqual(result, expected, "Should convert three periods to ellipsis")
    }

    func testMultipleEllipses() {
        let input = "Hello... world... goodbye..."
        let expected = "Hello\u{2026} world\u{2026} goodbye\u{2026}"
        let result = input.texturize()
        XCTAssertEqual(result, expected, "Should convert multiple ellipses")
    }

    // MARK: - Special Character Tests

    func testTrademark() {
        let input = "WordPress (tm)"
        let expected = "WordPress \u{2122}"
        let result = input.texturize()
        XCTAssertEqual(result, expected, "Should convert (tm) to trademark symbol")
    }

    func testMultiplicationSign() {
        let input = "5x10 meters"
        let expected = "5\u{00D7}10 meters"
        let result = input.texturize()
        XCTAssertEqual(result, expected, "Should convert x between digits to multiplication sign")
    }

    func testDoNotConvertHexNumbers() {
        let input = "0x1234"
        let expected = "0x1234"
        let result = input.texturize()
        XCTAssertEqual(result, expected, "Should not convert x in hex numbers")
    }

    // MARK: - Prime and Double Prime Tests

    func testFeetAndInches() {
        let input = "9' 6\""
        let expected = "9\u{2032} 6\u{2033}"
        let result = input.texturize()
        XCTAssertEqual(result, expected, "Should convert feet/inches marks to prime/double prime")
    }

    func testNumberWithPrimeOnly() {
        let input = "5'"
        let expected = "5\u{2032}"
        let result = input.texturize()
        XCTAssertEqual(result, expected, "Should convert prime mark after number")
    }

    // MARK: - Abbreviated Year Tests

    func testAbbreviatedYear() {
        let input = "Class of '99"
        let expected = "Class of \u{2019}99"
        let result = input.texturize()
        XCTAssertEqual(result, expected, "Should convert apostrophe before two-digit year")
    }

    func testQuotedAbbreviatedYear() {
        let input = "'99 was a great year"
        let expected = "\u{2019}99 was a great year"
        let result = input.texturize()
        XCTAssertEqual(result, expected, "Should handle abbreviated year at start")
    }

    // MARK: - Quoted Numbers Tests

    func testQuotedDecimalWithSingleQuotes() {
        let input = "The value is '0.42'"
        let expected = "The value is \u{2018}0.42\u{2019}"
        let result = input.texturize()
        XCTAssertEqual(result, expected, "Should convert quotes around decimal numbers")
    }

    func testQuotedNumberWithDoubleQuotes() {
        let input = "The answer is \"42\""
        let expected = "The answer is \u{201C}42\u{201D}"
        let result = input.texturize()
        XCTAssertEqual(result, expected, "Should convert double quotes around numbers")
    }

    // MARK: - Edge Cases

    func testEmptyString() {
        let input = ""
        let expected = ""
        let result = input.texturize()
        XCTAssertEqual(result, expected, "Should handle empty string")
    }

    func testNoSpecialCharacters() {
        let input = "Hello world"
        let expected = "Hello world"
        let result = input.texturize()
        XCTAssertEqual(result, expected, "Should return unchanged when no special characters")
    }

    func testMixedContent() {
        let input = "He said \"It's great--really great!\" Class of '99..."
        let expected = "He said \u{201C}It\u{2019}s great\u{2014}really great!\u{201D} Class of \u{2019}99\u{2026}"
        let result = input.texturize()
        XCTAssertEqual(result, expected, "Should handle mixed special characters")
    }

    func testBacktickQuotes() {
        let input = "``Hello''"
        let expected = "\u{201C}Hello\u{201D}"
        let result = input.texturize()
        XCTAssertEqual(result, expected, "Should convert backtick/double-apostrophe style quotes")
    }

    // MARK: - HTML/XML Preservation Tests

    func testPreserveHTMLTags() {
        let input = "<p>\"Hello world\"</p>"
        let expected = "<p>\u{201C}Hello world\u{201D}</p>"
        let result = input.texturize()
        XCTAssertEqual(result, expected, "Should texturize content but preserve HTML tags")
    }

    func testPreserveHTMLEntities() {
        let input = "A &amp; B \"test\""
        let expected = "A &amp; B \u{201C}test\u{201D}"
        let result = input.texturize()
        XCTAssertEqual(result, expected, "Should preserve existing HTML entities and texturize quotes")
    }

    // MARK: - Real World Examples

    func testRealWorldTitle1() {
        let input = "Affirm Sync: A4A and CS Oct 24, 2025"
        let expected = "Affirm Sync: A4A and CS Oct 24, 2025"
        let result = input.texturize()
        XCTAssertEqual(result, expected, "Should handle title with no special characters")
    }

    func testRealWorldTitle2() {
        let input = "\"I fell at the top of a mountain -- and knew I was going to die\""
        let expected = "\u{201C}I fell at the top of a mountain \u{2014} and knew I was going to die\u{201D}"
        let result = input.texturize()
        XCTAssertEqual(result, expected, "Should handle quoted title with em dash")
    }

    func testRealWorldTitle3() {
        let input = "'I get to do whatever I want in the moment': why more people are choosing to work freelance"
        let expected = "\u{2018}I get to do whatever I want in the moment\u{2019}: why more people are choosing to work freelance"
        let result = input.texturize()
        XCTAssertEqual(result, expected, "Should handle single quotes and apostrophes in title")
    }

    // MARK: - Space Preservation Tests

    func testSpaceBeforeSingleQuote() {
        let input = "Trump Says Meeting Putin Is a 'Waste of Time'"
        let expected = "Trump Says Meeting Putin Is a \u{2018}Waste of Time\u{2019}"
        let result = input.texturize()
        XCTAssertEqual(result, expected, "Should preserve space before opening single quote")
    }

    func testSpaceBeforeQuotedPhrase() {
        let input = "The Talk Show: 'You and Frank Sinatra'"
        let expected = "The Talk Show: \u{2018}You and Frank Sinatra\u{2019}"
        let result = input.texturize()
        XCTAssertEqual(result, expected, "Should preserve space and colon before quoted phrase")
    }

    func testMultipleSpacesBeforeSingleQuote() {
        let input = "This is a  'test' case"
        let expected = "This is a  \u{2018}test\u{2019} case"
        let result = input.texturize()
        XCTAssertEqual(result, expected, "Should preserve multiple spaces before quote")
    }
}
