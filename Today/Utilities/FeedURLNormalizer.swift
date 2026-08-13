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
        convertRedditURLToRSS(upgradingScheme(url))
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

    /// Reddit URLs are fetched as RSS:
    /// `reddit.com/r/x.json` → `reddit.com/r/x.rss`, and `reddit.com/r/x` → `reddit.com/r/x.rss`.
    ///
    /// This used to rewrite the other way, to `.json`. Reddit now answers unauthenticated
    /// `.json` endpoints with 403 and an HTML block page, and has said the shutdown is
    /// deliberate ("Deprecating unauthenticated JSON access", r/modnews). Every `.json` shape
    /// is refused — `/r/x.json`, `/r/x/.json`, www, old and api hosts alike — so the rewrite
    /// was turning a working endpoint into a blocked one. `.rss` still answers 200.
    ///
    /// The RSS path is not a strict downgrade for the feed itself: `RSSParser` already extracts
    /// the subreddit, comments URL and post ID from Reddit RSS, so the badge and permalink
    /// survive. Comment *threads* do need the JSON API and are not available this way.
    nonisolated static func convertRedditURLToRSS(_ url: String) -> String {
        guard url.contains("reddit.com/r/") else { return url }

        if url.hasSuffix(".rss") { return url }

        if url.hasSuffix(".json") {
            // Covers both `/r/x.json` and the `/r/x/.json` shape the default feeds shipped with.
            let withoutSuffix = String(url.dropLast(".json".count))
            let trimmed = withoutSuffix.hasSuffix("/") ? String(withoutSuffix.dropLast()) : withoutSuffix
            return trimmed + ".rss"
        }

        let trimmed = url.hasSuffix("/") ? String(url.dropLast()) : url
        return trimmed + ".rss"
    }
}
