//
//  PlatformTypes.swift
//  Today
//
//  Cross-platform type aliases for iOS/macOS compatibility
//

#if os(iOS)
import UIKit
public typealias PlatformImage = UIImage
public typealias PlatformColor = UIColor
#elseif os(macOS)
import AppKit
public typealias PlatformImage = NSImage
public typealias PlatformColor = NSColor

extension NSImage {
    /// Provides UIImage-compatible pngData() method for NSImage
    func pngData() -> Data? {
        guard let tiffRepresentation = tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: tiffRepresentation) else {
            return nil
        }
        return bitmapImage.representation(using: .png, properties: [:])
    }

    /// Provides UIImage-compatible jpegData(compressionQuality:) method for NSImage
    func jpegData(compressionQuality: CGFloat) -> Data? {
        guard let tiffRepresentation = tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: tiffRepresentation) else {
            return nil
        }
        return bitmapImage.representation(using: .jpeg, properties: [.compressionFactor: compressionQuality])
    }
}
#endif
