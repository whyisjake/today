//
//  Texturizer.swift
//  Today
//
//  Port of WordPress wptexturize() function to Swift
//  Converts straight quotes to curly quotes, dashes to proper em/en dashes,
//  and other typographic improvements
//

import Foundation

extension String {
    /// Apply typographic improvements: convert straight quotes to curly quotes,
    /// dashes to em/en dashes, and other text beautification
    func texturize() -> String {
        return Texturizer.texturize(self)
    }
}

class Texturizer {
    // Unicode characters for smart quotes and other symbols
    private static let openingQuote = "\u{201C}"        // "
    private static let closingQuote = "\u{201D}"        // "
    private static let openingSingleQuote = "\u{2018}"  // '
    private static let closingSingleQuote = "\u{2019}"  // '
    private static let apos = "\u{2019}"                // '
    private static let prime = "\u{2032}"               // ′
    private static let doublePrime = "\u{2033}"         // ″
    private static let enDash = "\u{2013}"              // –
    private static let emDash = "\u{2014}"              // —
    private static let ellipsis = "\u{2026}"            // …
    private static let trademark = "\u{2122}"           // ™
    private static let multiply = "\u{00D7}"            // ×

    // Placeholder flags used during processing
    private static let openQFlag = "<!--oq-->"
    private static let openSqFlag = "<!--osq-->"
    private static let aposFlag = "<!--apos-->"

    // Tags that should not be texturized
    private static let noTexturizeTags = ["pre", "code", "kbd", "style", "script", "tt"]

    /// Main texturize function
    static func texturize(_ text: String) -> String {
        // Return early if empty
        if text.isEmpty {
            return text
        }

        // Static replacements (simple string substitutions)
        var result = text
        result = result.replacingOccurrences(of: "...", with: ellipsis)
        result = result.replacingOccurrences(of: "``", with: openingQuote)
        result = result.replacingOccurrences(of: "''", with: closingQuote)
        result = result.replacingOccurrences(of: " (tm)", with: " \(trademark)")

        // Cockney expressions
        let cockneyPairs: [(String, String)] = [
            ("'tain't", "\(apos)tain\(apos)t"),
            ("'twere", "\(apos)twere"),
            ("'twas", "\(apos)twas"),
            ("'tis", "\(apos)tis"),
            ("'twill", "\(apos)twill"),
            ("'til", "\(apos)til"),
            ("'bout", "\(apos)bout"),
            ("'nuff", "\(apos)nuff"),
            ("'round", "\(apos)round"),
            ("'cause", "\(apos)cause"),
            ("'em", "\(apos)em")
        ]

        for (cockney, replacement) in cockneyPairs {
            result = result.replacingOccurrences(of: cockney, with: replacement, options: .caseInsensitive)
        }

        // Split by HTML tags to avoid texturizing inside tags
        let parts = splitPreservingHTMLTags(result)
        var texturizedParts: [String] = []
        var insideNoTexturizeTag = false
        var tagStack: [String] = []

        for part in parts {
            if part.hasPrefix("<") {
                // This is an HTML tag
                texturizedParts.append(part)

                // Track if we're entering/exiting a no-texturize tag
                if let tagName = extractTagName(from: part) {
                    if part.hasPrefix("</") {
                        // Closing tag
                        if let lastTag = tagStack.last, lastTag == tagName {
                            tagStack.removeLast()
                            if noTexturizeTags.contains(tagName) {
                                insideNoTexturizeTag = !tagStack.contains(where: { noTexturizeTags.contains($0) })
                            }
                        }
                    } else if !part.contains("/>") {
                        // Opening tag (not self-closing)
                        tagStack.append(tagName)
                        if noTexturizeTags.contains(tagName) {
                            insideNoTexturizeTag = true
                        }
                    }
                }
                continue
            }

            // Skip texturizing if we're inside a no-texturize tag
            if insideNoTexturizeTag {
                texturizedParts.append(part)
                continue
            }

            var texturized = part

            // Pattern-based replacements for apostrophes and quotes
            texturized = texturizeApostrophes(texturized)
            texturized = texturizeQuotes(texturized)
            texturized = texturizeDashes(texturized)
            texturized = texturizeMultiplication(texturized)

            // Replace &'s that aren't already entities
            texturized = replaceAmpersands(texturized)

            texturizedParts.append(texturized)
        }

        return texturizedParts.joined()
    }

    // MARK: - Helper Functions

    /// Split text while preserving HTML tags
    private static func splitPreservingHTMLTags(_ text: String) -> [String] {
        var parts: [String] = []
        var currentPart = ""
        var insideTag = false

        for char in text {
            if char == "<" {
                if !currentPart.isEmpty {
                    parts.append(currentPart)
                    currentPart = ""
                }
                insideTag = true
                currentPart.append(char)
            } else if char == ">" && insideTag {
                currentPart.append(char)
                parts.append(currentPart)
                currentPart = ""
                insideTag = false
            } else {
                currentPart.append(char)
            }
        }

        if !currentPart.isEmpty {
            parts.append(currentPart)
        }

        return parts
    }

