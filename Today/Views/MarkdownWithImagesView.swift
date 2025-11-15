//
//  MarkdownWithImagesView.swift
//  Today
//
//  Custom markdown renderer with image support for Reddit content
//

import SwiftUI

struct MarkdownWithImagesView: View {
    let text: String
    let fontOption: FontOption
    var fontSize: Font.TextStyle = .subheadline

    @State private var parsedContent: [ContentBlock] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(parsedContent.enumerated()), id: \.offset) { _, block in
                switch block {
                case .text(let content):
                    Text(parseMarkdown(content))
                        .font(fontOption == .serif ?
                            .system(fontSize, design: .serif) :
                            .system(fontSize, design: .default))
                        .textSelection(.enabled)

                case .image(let url, let alt):
                    VStack(alignment: .leading, spacing: 4) {
                        AsyncImage(url: URL(string: url)) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .cornerRadius(8)
                            case .failure:
                                HStack {
                                    Image(systemName: "photo")
                                        .foregroundStyle(.secondary)
                                    Text("Failed to load image")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .background(Color(.systemGray6))
                                .cornerRadius(8)
                            case .empty:
                                ProgressView()
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .padding()
                            @unknown default:
                                EmptyView()
                            }
                        }
                        .frame(maxWidth: .infinity)

                        if !alt.isEmpty {
                            Text(alt)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .italic()
                        }
                    }
                }
            }
        }
        .onAppear {
            parsedContent = parseContent(text)
        }
    }

    private func parseMarkdown(_ text: String) -> AttributedString {
        do {
            return try AttributedString(markdown: text)
        } catch {
            return AttributedString(text)
        }
    }

    private func parseContent(_ text: String) -> [ContentBlock] {
        var blocks: [ContentBlock] = []
        var currentText = text

        // Pattern for markdown images: ![alt](url)
        let markdownImagePattern = #"!\[(.*?)\]\((https?://[^\s\)]+)\)"#

        // Pattern for HTML images: <img src="url" alt="alt">
        let htmlImagePattern = #"<img[^>]*src=["']([^"']+)["'][^>]*(?:alt=["']([^"']*)["'])?[^>]*>"#

        while !currentText.isEmpty {
            var foundImage = false

            // Try to find markdown image
            if let markdownRegex = try? NSRegularExpression(pattern: markdownImagePattern, options: []),
               let match = markdownRegex.firstMatch(in: currentText, options: [], range: NSRange(currentText.startIndex..., in: currentText)) {

                // Add text before image
                let beforeRange = currentText.startIndex..<Range(match.range, in: currentText)!.lowerBound
                if !currentText[beforeRange].isEmpty {
                    blocks.append(.text(String(currentText[beforeRange])))
                }

                // Extract alt and URL
                let alt = match.numberOfRanges > 1 ? String(currentText[Range(match.range(at: 1), in: currentText)!]) : ""
                let url = match.numberOfRanges > 2 ? String(currentText[Range(match.range(at: 2), in: currentText)!]) : ""

                blocks.append(.image(url: url, alt: alt))

                // Continue with remaining text
                currentText = String(currentText[Range(match.range, in: currentText)!.upperBound...])
                foundImage = true
            }
            // Try to find HTML image
            else if let htmlRegex = try? NSRegularExpression(pattern: htmlImagePattern, options: []),
                    let match = htmlRegex.firstMatch(in: currentText, options: [], range: NSRange(currentText.startIndex..., in: currentText)) {

                // Add text before image
                let beforeRange = currentText.startIndex..<Range(match.range, in: currentText)!.lowerBound
                if !currentText[beforeRange].isEmpty {
                    blocks.append(.text(String(currentText[beforeRange])))
                }

                // Extract src and alt
                let url = match.numberOfRanges > 1 ? String(currentText[Range(match.range(at: 1), in: currentText)!]) : ""
                let alt = match.numberOfRanges > 2 && match.range(at: 2).location != NSNotFound ? String(currentText[Range(match.range(at: 2), in: currentText)!]) : ""

                blocks.append(.image(url: url, alt: alt))

                // Continue with remaining text
                currentText = String(currentText[Range(match.range, in: currentText)!.upperBound...])
                foundImage = true
            }

            if !foundImage {
                // No more images, add remaining text
                blocks.append(.text(currentText))
                break
            }
        }

        return blocks
    }

    enum ContentBlock {
        case text(String)
        case image(url: String, alt: String)
    }
}
