//
//  ID3ChapterService.swift
//  Today
//
//  Extracts chapters from MP3 files using ID3 tags (CHAP/CTOC frames)
//

import Foundation
import OutcastID3
import UIKit

/// Service for extracting chapter information from MP3 files using ID3 tags
class ID3ChapterService {
    static let shared = ID3ChapterService()

    private init() {}

    /// Extracted chapter data from ID3 tags
    struct ID3Chapter {
        let id: String
        let title: String
        let startTime: TimeInterval  // in seconds
        let endTime: TimeInterval?   // in seconds
        let url: String?
        let image: UIImage?
    }

    /// Extract chapters from a remote MP3 URL
    /// Uses HTTP Range requests to download only the ID3 tag, not the entire file
    func extractChapters(from url: URL) async throws -> [ID3Chapter] {
        // ID3v2 tags are at the beginning of the file
        // First, fetch just the header (10 bytes) to get the tag size

        var headerRequest = URLRequest(url: url)
        headerRequest.setValue("bytes=0-9", forHTTPHeaderField: "Range")

        let (headerData, headerResponse) = try await URLSession.shared.data(for: headerRequest)

        // Check if server supports range requests
        let supportsRange = (headerResponse as? HTTPURLResponse)?.statusCode == 206

        guard headerData.count >= 10,
              headerData[0] == 0x49, // 'I'
              headerData[1] == 0x44, // 'D'
              headerData[2] == 0x33  // '3'
        else {
            print("📖 No ID3v2 tag found at start of file")
            return []
        }

        // Parse tag size from syncsafe integer (bytes 6-9)
        // Each byte only uses 7 bits (high bit is always 0)
        let size = (Int(headerData[6]) << 21) |
                   (Int(headerData[7]) << 14) |
                   (Int(headerData[8]) << 7) |
                   Int(headerData[9])

        let totalTagSize = size + 10 // Add 10 bytes for header
        print("📖 ID3v2 tag size: \(totalTagSize) bytes (\(totalTagSize / 1024) KB)")

        // Fetch just the ID3 tag data
        let tagData: Data
        if supportsRange {
            var tagRequest = URLRequest(url: url)
            tagRequest.setValue("bytes=0-\(totalTagSize - 1)", forHTTPHeaderField: "Range")
            let (data, _) = try await URLSession.shared.data(for: tagRequest)
            tagData = data
            print("📖 Downloaded ID3 tag only (range request)")
        } else {
            // Server doesn't support range requests - fall back to full download
            print("📖 Server doesn't support range requests, downloading full file")
            let (localURL, _) = try await URLSession.shared.download(from: url)
            defer { try? FileManager.default.removeItem(at: localURL) }
            return try extractChaptersFromLocalFile(at: localURL)
        }

        // Write tag data to a temporary file for OutcastID3
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp3")

        try tagData.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        return try extractChaptersFromLocalFile(at: tempURL)
    }

    /// Extract chapters from a local MP3 file
    func extractChaptersFromLocalFile(at url: URL) throws -> [ID3Chapter] {
        let mp3File = try OutcastID3.MP3File(localUrl: url)
        let id3Tag = try mp3File.readID3Tag()

        var chapters: [ID3Chapter] = []
        var tableOfContents: [String] = []

        // First pass: find table of contents for ordering
        for frame in id3Tag.tag.frames {
            if let tocFrame = frame as? OutcastID3.Frame.TableOfContentsFrame {
                tableOfContents = tocFrame.childElementIds
                print("📖 ID3: Found TOC with \(tableOfContents.count) chapters")
            }
        }

        // Second pass: extract chapter frames
        for frame in id3Tag.tag.frames {
            if let chapterFrame = frame as? OutcastID3.Frame.ChapterFrame {
                let chapter = parseChapterFrame(chapterFrame)
                chapters.append(chapter)
                let hasUrl = chapter.url != nil ? "🔗" : ""
                let hasImage = chapter.image != nil ? "🖼️" : ""
                print("📖 ID3: Found chapter '\(chapter.title)' at \(formatTime(chapter.startTime)) \(hasUrl)\(hasImage)")
                if let url = chapter.url {
                    print("   └─ URL: \(url)")
                }
            }
        }

        // Sort chapters by table of contents order, or by start time if no TOC
        if !tableOfContents.isEmpty {
            chapters.sort { chapter1, chapter2 in
                let index1 = tableOfContents.firstIndex(of: chapter1.id) ?? Int.max
                let index2 = tableOfContents.firstIndex(of: chapter2.id) ?? Int.max
                return index1 < index2
            }
        } else {
            chapters.sort { $0.startTime < $1.startTime }
        }

        print("📖 ID3: Extracted \(chapters.count) chapters total")
        return chapters
    }

