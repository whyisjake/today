//
//  PerformanceSignpostsTests.swift
//  TodayTests
//
//  Tests for the Perf instrumentation wrapper.
//
//  Note on scope: OSSignposter does not expose emitted signposts for inspection, so
//  these tests cover what is actually verifiable — that instrumentation is transparent
//  to the code it wraps (values pass through, errors propagate, cancellation-abandoned
//  intervals don't corrupt later ones) and that the phase table has no name collisions.
//  Whether intervals appear correctly on the Instruments timeline is verified manually.
//

import XCTest
@testable import Today

final class PerformanceSignpostsTests: XCTestCase {

    // MARK: - Transparency: measure must not alter the wrapped work

    func testMeasureReturnsBodyValue() {
        let result = Perf.measure(.articleListDerivation) { 42 }
        XCTAssertEqual(result, 42)
    }

    func testMeasurePropagatesThrownError() {
        struct Boom: Error {}

        XCTAssertThrowsError(
            try Perf.measure(.articleListDerivation) { throw Boom() }
        ) { error in
            XCTAssertTrue(error is Boom, "measure must rethrow the body's error unchanged")
        }
    }

    func testMeasureAsyncReturnsBodyValue() async {
        let result = await Perf.measureAsync(.syncTotal) { "done" }
        XCTAssertEqual(result, "done")
    }

    func testMeasureAsyncPropagatesThrownError() async {
        struct Boom: Error {}

        do {
            _ = try await Perf.measureAsync(.syncTotal) { throw Boom() }
            XCTFail("measureAsync should have rethrown")
        } catch {
            XCTAssertTrue(error is Boom, "measureAsync must rethrow the body's error unchanged")
        }
    }

    func testMeasureEndsIntervalEvenWhenBodyThrows() {
        // The interval is ended via `defer`, so a throwing body must not leave it open.
        // If this leaked, the following measure on the same phase would misbehave.
        struct Boom: Error {}
        _ = try? Perf.measure(.syncInsert) { throw Boom() }

        let result = Perf.measure(.syncInsert) { "still works" }
        XCTAssertEqual(result, "still works")
    }

    // MARK: - Abandoned intervals

    func testAbandonedIntervalDoesNotAffectLaterIntervalOfSamePhase() {
        // Simulates a cancelled task: begin without a matching end.
        _ = Perf.begin(.syncFetchParse, "abandoned")

        // A fresh interval on the same phase must still open and close cleanly.
        let second = Perf.begin(.syncFetchParse, "second")
        Perf.end(second)

        let third = Perf.measure(.syncFetchParse) { 7 }
        XCTAssertEqual(third, 7, "an abandoned interval must not corrupt later intervals")
    }

    func testOverlappingIntervalsOfSamePhaseAreIndependent() {
        let first = Perf.begin(.syncFeedFetch, "feed-a")
        let second = Perf.begin(.syncFeedFetch, "feed-b")

        // Ending out of order must be safe — each interval carries its own signpost ID.
        Perf.end(second)
        Perf.end(first)
    }

    // MARK: - Phase table integrity

    func testEveryPhaseHasANonEmptyName() {
        for phase in PerfPhase.allCases {
            let name = String(describing: phase.name)
            XCTAssertFalse(name.isEmpty, "\(phase) has an empty signpost name")
        }
    }

    func testPhaseNamesAreUnique() {
        // Guards against copy-paste collisions in the name switch, which would make two
        // different phases indistinguishable on the timeline.
        let names = PerfPhase.allCases.map { String(describing: $0.name) }
        XCTAssertEqual(
            names.count,
            Set(names).count,
            "duplicate signpost names found: \(names.sorted())"
        )
    }

    func testEveryPhaseHasAPositiveLogThreshold() {
        for phase in PerfPhase.allCases {
            XCTAssertGreaterThan(
                phase.logThreshold,
                .zero,
                "\(phase) has a non-positive log threshold, which would log every call"
            )
        }
    }

    // MARK: - Point events

    func testEventAndLogDoNotCrash() {
        // Smoke coverage: these are fire-and-forget, but a malformed interpolation
        // would trap at runtime rather than fail to compile.
        Perf.event(.syncTotal, "every feed failed")
        Perf.log("sync completed")
        Perf.logError("sync error")
    }
}
