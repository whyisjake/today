//
//  ScreenUtilities.swift
//  Today
//
//  Cross-platform screen dimension utilities
//

import SwiftUI

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct ScreenUtilities {
    /// Returns the main screen width
    static var mainScreenWidth: CGFloat {
        #if os(iOS)
        UIScreen.main.bounds.width
        #elseif os(macOS)
        NSScreen.main?.frame.width ?? 1280
        #endif
    }

    /// Returns the main screen height
    static var mainScreenHeight: CGFloat {
        #if os(iOS)
        UIScreen.main.bounds.height
        #elseif os(macOS)
        NSScreen.main?.frame.height ?? 800
        #endif
    }

    /// Returns the main screen bounds
    static var mainScreenBounds: CGRect {
        #if os(iOS)
        UIScreen.main.bounds
        #elseif os(macOS)
        NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 1280, height: 800)
        #endif
    }

    /// Returns the main screen scale factor
    static var mainScreenScale: CGFloat {
        #if os(iOS)
        UIScreen.main.scale
        #elseif os(macOS)
        NSScreen.main?.backingScaleFactor ?? 2.0
        #endif
    }
}
