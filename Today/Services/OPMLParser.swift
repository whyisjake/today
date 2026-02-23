import Foundation

// MARK: - OPML Parser

/// Reusable OPML parser extracted from FeedListView.
/// Used by both OPML import and OPML subscription features.
class OPMLParser {

    struct ParsedFeed {
        let url: String
        let title: String
        let category: String
    }

    /// Title extracted from the OPML `<head><title>` element, if present.
    private(set) var opmlTitle: String?

    /// Parse OPML content from a string and return the list of feeds.
    func parse(_ opmlContent: String) throws -> [ParsedFeed] {
        print("🔍 OPML Parser: Starting XML parsing...")
        print("🔍 OPML Parser: Input length: \(opmlContent.count) characters")

        let cleanedContent = cleanOPMLContent(opmlContent)

        guard let data = cleanedContent.data(using: .utf8) else {
            print("❌ OPML Parser: Failed to convert to UTF-8 data")
            throw NSError(domain: "OPML", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid OPML text encoding"])
        }

        return try parseData(data, originalContent: cleanedContent)
    }

    /// Parse OPML content from raw data and return the list of feeds.
    func parse(data: Data) throws -> [ParsedFeed] {
        let content = String(data: data, encoding: .utf8) ?? ""
        let cleanedContent = cleanOPMLContent(content)

        guard let cleanedData = cleanedContent.data(using: .utf8) else {
            throw NSError(domain: "OPML", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid OPML text encoding"])
        }

        return try parseData(cleanedData, originalContent: cleanedContent)
    }

    // MARK: - Private

    private func parseData(_ data: Data, originalContent: String) throws -> [ParsedFeed] {
        // Reset state from any previous parse call
        opmlTitle = nil

        print("🔍 OPML Parser: UTF-8 conversion successful, data size: \(data.count) bytes")

        // Detect HTML content before attempting XML parse
        let lowered = originalContent.prefix(1000).lowercased()
        if lowered.contains("<!doctype html") || lowered.contains("<html") || lowered.contains("<div") {
            print("❌ OPML Parser: Content appears to be HTML, not OPML")
            throw NSError(domain: "OPML", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "The URL returned an HTML page, not an OPML file. Check that the URL points directly to an OPML/XML file."
            ])
        }

        let parser = XMLParser(data: data)
        let delegate = OPMLParserDelegate()
        parser.delegate = delegate

        print("🔍 OPML Parser: Starting XMLParser.parse()...")
        let parseResult = parser.parse()
        print("🔍 OPML Parser: XMLParser.parse() completed with result: \(parseResult)")

        // Store the title if found
        opmlTitle = delegate.opmlTitle

        if parseResult {
            if let error = delegate.parseError {
                print("❌ OPML Parser: Parse error occurred: \(error.localizedDescription)")
                throw NSError(domain: "OPML", code: -1, userInfo: [
                    NSLocalizedDescriptionKey: "XML parsing error: \(error.localizedDescription)"
                ])
            }

            print("🔍 OPML Parser: Found \(delegate.feeds.count) feeds")

            if delegate.feeds.isEmpty {
                print("❌ OPML Parser: No feeds found in OPML")
                throw NSError(domain: "OPML", code: -1, userInfo: [
                    NSLocalizedDescriptionKey: "No valid feeds found in OPML file. Make sure feeds have both a URL and title."
                ])
            }

            print("✅ OPML Parser: Successfully parsed \(delegate.feeds.count) feeds")
            return delegate.feeds.map { ParsedFeed(url: $0.url, title: $0.title, category: $0.category) }
        } else {
            throw buildParseError(parser: parser, delegate: delegate, content: originalContent)
        }
    }

    // MARK: - Content Cleaning

    private func cleanOPMLContent(_ opmlContent: String) -> String {
        var cleanedContent = opmlContent.trimmingCharacters(in: .whitespacesAndNewlines)

        // Remove BOM if present
        if cleanedContent.hasPrefix("\u{FEFF}") {
            cleanedContent = String(cleanedContent.dropFirst())
            print("🔍 OPML Parser: Removed BOM")
        }

        // Detect if OPML was pasted twice (duplicate content)
        let xmlDeclarationCount = cleanedContent.components(separatedBy: "<?xml").count - 1
        let closingOpmlCount = cleanedContent.components(separatedBy: "</opml>").count - 1

        if xmlDeclarationCount > 1 || closingOpmlCount > 1 {
            print("⚠️ OPML Parser: Detected duplicate content (multiple XML declarations or closing tags)")
            if let firstOpmlEnd = cleanedContent.range(of: "</opml>") {
                let endIndex = cleanedContent.index(firstOpmlEnd.upperBound, offsetBy: 0)
                cleanedContent = String(cleanedContent[..<endIndex])
                print("✅ OPML Parser: Extracted first OPML section (\(cleanedContent.count) characters)")
            }
        }

        // Fix attribute spacing: text= "value" -> text="value"
        do {
            let regex = try NSRegularExpression(pattern: "=\\s+\"", options: [])
            let range = NSRange(cleanedContent.startIndex..., in: cleanedContent)
            let fixed = regex.stringByReplacingMatches(
                in: cleanedContent,
                options: [],
                range: range,
                withTemplate: "=\""
            )
            let fixCount = regex.numberOfMatches(in: cleanedContent, options: [], range: range)
            if fixCount > 0 {
                cleanedContent = fixed
                print("🔍 OPML Parser: Fixed \(fixCount) attribute spacing issues (= \" -> =\")")
            }
        } catch {
            print("⚠️ OPML Parser: Regex failed, using simple string replacement")
            cleanedContent = cleanedContent.replacingOccurrences(of: "= \"", with: "=\"")
        }

        // Fix unescaped special characters in attribute values
        cleanedContent = fixUnescapedAttributeValues(cleanedContent)
        print("🔍 OPML Parser: Fixed unescaped special characters in attributes")

        // Remove any invalid control characters (except tab, newline, carriage return)
        cleanedContent = cleanedContent.filter { char in
            let scalar = char.unicodeScalars.first!
            let value = scalar.value
            return value == 0x09 || value == 0x0A || value == 0x0D || value >= 0x20
        }

        return cleanedContent
    }

    /// Fix unescaped quotes and ampersands inside attribute values.
    /// Handles Stream's broken OPML export which doesn't escape special chars.
    private func fixUnescapedAttributeValues(_ content: String) -> String {
        var fixed = ""
        var inAttributeValue = false
        var inXMLDeclaration = false
        var inComment = false
        var i = content.startIndex

        while i < content.endIndex {
            let char = content[i]

            // Check if we're entering an XML comment <!--
            if !inComment && !inXMLDeclaration && char == "<" {
                let remaining = String(content[i...])
                if remaining.hasPrefix("<!--") {
                    inComment = true
                }
            }

            // Check if we're exiting an XML comment -->
            if inComment && char == "-" {
                let remaining = String(content[i...])
                if remaining.hasPrefix("-->") {
                    fixed.append("-->")
                    i = content.index(i, offsetBy: 3)
                    inComment = false
                    continue
                }
            }

            // Skip processing inside comments
            if inComment {
                fixed.append(char)
                i = content.index(after: i)
                continue
            }

            // Check if we're entering an XML declaration
            if char == "<" && content.index(after: i) < content.endIndex &&
               content[content.index(after: i)] == "?" {
                inXMLDeclaration = true
                fixed.append(char)
                i = content.index(after: i)
                continue
            }

            // Check if we're exiting an XML declaration
            if inXMLDeclaration && char == "?" && content.index(after: i) < content.endIndex &&
               content[content.index(after: i)] == ">" {
                fixed.append(char) // append ?
                i = content.index(after: i)
                fixed.append(content[i]) // append >
                inXMLDeclaration = false
                i = content.index(after: i)
                continue
            }

            // Skip processing inside XML declarations
            if inXMLDeclaration {
                fixed.append(char)
                i = content.index(after: i)
                continue
            }

            // Detect start of attribute value: ="
            if char == "=" && content.index(after: i) < content.endIndex &&
               content[content.index(after: i)] == "\"" {
                fixed.append(char) // append =
                i = content.index(after: i)
                fixed.append(content[i]) // append opening "
                i = content.index(after: i)
                inAttributeValue = true
                continue
            }

            // Inside attribute value
            if inAttributeValue {
                if char == "\"" {
                    // Check if this is the closing quote
                    var j = content.index(after: i)
                    var isClosingQuote = false

                    // Skip whitespace after the quote
                    while j < content.endIndex && (content[j] == " " || content[j] == "\t") {
                        j = content.index(after: j)
                    }

                    if j < content.endIndex {
                        let nextChar = content[j]
                        if nextChar == "/" || nextChar == ">" {
                            isClosingQuote = true
                        } else if nextChar.isLetter {
                            var k = j
                            while k < content.endIndex && (content[k].isLetter || content[k].isNumber || content[k] == "_" || content[k] == "-") {
                                k = content.index(after: k)
                            }
                            if k < content.endIndex && content[k] == "=" {
                                isClosingQuote = true
                            }
                        }
                    } else {
                        isClosingQuote = true
                    }

                    if isClosingQuote {
                        fixed.append(char)
                        inAttributeValue = false
                    } else {
                        fixed.append("&quot;")
                    }
                } else if char == "&" {
                    let remainingContent = String(content[i...])
                    let isEntity = remainingContent.hasPrefix("&quot;") ||
                        remainingContent.hasPrefix("&amp;") ||
                        remainingContent.hasPrefix("&lt;") ||
                        remainingContent.hasPrefix("&gt;") ||
                        remainingContent.hasPrefix("&apos;") ||
                        remainingContent.hasPrefix("&#")

                    if isEntity {
                        fixed.append(char)
                    } else {
                        fixed.append("&amp;")
                    }
                } else {
                    fixed.append(char)
                }
            } else {
                fixed.append(char)
            }

            i = content.index(after: i)
        }

        return fixed
    }

    // MARK: - Error Building

    private func buildParseError(parser: XMLParser, delegate: OPMLParserDelegate, content: String) -> NSError {
        let line = parser.lineNumber
        let column = parser.columnNumber

        if let error = delegate.parseError {
            print("❌ OPML Parser: Parse failed at line \(line), column \(column)")
            print("❌ OPML Parser: Error: \(error.localizedDescription)")
            print("❌ OPML Parser: Error code: \((error as NSError).code)")

            let lines = content.components(separatedBy: .newlines)
            if line > 0 && line <= lines.count {
                let problemLine = lines[line - 1]
                print("❌ OPML Parser: Problematic line: \(problemLine)")
                if column > 0 && column <= problemLine.count {
                    let index = problemLine.index(problemLine.startIndex, offsetBy: column - 1, limitedBy: problemLine.endIndex)
                    if let index = index {
                        let char = problemLine[index]
                        print("❌ OPML Parser: Character at error: '\(char)' (Unicode: \\u{\(String(char.unicodeScalars.first!.value, radix: 16))})")
                    }
                }
            }

            let errorCode = (error as NSError).code
            var errorMessage = "Failed to parse OPML at line \(line), column \(column)"

            if errorCode == 23 {
                errorMessage += "\n\nThis OPML file contains invalid XML characters. This is a known issue with some RSS readers' OPML export.\n\nTry:\n1. Re-export the OPML from your RSS reader\n2. Open the OPML file in a text editor and check for unusual characters\n3. Make sure you didn't accidentally paste the content twice"
            } else if errorCode == 4 {
                errorMessage += "\n\nThe OPML content appears to be empty or invalid."
            } else {
                errorMessage += ": \(error.localizedDescription)"
            }

            return NSError(domain: "OPML", code: -1, userInfo: [
                NSLocalizedDescriptionKey: errorMessage
            ])
        } else {
            print("❌ OPML Parser: Parse failed at line \(line), column \(column) with no specific error")

            var errorMessage = "Failed to parse OPML file at line \(line), column \(column)."
            errorMessage += "\n\nPlease check that:"
            errorMessage += "\n• The OPML file was exported correctly from your RSS reader"
            errorMessage += "\n• You copied the entire file content"
            errorMessage += "\n• You didn't paste the content multiple times"

            return NSError(domain: "OPML", code: -1, userInfo: [
                NSLocalizedDescriptionKey: errorMessage
            ])
        }
    }
}

// MARK: - OPML Parser Delegate

class OPMLParserDelegate: NSObject, XMLParserDelegate {
    var feeds: [(url: String, title: String, category: String)] = []
    var opmlTitle: String?
    var parseError: Error?

