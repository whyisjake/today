//
//  HostThrottle.swift
//  Today
//
//  Per-host request pacing, so one strict host cannot fail a whole sync.
//

import Foundation

/// Spaces out requests to the same host, and backs off when a host says 429.
///
/// Reddit is why this exists. `BackgroundFeedSync` keeps five fetches in flight, and a store
/// with eighteen Reddit feeds fires all of them at `www.reddit.com` within a second or two.
/// Reddit answers the first and 429s the rest, so most Reddit feeds silently stopped updating
/// while every other host was fine. Reddit's RSS limit is strict enough that a second request
/// arriving immediately after a success is often refused.
///
/// Deliberately per-host rather than global: feeds on different hosts never wait for each
/// other, so a typical sync is unaffected. Only hosts that actually need pacing pay for it.
///
/// An actor, so the timestamps are safe to touch from the `@concurrent` fetch phase.
actor HostThrottle {
    static let shared = HostThrottle()

    /// Minimum gap between two requests to the same host.
    ///
    /// Most hosts need none. `reddit.com` does — measured: a burst of RSS requests gets one 200
    /// and then 429s.
    private static let intervals: [String: TimeInterval] = [
        "reddit.com": 2.0
    ]

    /// How long to stand down after a 429 that carried no `Retry-After`.
    private static let defaultBackoff: TimeInterval = 30

    private var nextAllowed: [String: Date] = [:]

    /// The throttling key for a URL: the registrable domain, so `www.reddit.com`,
    /// `old.reddit.com` and `reddit.com` share one budget — they are one service.
    nonisolated static func key(for url: URL) -> String? {
        guard let host = url.host?.lowercased() else { return nil }
        for domain in intervals.keys where host == domain || host.hasSuffix("." + domain) {
            return domain
        }
        return nil
    }

    /// Wait until this host is willing to hear from us again.
    ///
    /// A no-op for hosts with no configured interval, which is nearly all of them.
    func waitForTurn(_ url: URL) async {
        guard let key = Self.key(for: url), let interval = Self.intervals[key] else { return }

        let now = Date()
        let readyAt = nextAllowed[key] ?? now
        // Reserve this host before suspending, so concurrent callers queue behind each other
        // rather than all reading the same slot and firing together.
        nextAllowed[key] = max(readyAt, now).addingTimeInterval(interval)

        let delay = readyAt.timeIntervalSince(now)
        guard delay > 0 else { return }

        Perf.log("⏳ [Throttle] \(key): waiting \(String(format: "%.1f", delay))s")
        try? await Task.sleep(for: .seconds(delay))
    }

    /// Record a 429 so the next request to this host waits out the penalty.
    ///
    /// `Retry-After` is honoured when present (seconds form), since that is the host telling us
    /// exactly how long it wants; otherwise a fixed stand-down applies.
    func penalize(_ url: URL, retryAfter: String?) {
        guard let key = Self.key(for: url) else { return }

        let backoff = retryAfter.flatMap(TimeInterval.init) ?? Self.defaultBackoff
        let until = Date().addingTimeInterval(backoff)
        nextAllowed[key] = max(nextAllowed[key] ?? until, until)
        Perf.logError("⏳ [Throttle] \(key): 429 — backing off \(String(format: "%.0f", backoff))s")
    }

    /// Testing seam: forget all recorded state.
    func reset() {
        nextAllowed.removeAll()
    }
}
