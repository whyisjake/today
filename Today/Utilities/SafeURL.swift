//
//  SafeURL.swift
//  Today
//
//  The single scheme allow-list for feed-controlled URLs.
//
//  Every URL the app opens, loads into a WKWebView, or ingests as a subscription originates in
//  attacker-controlled content: an RSS `<link>`, a Reddit link href, an OPML `xmlUrl`, an ID3
//  chapter URL. `URL(string:)` happily accepts `file:`, `data:`, `javascript:`, `ftp:` and any
//  custom app scheme, and `NSWorkspace.shared.open` / `UIApplication.shared.open` will act on
//  all of them — on macOS that is a sandbox pivot, not just a bad link.
//
//  So: nothing gets opened, loaded or stored unless its scheme is on the list here.
//
//  Note on isolation: this module builds with SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor, so
//  every member has to be explicitly `nonisolated` — the ingestion callers (FeedURLNormalizer,
//  OPML sync) are nonisolated and could not otherwise reach it. Same reason
//  `FeedURLNormalizer.canonical` is annotated.
//

import Foundation

enum SafeURL {

    /// The only schemes any feed-controlled URL may carry.
    ///
    /// `http` is on the list because it has to be: the domains in
    /// `FeedURLNormalizer.httpOnlyDomains` do not support HTTPS and have ATS exceptions, so
    /// their feeds are legitimately fetched and opened over plain HTTP. Everything else —
    /// `file`, `data`, `javascript`, `ftp`, `tel`, `facetime`, custom app schemes — is refused.
    nonisolated static let allowedSchemes: Set<String> = ["http", "https"]

    /// True when the URL carries an allow-listed scheme (compared case-insensitively, so
    /// `HTTP://example.com` passes).
    nonisolated static func isAllowed(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return allowedSchemes.contains(scheme)
    }

    /// The URL to hand to `openURL` / `UIApplication.open` / `NSWorkspace.open` /
    /// `webView.load(URLRequest:)`, or nil if it must not be acted on.
    nonisolated static func webOpenable(_ string: String?) -> URL? {
        guard let string, !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let url = URL(string: string) else { return nil }
        return webOpenable(url)
    }

    /// Overload for a URL that already exists — e.g. `navigationAction.request.url`.
    nonisolated static func webOpenable(_ url: URL?) -> URL? {
        guard let url, isAllowed(url) else { return nil }
        return url
    }

    /// The canonical form of a feed/OPML URL that is safe to store and fetch, or nil.
    ///
    /// This is the ingestion gate, kept separate from `FeedURLNormalizer.canonical` so that
    /// canonicalisation keeps its non-optional signature (it has many call sites, including
    /// pure string comparisons). Apply this wherever an externally-supplied `xmlUrl` first
    /// enters the app, so a `file:///etc/passwd` entry never reaches `URLSession` or the store.
    nonisolated static func feedIngestable(_ string: String) -> String? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = URL(string: trimmed), isAllowed(url) else { return nil }

        // Canonicalise only after the scheme check: the upgrade/Reddit rewrites assume a web URL.
        let canonical = FeedURLNormalizer.canonical(trimmed)

        // The rewrite is textual, so re-check rather than assume it preserved the scheme.
        guard let canonicalURL = URL(string: canonical), isAllowed(canonicalURL) else { return nil }
        return canonical
    }
}
