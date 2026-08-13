//
//  HTMLHelper.swift
//  Today
//
//  Utilities for handling HTML content in RSS feeds
//

import Foundation
import SwiftUI

extension String {
    /// Convert HTML string to AttributedString for native SwiftUI display
    var htmlToAttributedString: AttributedString {
        // Clean up WordPress emoji images that interfere with list rendering
        var cleanedHTML = self
            .replacingOccurrences(of: "<img[^>]*class=\"wp-smiley\"[^>]*>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "<img[^>]*wp-smiley[^>]*>", with: "", options: .regularExpression)

        // Remove CDATA sections
        cleanedHTML = cleanedHTML
            .replacingOccurrences(of: "<![CDATA[", with: "")
            .replacingOccurrences(of: "]]>", with: "")

        // Wrap HTML in proper document with system font CSS
        let htmlWithStyle = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <style>
                body {
                    font-family: Georgia, 'Times New Roman', serif;
                    font-size: 18px;
                    line-height: 1.7;
                    color: #000000;
                    margin: 0;
                    padding: 0;
                }

                /* Paragraph spacing */
                p {
                    margin: 0 0 16px 0;
                    padding: 0;
                }

                /* Headings */
                h1, h2, h3, h4, h5, h6 {
                    font-weight: 600;
                    margin: 24px 0 12px 0;
                    line-height: 1.3;
                }

                h1 { font-size: 28px; }
                h2 { font-size: 24px; }
                h3 { font-size: 20px; }
                h4 { font-size: 18px; }

                /* Lists */
                ul, ol {
                    margin: 16px 0;
                    padding-left: 24px;
                }

                ul {
                    list-style-type: disc;
                    list-style-position: outside;
                }

                ol {
                    list-style-type: decimal;
                    list-style-position: outside;
                }

                li {
                    margin: 6px 0;
                    padding-left: 8px;
                    line-height: 1.6;
                    display: list-item;
                    margin-left:20px;
                }

                /* Blockquotes */
                blockquote {
                    margin: 16px 0;
                    padding: 12px 16px;
                    border-left: 4px solid #007AFF;
                    background-color: #F2F2F7;
                    font-style: italic;
                }

                /* Code blocks */
                pre {
                    background-color: #F2F2F7;
                    padding: 12px;
                    border-radius: 6px;
                    overflow-x: auto;
                    margin: 16px 0;
                }

                code {
                    font-family: 'SF Mono', Menlo, Monaco, 'Courier New', monospace;
                    font-size: 14px;
                    background-color: #F2F2F7;
                    padding: 2px 6px;
                    border-radius: 3px;
                }

                pre code {
                    background-color: transparent;
                    padding: 0;
                }

                /* Links */
                a {
                    color: #007AFF;
                    text-decoration: none;
                }

                /* Images */
                img {
                    max-width: 100%;
                    height: auto;
                    margin: 16px 0;
                    border-radius: 8px;
                }

                /* Horizontal rule */
                hr {
                    border: none;
                    border-top: 1px solid #E5E5EA;
                    margin: 24px 0;
                }

                /* Tables */
                table {
                    border-collapse: collapse;
                    width: 100%;
                    margin: 16px 0;
                }

                th, td {
                    border: 1px solid #E5E5EA;
                    padding: 8px;
                    text-align: left;
                }

                th {
                    background-color: #F2F2F7;
                    font-weight: 600;
                }

                /* Strong and emphasis */
                strong, b {
                    font-weight: 600;
                }

                em, i {
                    font-style: italic;
                }
            </style>
        </head>
        <body>
            \(cleanedHTML)
        </body>
        </html>
        """

        guard let data = htmlWithStyle.data(using: .utf8) else {
            return AttributedString(self.strippingHTML)
        }

        do {
            let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
                .documentType: NSAttributedString.DocumentType.html,
                .characterEncoding: String.Encoding.utf8.rawValue
            ]

            let nsAttributedString = try NSAttributedString(
                data: data,
                options: options,
                documentAttributes: nil
            )

            // Convert to AttributedString
            let attributedString = AttributedString(nsAttributedString)

            // Check if the parsing actually worked by looking at the string
            let plainString = nsAttributedString.string

            // If we still see HTML tags in the output (like <span>), strip everything
            if plainString.range(of: "<[^>]+>", options: .regularExpression) != nil {
                return AttributedString(self.strippingHTML)
            }

            return attributedString
        } catch {
            // If parsing fails, strip HTML tags
            return AttributedString(self.strippingHTML)
        }
    }

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

// Helper view for rendering HTML content
struct HTMLText: View {
    let html: String
    let fontSize: CGFloat
    @AppStorage("fontOption") private var fontOption: FontOption = .serif

    init(_ html: String, fontSize: CGFloat = 15) {
        self.html = html
        self.fontSize = fontSize
    }

    var body: some View {
        Text(html.htmlToAttributedString)
            .font(fontOption == .serif ?
                .system(size: fontSize, design: .serif) :
                .system(size: fontSize, design: .default))
    }
}
