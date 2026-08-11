//
//  PerformanceSignposts.swift
//  Today
//
//  Centralized OSSignposter instrumentation for launch, sync, and article-list
//  derivation.
//
//  Why signposts instead of print/CFAbsoluteTimeGetCurrent: intervals show up on the
//  Instruments timeline alongside the main-thread trace, and they cost effectively
//  nothing when nothing is recording — so they are safe to leave in release builds.
//  A `print` costs string formatting unconditionally and is invisible in Instruments.
//

import Foundation
import os

/// The phases we measure. Keep this list small and meaningful — a signpost nobody
/// reads is just noise on the timeline.
enum PerfPhase: CaseIterable {
    // Launch
    case appInit
    case defaultFeedSetup
    case databaseMigration
    case plainTextBackfill

    // Sync
    case syncTotal
    case syncFetchParse
    case syncFeedFetch
    case syncInsert
    case syncOPML

    // Read path
    case articleListDerivation
    case articleCountAggregate

    var name: StaticString {
        switch self {
        case .appInit: return "app-init"
        case .defaultFeedSetup: return "default-feed-setup"
        case .databaseMigration: return "database-migration"
        case .plainTextBackfill: return "plain-text-backfill"
        case .syncTotal: return "sync-total"
        case .syncFetchParse: return "sync-fetch-parse"
        case .syncFeedFetch: return "sync-feed-fetch"
        case .syncInsert: return "sync-insert"
        case .syncOPML: return "sync-opml"
        case .articleListDerivation: return "article-list-derivation"
        case .articleCountAggregate: return "article-count-aggregate"
        }
    }

    /// Durations above this are logged to Console as well as emitted as a signpost, so
    /// a regression is visible without attaching Instruments. Mirrors the 10ms threshold
    /// that was already being applied by hand in ContentView.
    var logThreshold: Duration {
        switch self {
        case .articleListDerivation, .articleCountAggregate:
            return .milliseconds(10)
        case .appInit, .defaultFeedSetup:
            return .milliseconds(50)
        default:
            return .milliseconds(250)
        }
    }
}

/// Performance instrumentation entry point.
///
/// Typical use:
/// ```
/// let result = Perf.measure(.articleListDerivation) { derive() }
/// ```
/// or, when the work spans suspension points:
/// ```
/// await Perf.measureAsync(.syncTotal) { await sync() }
/// ```
/// For work whose begin and end are not lexically adjacent, use `begin`/`end`.
enum Perf {
    private static let subsystem = "com.today"

    static let signposter = OSSignposter(subsystem: subsystem, category: "performance")
    private static let logger = Logger(subsystem: subsystem, category: "performance")

    /// A single in-flight interval.
    ///
    /// Each interval carries its own signpost ID, so overlapping or abandoned intervals
    /// with the same phase name cannot be confused for one another. An interval that is
    /// begun and never ended (a cancelled task, an early return) simply never emits its
    /// end event — it holds no shared state and cannot corrupt a later interval.
    struct Interval {
        let phase: PerfPhase
        fileprivate let id: OSSignpostID
        fileprivate let state: OSSignpostIntervalState
        fileprivate let started: ContinuousClock.Instant
    }

    // MARK: - Interval API

    static func begin(_ phase: PerfPhase, _ message: String? = nil) -> Interval {
        let id = signposter.makeSignpostID()
        let state: OSSignpostIntervalState
        if let message {
            state = signposter.beginInterval(phase.name, id: id, "\(message, privacy: .public)")
        } else {
            state = signposter.beginInterval(phase.name, id: id)
        }
        return Interval(phase: phase, id: id, state: state, started: .now)
    }

    static func end(_ interval: Interval, _ message: String? = nil) {
        let elapsed = ContinuousClock.Instant.now - interval.started

        if let message {
            signposter.endInterval(interval.phase.name, interval.state, "\(message, privacy: .public)")
        } else {
            signposter.endInterval(interval.phase.name, interval.state)
        }

        guard elapsed > interval.phase.logThreshold else { return }
        let name = String(describing: interval.phase.name)
        let ms = Double(elapsed.components.attoseconds) / 1e15
            + Double(elapsed.components.seconds) * 1000
        if let message {
            logger.info("⏱️ \(name, privacy: .public) took \(ms, format: .fixed(precision: 1))ms — \(message, privacy: .public)")
        } else {
            logger.info("⏱️ \(name, privacy: .public) took \(ms, format: .fixed(precision: 1))ms")
        }
    }

    // MARK: - Scoped measurement

    @discardableResult
    static func measure<T>(_ phase: PerfPhase, _ message: String? = nil, _ body: () throws -> T) rethrows -> T {
        let interval = begin(phase, message)
        defer { end(interval) }
        return try body()
    }

    @discardableResult
    static func measureAsync<T>(
        _ phase: PerfPhase,
        _ message: String? = nil,
        _ body: () async throws -> T
    ) async rethrows -> T {
        let interval = begin(phase, message)
        defer { end(interval) }
        return try await body()
    }

    // MARK: - Point events

    /// A one-off marker on the timeline — use for things with no duration, like
    /// "sync decided every feed failed".
    static func event(_ phase: PerfPhase, _ message: String) {
        signposter.emitEvent(phase.name, "\(message, privacy: .public)")
        logger.info("\(String(describing: phase.name), privacy: .public): \(message, privacy: .public)")
    }

    /// Durable log line for outcomes worth keeping regardless of whether Instruments
    /// is attached. Replaces the `print` calls that were on the sync path.
    static func log(_ message: String) {
        logger.info("\(message, privacy: .public)")
    }

    static func logError(_ message: String) {
        logger.error("\(message, privacy: .public)")
    }
}
