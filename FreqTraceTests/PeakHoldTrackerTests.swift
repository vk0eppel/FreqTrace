//
//  PeakHoldTrackerTests.swift
//  FreqTraceTests
//
//  Exercises PeakHoldTracker, the pure generic seam behind Peak (ticket
//  #12, CONTEXT.md "Peak"): a classic level-meter peak-hold -- the highest
//  value seen per key since the last manual reset, indefinite (never
//  auto-expiring). Shared by RTA bars (keyed by bar index) and the SPL /
//  Tracked Frequency level numeric readouts (keyed by a single scalar key),
//  rather than three separate implementations.
//

import Testing
@testable import FreqTrace

struct PeakHoldTrackerTests {

    @Test func peakStartsAtNilBeforeAnyUpdate() {
        let tracker = PeakHoldTracker<Int>()

        #expect(tracker.peak(for: 0) == nil)
    }

    @Test func firstUpdateBecomesThePeak() {
        var tracker = PeakHoldTracker<Int>()

        tracker.update(3.0, for: 0)

        #expect(tracker.peak(for: 0) == 3.0)
    }

    @Test func aLowerUpdateDoesNotLowerTheHeldPeak() {
        var tracker = PeakHoldTracker<Int>()

        tracker.update(5.0, for: 0)
        tracker.update(2.0, for: 0)

        #expect(tracker.peak(for: 0) == 5.0)
    }

    @Test func aHigherUpdateRaisesTheHeldPeak() {
        var tracker = PeakHoldTracker<Int>()

        tracker.update(2.0, for: 0)
        tracker.update(5.0, for: 0)

        #expect(tracker.peak(for: 0) == 5.0)
    }

    @Test func resetClearsAllHeldPeaks() {
        var tracker = PeakHoldTracker<Int>()
        tracker.update(5.0, for: 0)
        tracker.update(7.0, for: 1)

        tracker.reset()

        #expect(tracker.peak(for: 0) == nil)
        #expect(tracker.peak(for: 1) == nil)
    }

    @Test func differentKeysHoldIndependentPeaks() {
        var tracker = PeakHoldTracker<Int>()

        tracker.update(1.0, for: 0)
        tracker.update(9.0, for: 1)

        #expect(tracker.peak(for: 0) == 1.0)
        #expect(tracker.peak(for: 1) == 9.0)
    }
}