    /// Extract tag name from HTML tag string
    private static func extractTagName(from tag: String) -> String? {
        let pattern = "</?([a-zA-Z][a-zA-Z0-9]*)"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: tag, range: NSRange(tag.startIndex..., in: tag)),
              match.numberOfRanges > 1 else {
            return nil
        }

        let range = Range(match.range(at: 1), in: tag)!
        return String(tag[range])
    }

    /// Texturize apostrophes
    private static func texturizeApostrophes(_ text: String) -> String {
        var result = text

        // '99 and '99s (abbreviated years)
        result = result.replacingOccurrences(
            of: "'(?=\\d\\d(?:[^\\d%]|$))",
            with: aposFlag,
            options: .regularExpression
        )

        // Quoted decimal numbers like '0.42'
        result = result.replacingOccurrences(
            of: "(^|\\s)'(\\d[.,\\d]*)'",
            with: "$1\(openSqFlag)$2\(closingSingleQuote)",
            options: .regularExpression
        )

        // Single quote at start or after specific characters
        result = result.replacingOccurrences(
            of: "(^|[(\\[{\"\\-\\s])'",
            with: "$1\(openSqFlag)",
            options: .regularExpression
        )

        // Apostrophe in contractions/possessives
        result = result.replacingOccurrences(
            of: "(?<!\\s)'(?![\\s.,;!?\"'(){}\\[\\]\\-])",
            with: aposFlag,
            options: .regularExpression
        )

        // Replace flags with actual characters
        result = result.replacingOccurrences(of: aposFlag, with: apos)
        result = result.replacingOccurrences(of: openSqFlag, with: openingSingleQuote)

        // Handle primes (feet)
        result = texturizePrimes(result, quoteChar: "'", primeChar: prime, openFlag: openSqFlag, closeQuote: closingSingleQuote)

        return result
    }

    /// Texturize double quotes
    private static func texturizeQuotes(_ text: String) -> String {
        var result = text

        // Quoted numbers like "42"
        result = result.replacingOccurrences(
            of: "(^|\\s)\"(\\d[.,\\d]*)\"",
            with: "$1\(openQFlag)$2\(closingQuote)",
            options: .regularExpression
        )

        // Double quote at start or after specific characters
        result = result.replacingOccurrences(
            of: "(^|[(\\[{\\-\\s])\"",
            with: "$1\(openQFlag)",
            options: .regularExpression
        )

        // Replace flags
        result = result.replacingOccurrences(of: openQFlag, with: openingQuote)

        // Closing quotes (anything not matched above)
        result = result.replacingOccurrences(of: "\"", with: closingQuote)

        // Handle double primes (inches)
        result = texturizePrimes(result, quoteChar: "\"", primeChar: doublePrime, openFlag: openQFlag, closeQuote: closingQuote)

        return result
    }

    /// Handle primes (feet/inches markers)
    private static func texturizePrimes(_ text: String, quoteChar: String, primeChar: String, openFlag: String, closeQuote: String) -> String {
        var result = text

        // Convert quote to prime after digit
        let primePattern = "(\\d)\\" + (quoteChar == "\"" ? "\"" : "'")
        result = result.replacingOccurrences(
            of: primePattern,
            with: "$1\(primeChar)",
            options: .regularExpression
        )

        return result
    }

    /// Texturize dashes
    private static func texturizeDashes(_ text: String) -> String {
        var result = text

        // Em dash: ---
        result = result.replacingOccurrences(of: "---", with: emDash)

        // Em dash: -- with spaces
        result = result.replacingOccurrences(
            of: "(^|\\s)--(\\s|$)",
            with: "$1\(emDash)$2",
            options: .regularExpression
        )

        // En dash: -- (but not xn--)
        result = result.replacingOccurrences(
            of: "(?<!xn)--",
            with: enDash,
            options: .regularExpression
        )

        // En dash: single dash with spaces
        result = result.replacingOccurrences(
            of: "(^|\\s)-(\\s|$)",
            with: "$1\(enDash)$2",
            options: .regularExpression
        )

        return result
    }

    /// Convert x to multiplication sign between digits
    private static func texturizeMultiplication(_ text: String) -> String {
        // 9x9 (but never 0x9999 for hex)
        return text.replacingOccurrences(
            of: "\\b(\\d(?:[\\d.,]+|))x(\\d[\\d.,]*)\\b",
            with: "$1\(multiply)$2",
            options: .regularExpression
        )
    }

    /// Replace ampersands that aren't already HTML entities
    private static func replaceAmpersands(_ text: String) -> String {
        return text.replacingOccurrences(
            of: "&(?!#(?:\\d+|x[a-fA-F0-9]+);|[a-zA-Z][a-zA-Z0-9]{0,7};)",
            with: "&#038;",
            options: .regularExpression
        )
    }
}
