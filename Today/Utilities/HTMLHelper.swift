//
//  HTMLHelper.swift
//  Today
//
//  Utilities for handling HTML content in RSS feeds
//

import Foundation

extension String {
    /// Strip HTML tags from string (fallback)
    ///
    /// `nonisolated` because this module builds with SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor,
    /// which would otherwise confine this pure string transform to the main actor and make it
    /// unusable from background work like the derived-field backfill.
    nonisolated var strippingHTML: String {
        var result = self

        // Remove all HTML tags (including span, div, etc.)
        result = result.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)

        // Decode HTML entities — one pass, no chaining (see `decodeHTMLEntities`)
        result = result.decodeHTMLEntities()

        // Clean up multiple spaces and newlines
        result = result.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Get plain text from HTML (useful for AI processing)
    nonisolated var htmlToPlainText: String {
        return self.strippingHTML
    }

    /// The app's single HTML entity decoder: named, decimal and hexadecimal references.
    ///
    /// This replaced four near-duplicate implementations (RSSParser, JSONFeedParser,
    /// RedditJSONParser and the inline block in `strippingHTML`). All four ran a sequence of
    /// whole-string `replacingOccurrences` calls, which lets one rule consume another rule's
    /// output: with `&amp;` decoded before `&lt;`, the single input `&amp;lt;` became `&lt;`
    /// and was then caught by the `&lt;` rule, yielding a live `<`. Escaped markup a feed had
    /// deliberately neutered came back to life in one decode.
    ///
    /// This version scans the string once and replaces each reference exactly where it
    /// occurs, resuming *after* the replacement. Nothing a decode produces can be re-read as
    /// an entity, so `&amp;lt;` decodes to the literal text `&lt;` and stays inert. Decoding
    /// is therefore also strictly single-pass: no caller may apply it twice.
    ///
    /// `nonisolated` because this module builds with SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor,
    /// and the feed parsers call this from background work (see `strippingHTML`).
    nonisolated func decodeHTMLEntities() -> String {
        guard self.contains("&") else { return self }

        var result = ""
        result.reserveCapacity(self.count)
        var cursor = self.startIndex

        while let ampersand = self[cursor...].firstIndex(of: "&") {
            result.append(contentsOf: self[cursor..<ampersand])

            let bodyStart = self.index(after: ampersand)
            // Longest reference we accept is a hex/decimal code point; bound the scan so a
            // stray `&` in prose does not drag the search across the whole document.
            let windowEnd = self.index(bodyStart, offsetBy: HTMLEntities.maxReferenceLength,
                                       limitedBy: self.endIndex) ?? self.endIndex

            if let semicolon = self[bodyStart..<windowEnd].firstIndex(of: ";"),
               let decoded = HTMLEntities.decode(String(self[bodyStart..<semicolon])) {
                result.append(decoded)
                cursor = self.index(after: semicolon)
            } else {
                result.append("&")
                cursor = bodyStart
            }
        }

        result.append(contentsOf: self[cursor...])
        return result
    }
}

/// Entity table and reference decoding for `String.decodeHTMLEntities()`.
enum HTMLEntities {
    /// Character budget for the text between `&` and `;`.
    nonisolated static let maxReferenceLength = 10

    /// The union of the named entities the four previous decoders supported.
    nonisolated static let named: [String: String] = [
        "amp": "&",
        "lt": "<",
        "gt": ">",
        "quot": "\"",
        "apos": "'",
        "nbsp": " ",
        "rdquo": "\u{201D}",  // Right double quote
        "ldquo": "\u{201C}",  // Left double quote
        "rsquo": "\u{2019}",  // Right single quote
        "lsquo": "\u{2018}",  // Left single quote
        "mdash": "\u{2014}",  // Em dash
        "ndash": "\u{2013}",  // En dash
        "hellip": "\u{2026}"  // Ellipsis
    ]

    /// Decode the body of a reference — the text between `&` and `;`.
    /// Returns nil for anything unrecognised, so it is left in the output verbatim.
    nonisolated static func decode(_ reference: String) -> String? {
        guard !reference.isEmpty else { return nil }

        guard reference.hasPrefix("#") else {
            return named[reference]
        }

        let digits = reference.dropFirst()
        let codePoint: UInt32?
        if digits.hasPrefix("x") || digits.hasPrefix("X") {
            codePoint = UInt32(digits.dropFirst(), radix: 16)
        } else {
            codePoint = UInt32(digits, radix: 10)
        }

        guard let codePoint, let scalar = UnicodeScalar(codePoint) else { return nil }
        return String(scalar)
    }
}
