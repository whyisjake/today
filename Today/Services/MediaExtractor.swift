//
//  MediaExtractor.swift
//  Today
//
//  Service for extracting direct media URLs from embed HTML
//  Supports: Giphy, Redgifs, Gfycat, Imgur, Streamable
//

import Foundation

struct ExtractedMedia {
    let url: URL
    let type: MediaType
    let width: Int?
    let height: Int?

    enum MediaType {
        case gif
        case video
        case image
    }
}

class MediaExtractor {
    static let shared = MediaExtractor()

    /// Extract direct media URL from embed HTML
    /// Returns nil if no supported media found or if iframe should be used
    func extractMedia(from html: String) -> ExtractedMedia? {
        print("🎬 MediaExtractor: Processing embed HTML (\(html.count) chars)")

        // Giphy
        if html.contains("giphy.com") {
            print("🎬 MediaExtractor: Detected Giphy embed")
            let result = extractGiphy(from: html)
            if let media = result {
                print("✅ MediaExtractor: Extracted Giphy URL: \(media.url)")
            } else {
                print("❌ MediaExtractor: Failed to extract Giphy URL")
                print("   HTML: \(html)")
            }
            return result
        }

        // Redgifs
        if html.contains("redgifs.com") {
            print("🎬 MediaExtractor: Detected Redgifs embed")
            let result = extractRedgifs(from: html)
            if let media = result {
                print("✅ MediaExtractor: Extracted Redgifs URL: \(media.url)")
            } else {
                print("❌ MediaExtractor: Failed to extract Redgifs URL")
                print("   HTML: \(html)")
            }
            return result
        }

        // Gfycat
        if html.contains("gfycat.com") {
            print("🎬 MediaExtractor: Detected Gfycat embed")
            let result = extractGfycat(from: html)
            if let media = result {
                print("✅ MediaExtractor: Extracted Gfycat URL: \(media.url)")
            } else {
                print("❌ MediaExtractor: Failed to extract Gfycat URL")
                print("   HTML: \(html)")
            }
            return result
        }

        // Imgur (gifv/mp4)
        if html.contains("imgur.com") {
            print("🎬 MediaExtractor: Detected Imgur embed")
            let result = extractImgur(from: html)
            if let media = result {
                print("✅ MediaExtractor: Extracted Imgur URL: \(media.url)")
            } else {
                print("❌ MediaExtractor: Failed to extract Imgur URL")
                print("   HTML: \(html)")
            }
            return result
        }

        // Streamable
        if html.contains("streamable.com") {
            print("🎬 MediaExtractor: Detected Streamable embed (not supported)")
            return extractStreamable(from: html)
        }

        print("🎬 MediaExtractor: No supported service detected")
        return nil
    }

    // MARK: - Giphy

    private func extractGiphy(from html: String) -> ExtractedMedia? {
        // Giphy embed URLs: https://giphy.com/embed/ID or https://i.giphy.com/media/ID/giphy.gif

        // Try to extract GIF ID from embed URL
        if let gifId = extractPattern(from: html, pattern: "giphy\\.com/embed/([a-zA-Z0-9]+)") {
            // Construct direct GIF URL
            let gifUrl = "https://i.giphy.com/media/\(gifId)/giphy.gif"
            if let url = URL(string: gifUrl) {
                return ExtractedMedia(url: url, type: .gif, width: nil, height: nil)
            }
        }

        // Try direct i.giphy.com URLs
        if let directUrl = extractPattern(from: html, pattern: "(https://i\\.giphy\\.com/[^\"\\s]+\\.gif)") {
            if let url = URL(string: directUrl) {
                return ExtractedMedia(url: url, type: .gif, width: nil, height: nil)
            }
        }

        return nil
    }

    // MARK: - Redgifs

    private func extractRedgifs(from html: String) -> ExtractedMedia? {
        // Redgifs embed: https://www.redgifs.com/ifr/ID
        // Note: Redgifs requires using their API to get actual video URLs
        // Direct CDN URLs don't work without proper authentication

        if let gifId = extractPattern(from: html, pattern: "redgifs\\.com/ifr/([a-zA-Z0-9]+)") {
            print("🔍 MediaExtractor: Extracted Redgifs ID: \(gifId)")
            print("⚠️ MediaExtractor: Redgifs requires API call - falling back to iframe")
            // Return nil to use iframe embed instead
            // TODO: Implement Redgifs API v2 to get actual video URL
            return nil
        }

        // Try extracting direct video URLs from iframe src (unlikely to work)
        if let videoUrl = extractPattern(from: html, pattern: "(https://[^\"\\s]+redgifs[^\"\\s]+\\.mp4)") {
            print("🔍 MediaExtractor: Found direct Redgifs URL in iframe: \(videoUrl)")
            if let url = URL(string: videoUrl) {
                return ExtractedMedia(url: url, type: .video, width: nil, height: nil)
            }
        }

        return nil
    }

    // MARK: - Gfycat

    private func extractGfycat(from html: String) -> ExtractedMedia? {
        // Gfycat embed: https://gfycat.com/ifr/ID
        // Direct video: https://thumbs.gfycat.com/ID-mobile.mp4

        if let gifId = extractPattern(from: html, pattern: "gfycat\\.com/ifr/([a-zA-Z0-9]+)") {
            let mp4Url = "https://thumbs.gfycat.com/\(gifId)-mobile.mp4"
            if let url = URL(string: mp4Url) {
                return ExtractedMedia(url: url, type: .video, width: nil, height: nil)
            }
        }

        return nil
    }

    // MARK: - Imgur

    private func extractImgur(from html: String) -> ExtractedMedia? {
        // Imgur gifv: https://i.imgur.com/ID.gifv -> https://i.imgur.com/ID.mp4

        if let gifvUrl = extractPattern(from: html, pattern: "(https://i\\.imgur\\.com/[a-zA-Z0-9]+)\\.gifv") {
            let mp4Url = gifvUrl + ".mp4"
            if let url = URL(string: mp4Url) {
                return ExtractedMedia(url: url, type: .video, width: nil, height: nil)
            }
        }

        // Direct imgur mp4
        if let mp4Url = extractPattern(from: html, pattern: "(https://i\\.imgur\\.com/[a-zA-Z0-9]+\\.mp4)") {
            if let url = URL(string: mp4Url) {
                return ExtractedMedia(url: url, type: .video, width: nil, height: nil)
            }
        }

        return nil
    }

    // MARK: - Streamable

    private func extractStreamable(from html: String) -> ExtractedMedia? {
        // Streamable embed: https://streamable.com/e/ID
        // This would require an API call to get direct video URL
        // For now, return nil to use iframe
        return nil
    }

    // MARK: - Helper

    private func extractPattern(from string: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }

        let nsString = string as NSString
        let range = NSRange(location: 0, length: nsString.length)

        guard let match = regex.firstMatch(in: string, options: [], range: range) else {
            return nil
        }

        // Return first capture group if it exists, otherwise full match
        if match.numberOfRanges > 1 {
            return nsString.substring(with: match.range(at: 1))
        } else {
            return nsString.substring(with: match.range)
        }
    }
}
