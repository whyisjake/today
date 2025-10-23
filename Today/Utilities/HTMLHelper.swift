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
                    font-family: -apple-system, BlinkMacSystemFont, 'SF Pro Text', 'Helvetica Neue', Helvetica, Arial, sans-serif;
                    font-size: 17px;
                    line-height: 1.6;
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
    var strippingHTML: String {
        var result = self

        // Remove all HTML tags (including span, div, etc.)
        result = result.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)

        // Decode common HTML entities
        result = result.replacingOccurrences(of: "&nbsp;", with: " ")
        result = result.replacingOccurrences(of: "&amp;", with: "&")
        result = result.replacingOccurrences(of: "&lt;", with: "<")
        result = result.replacingOccurrences(of: "&gt;", with: ">")
        result = result.replacingOccurrences(of: "&quot;", with: "\"")
        result = result.replacingOccurrences(of: "&#39;", with: "'")
        result = result.replacingOccurrences(of: "&apos;", with: "'")
        result = result.replacingOccurrences(of: "&rdquo;", with: "\u{201D}") // Right double quote
        result = result.replacingOccurrences(of: "&ldquo;", with: "\u{201C}") // Left double quote
        result = result.replacingOccurrences(of: "&rsquo;", with: "\u{2019}") // Right single quote
        result = result.replacingOccurrences(of: "&lsquo;", with: "\u{2018}") // Left single quote
        result = result.replacingOccurrences(of: "&mdash;", with: "\u{2014}") // Em dash
        result = result.replacingOccurrences(of: "&ndash;", with: "\u{2013}") // En dash
        result = result.replacingOccurrences(of: "&hellip;", with: "\u{2026}") // Ellipsis

        // Decode numeric entities (&#xxx;)
        result = result.replacingOccurrences(
            of: "&#(\\d+);",
            with: "",
            options: .regularExpression
        )

        // Clean up multiple spaces and newlines
        result = result.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Get plain text from HTML (useful for AI processing)
    var htmlToPlainText: String {
        return self.strippingHTML
    }
}

// Helper view for rendering HTML content
struct HTMLText: View {
    let html: String
    let fontSize: CGFloat

    init(_ html: String, fontSize: CGFloat = 15) {
        self.html = html
        self.fontSize = fontSize
    }

    var body: some View {
        Text(html.htmlToAttributedString)
            .font(.system(size: fontSize))
    }
}