    /// Parse a single chapter frame and its nested frames
    private func parseChapterFrame(_ chapterFrame: OutcastID3.Frame.ChapterFrame) -> ID3Chapter {
        // OutcastID3 already converts times to seconds (TimeInterval)
        let startTime = chapterFrame.startTime
        let endTime = chapterFrame.endTime > 0 ? chapterFrame.endTime : nil

        var title = "Chapter"
        var url: String? = nil
        var image: UIImage? = nil

        print("   📖 Parsing chapter '\(chapterFrame.elementId)' with \(chapterFrame.subFrames.count) subframes")

        // Extract nested frames (title, URL, artwork)
        for subFrame in chapterFrame.subFrames {
            // Log the frame type for debugging
            let frameType = String(describing: type(of: subFrame))
            print("      └─ SubFrame type: \(frameType)")

            // Check for title frame
            if let stringFrame = subFrame as? OutcastID3.Frame.StringFrame {
                print("         StringFrame: type=\(stringFrame.type), str='\(stringFrame.str)'")
                // TIT2 is the title frame
                if stringFrame.type == .title {
                    title = stringFrame.str
                }
            }

            // Check for URL frame (standard URL - WCOM, WCOP, WOAF, WOAR, WOAS, WORS, WPAY, WPUB)
            if let urlFrame = subFrame as? OutcastID3.Frame.UrlFrame {
                print("         UrlFrame: urlString='\(urlFrame.urlString)'")
                url = urlFrame.urlString
            }

            // Check for user-defined URL frame (WXXX) - commonly used for chapter links
            if let userUrlFrame = subFrame as? OutcastID3.Frame.UserUrlFrame {
                print("         UserUrlFrame: urlString='\(userUrlFrame.urlString)', description='\(userUrlFrame.urlDescription)'")
                url = userUrlFrame.urlString
            }

            // Check for picture frame (chapter artwork)
            if let pictureFrame = subFrame as? OutcastID3.Frame.PictureFrame {
                print("         PictureFrame: type=\(pictureFrame.pictureType), size=\(pictureFrame.picture.image.size)")
                image = pictureFrame.picture.image
            }

            // Check for raw/unknown frames
            if let rawFrame = subFrame as? OutcastID3.Frame.RawFrame {
                print("         RawFrame: identifier='\(rawFrame.frameIdentifier ?? "unknown")', dataSize=\(rawFrame.data.count) bytes")
            }
        }

        return ID3Chapter(
            id: chapterFrame.elementId,
            title: title,
            startTime: startTime,
            endTime: endTime,
            url: url,
            image: image
        )
    }

    /// Convert ID3Chapter to PodcastChapter
    func convertToPodcastChapters(_ id3Chapters: [ID3Chapter]) -> [PodcastChapter] {
        return id3Chapters.map { chapter in
            PodcastChapter(
                title: chapter.title,
                startTime: chapter.startTime,
                endTime: chapter.endTime,
                imageUrl: nil,  // We have imageData instead
                url: chapter.url
            )
        }
    }

    /// Get chapter artwork as UIImage
    func getChapterArtwork(for chapter: ID3Chapter) -> UIImage? {
        return chapter.image
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", minutes, secs)
    }
}
