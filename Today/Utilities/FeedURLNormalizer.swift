//
//  FeedURLNormalizer.swift
//  Today
//
//  The single definition of the form a feed URL is stored in.
//
//  This exists because the normalisation used to live only inside `FeedManager.addFeed`, while
//  OPML sync compared URLs as listed in the remote document. A subscription listing
//  `http://techcrunch.com/feed/` therefore never matched the feed stored as
//  `https://techcrunch.com/feed/`: every sync the feed looked missing (deactivated) and the
//  OPML entry looked new (re-added), producing endless "+N added, -N deactivated" churn and
//  leaving the feeds deactivated, which silently stopped them syncing.
//
//  Anything that compares a feed URL against a stored feed must canonicalise both sides
//  through here.
//

import Foundation

enum FeedURLNormalizer {

    /// Domains known not to support HTTPS. They have ATS exceptions in Info.plist, so they must
    /// keep their `http://` scheme rather than being upgraded.
    static let httpOnlyDomains: Set<String> = ["data.feedland.org", "scripting.com"]

    /// The canonical stored form of a feed URL.
    ///
    /// Applies the same two transforms `FeedManager.addFeed` applies before persisting a feed:
    /// an `http://` → `https://` upgrade (except for the exempt domains above), and Reddit's
    /// `.json` rewrite.
    ///
    /// This is a pure string transform and says nothing about whether the URL is safe to
    /// fetch — it is also used to compare URLs, where returning nil would be wrong. Anything
    /// *ingesting* a URL (OPML `xmlUrl`, `addFeed`) must go through
    /// `SafeURL.feedIngestable(_:)` instead, which applies the scheme allow-list and then
    /// canonicalises through here.
    nonisolated static func canonical(_ url: String) -> String {
        convertRedditURLToJSON(upgradingScheme(url))
    }

    /// `http://` → `https://` — most servers support it and ATS blocks plain HTTP.
    nonisolated static func upgradingScheme(_ url: String) -> String {
        guard url.lowercased().hasPrefix("http://") else { return url }

        let host = URL(string: url)?.host?.lowercased() ?? ""
        let isHTTPOnly = httpOnlyDomains.contains(host)
            || httpOnlyDomains.contains(where: { host.hasSuffix(".\($0)") })
        guard !isHTTPOnly else { return url }

        return "https://" + url.dropFirst("http://".count)
    }

    /// Reddit URLs are fetched as JSON:
    /// `reddit.com/r/x.rss` → `reddit.com/r/x.json`, and `reddit.com/r/x` → `reddit.com/r/x.json`.
    nonisolated static func convertRedditURLToJSON(_ url: String) -> String {
        var urlString = url

        if urlString.contains("reddit.com/r/") && urlString.hasSuffix(".rss") {
            urlString = urlString.replacingOccurrences(of: ".rss", with: ".json")
        } else if urlString.contains("reddit.com/r/") && !urlString.hasSuffix(".json") {
            if urlString.hasSuffix("/") {
                urlString = String(urlString.dropLast())
            }
            urlString += ".json"
        }

        return urlString
    }
}
