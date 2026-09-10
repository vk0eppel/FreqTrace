//
//  RecentAnomalyTrackerTests.swift
//  FreqTraceTests
//
//  Exercises RecentAnomalyTracker, the pure seam behind the RECENT column
//  beside LIVE in the Measured Data row's anomaly block (user request): a
//  cleared Anomaly Candidate is kept, dimmed, so a tech can still read a ring
//  that settled too fast to catch live. Deduped by frequency, most-recent-
//  first, capped, carrying the loudest level each candidate reached.
//
//  This is the feature's only practical test seam -- observing it live needs a
//  real narrowband tone to ring up and then settle through the mic.
//

import Testing
@testable import FreqTrace

struct RecentAnomalyTrackerTests {
    private func candidate(_ hz: Double, _ severityDb: Float) -> AnomalyCandidate {
        AnomalyCandidate(frequencyHz: hz, severityDb: severityDb)
    }

    @Test func startsEmpty() {
        let tracker = RecentAnomalyTracker(maxCount: 3)

        #expect(tracker.candidates.isEmpty)
    }

    @Test func aStillLiveCandidateIsNotYetRecent() {
        var tracker = RecentAnomalyTracker(maxCount: 3)

        tracker.update(live: [candidate(1000, -10)])

        #expect(tracker.candidates.isEmpty)
    }

    @Test func aClearedCandidateBecomesRecent() {
        var tracker = RecentAnomalyTracker(maxCount: 3)

        tracker.update(live: [candidate(1000, -10)])
        tracker.update(live: [])   // rang down / settled

        #expect(tracker.candidates.map(\.id) == [1000])
    }

    @Test func recentCarriesTheLoudestLevelReachedWhileLive() {
        var tracker = RecentAnomalyTracker(maxCount: 3)

        tracker.update(live: [candidate(1000, -20)])
        tracker.update(live: [candidate(1000, -6)])    // peak
        tracker.update(live: [candidate(1000, -14)])   // falling but still live
        tracker.update(live: [])                        // cleared

        #expect(tracker.candidates.first?.peakDb == -6)
    }

    @Test func mostRecentClearedIsFirst() {
        var tracker = RecentAnomalyTracker(maxCount: 3)

        tracker.update(live: [candidate(1000, -10)])
        tracker.update(live: [])                        // 1000 clears first
        tracker.update(live: [candidate(2000, -8)])
        tracker.update(live: [])                        // 2000 clears second

        #expect(tracker.candidates.map(\.id) == [2000, 1000])
    }

    @Test func aReRingLeavesRecentThenReturnsToTheFrontWhenClearedAgain() {
        var tracker = RecentAnomalyTracker(maxCount: 3)

        tracker.update(live: [candidate(1000, -10)])
        tracker.update(live: [])                        // 1000 -> recent
        tracker.update(live: [candidate(2000, -8)])
        tracker.update(live: [])                        // recent: [2000, 1000]
        #expect(tracker.candidates.map(\.id) == [2000, 1000])

        tracker.update(live: [candidate(1000, -5)])     // 1000 re-rings, leaves recent
        #expect(tracker.candidates.map(\.id) == [2000])

        tracker.update(live: [])                        // 1000 clears again -> front
        #expect(tracker.candidates.map(\.id) == [1000, 2000])
        #expect(tracker.candidates.first?.peakDb == -5)
    }

    @Test func noDuplicateEntriesForTheSameFrequency() {
        var tracker = RecentAnomalyTracker(maxCount: 3)

        tracker.update(live: [candidate(1000, -10)])
        tracker.update(live: [])
        tracker.update(live: [candidate(1000, -7)])
        tracker.update(live: [])

        #expect(tracker.candidates.map(\.id) == [1000])
        #expect(tracker.candidates.first?.peakDb == -7)
    }

    @Test func oldestDropsOffWhenOverCapacity() {
        var tracker = RecentAnomalyTracker(maxCount: 3)

        for hz in [1000.0, 2000, 3000, 4000] {
            tracker.update(live: [candidate(hz, -10)])
            tracker.update(live: [])
        }

        // Newest three kept, oldest (1000) dropped, most-recent first.
        #expect(tracker.candidates.map(\.id) == [4000, 3000, 2000])
    }

    @Test func simultaneouslyClearedAreOrderedLoudestFirst() {
        var tracker = RecentAnomalyTracker(maxCount: 3)

        tracker.update(live: [candidate(1000, -20), candidate(2000, -6)])
        tracker.update(live: [])   // both clear the same hop

        #expect(tracker.candidates.map(\.id) == [2000, 1000])
    }

    @Test func resetClearsHistoryAndLiveTracking() {
        var tracker = RecentAnomalyTracker(maxCount: 3)
        tracker.update(live: [candidate(1000, -10)])
        tracker.update(live: [])
        #expect(!tracker.candidates.isEmpty)

        tracker.reset()
        #expect(tracker.candidates.isEmpty)

        // After reset, a candidate that was mid-flight before the reset must
        // not resurrect: clearing it now (never re-seen as live) adds nothing.
        tracker.update(live: [])
        #expect(tracker.candidates.isEmpty)
    }
}