    private var currentCategory = "General"
    private var categoryStack: [String] = []
    private var elementCount = 0
    private var feedCount = 0
    private var categoryCount = 0
    private var skippedCount = 0
    private var isInsideHead = false
    private var isInsideTitle = false
    private var titleBuffer = ""

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        if elementName == "head" {
            isInsideHead = true
            return
        }

        if isInsideHead && elementName == "title" {
            isInsideTitle = true
            titleBuffer = ""
            return
        }

        if elementName == "outline" {
            elementCount += 1

            if elementCount <= 3 {
                print("🔍 Delegate: Element \(elementCount) - attributes: \(attributeDict)")
            }

            // Case-insensitive attribute lookup helper
            func getAttribute(_ name: String) -> String? {
                if let value = attributeDict[name] {
                    return value
                }
                for (key, value) in attributeDict {
                    if key.lowercased() == name.lowercased() {
                        return value
                    }
                }
                return nil
            }

            let type = getAttribute("type")
            let xmlUrl = getAttribute("xmlUrl")
            let title = getAttribute("title") ?? getAttribute("text")
            let text = getAttribute("text")

            let isFeed = xmlUrl != nil || type?.lowercased() == "rss"

            if isFeed, let url = xmlUrl, let feedTitle = title, !feedTitle.trimmingCharacters(in: .whitespaces).isEmpty {
                // Determine category: prefer inline `category` attribute (Feedland-style),
                // fall back to nested parent category (traditional OPML)
                let feedCategory: String
                if let inlineCategory = getAttribute("category") {
                    // Feedland uses comma-separated categories like "all,tech,bloggers"
                    // Pick the first meaningful one (skip "all" and "starters" which are meta-categories)
                    let cats = inlineCategory.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
                    let meaningful = cats.filter { $0 != "all" && $0 != "starters" }
                    feedCategory = meaningful.first ?? cats.first ?? currentCategory
                } else {
                    feedCategory = currentCategory
                }
                feeds.append((url: url, title: feedTitle, category: feedCategory))
                feedCount += 1
                if feedCount <= 3 {
                    print("✅ Delegate: Added feed \(feedCount): \(feedTitle) | \(url)")
                }
            } else if !isFeed, let categoryName = text, !categoryName.trimmingCharacters(in: .whitespaces).isEmpty {
                categoryStack.append(currentCategory)
                currentCategory = categoryName.lowercased()
                categoryCount += 1
                print("📁 Delegate: Found category: \(categoryName)")
            } else {
                skippedCount += 1
                if skippedCount <= 3 {
                    var reason = "Unknown"
                    if !isFeed {
                        reason = "Not a feed (no xmlUrl or type=rss)"
                    } else if xmlUrl == nil {
                        reason = "Missing xmlUrl"
                    } else if title == nil || title!.trimmingCharacters(in: .whitespaces).isEmpty {
                        reason = "Missing or empty title"
                    }
                    print("⏭️  Delegate: Skipped element (reason: \(reason))")
                }
            }
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if isInsideTitle {
            titleBuffer += string
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "head" {
            isInsideHead = false
            return
        }

        if isInsideHead && elementName == "title" {
            isInsideTitle = false
            let trimmed = titleBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                opmlTitle = trimmed
            }
            return
        }

        if elementName == "outline" && !categoryStack.isEmpty {
            currentCategory = categoryStack.removeLast()
        }
    }

    func parser(_ parser: XMLParser, didEndDocument: Void) {
        print("📊 Delegate: Parsing complete - Processed \(elementCount) outline elements")
        print("📊 Delegate: Found \(feedCount) feeds, \(categoryCount) categories, skipped \(skippedCount) elements")
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        self.parseError = parseError
    }

    func parser(_ parser: XMLParser, validationErrorOccurred validationError: Error) {
        self.parseError = validationError
    }
}
