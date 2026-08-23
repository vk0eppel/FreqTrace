//
//  PrototypeCriteriaTests.swift
//  FreqTraceTests
//
//  Ticket #36 (map #18): scores the PrototypeAnomalyDetector (the four-state
//  criteria + hotness trigger) against the #34 synthetic corpus, pins the
//  threshold intents, and shows it beats the baseline (5/7 -> 7/7). Results
//  written up in docs/research/anomaly-criteria-prototype.md.
//
//  Scored with a -25 dBFS detectability floor so latency measures real
//  climb-into-view time (the upgrade the #34 baseline doc flagged), matching
//  the prototype's own candidate floor.
//

import Foundation
import Testing
@testable import FreqTrace

struct PrototypeCriteriaTests {

    private let config = AnalysisConfig.default
    private var scorer: CorpusScorer { CorpusScorer(config: config, detectabilityFloorDb: -25) }

    private func scorePrototype(_ params: PrototypeParams) -> [CaseScore] {
        scorer.scoreAll(cases: AnomalyCorpus.cases) {
            PrototypeAnomalyDetector.makeProcess(params: params, config: config)
        }
    }

    private func score(number: Int, _ params: PrototypeParams) -> CaseScore {
        scorePrototype(params).first { $0.number == number }!
    }

    private func passCount(_ params: PrototypeParams) -> Int {
        scorePrototype(params).filter(\.verdict).count
    }

    private func passCount(detectFloorDb: Float) -> Int {
        var p = PrototypeParams.tuned; p.detectFloorDb = detectFloorDb; return passCount(p)
    }
    private func passCount(riseThresholdDb: Float) -> Int {
        var p = PrototypeParams.tuned; p.riseThresholdDb = riseThresholdDb; return passCount(p)
    }
    private func passCount(hotThresholdDb: Float) -> Int {
        var p = PrototypeParams.tuned; p.hotThresholdDb = hotThresholdDb; return passCount(p)
    }
    private func passCount(fallAwayDb: Float) -> Int {
        var p = PrototypeParams.tuned; p.fallAwayDb = fallAwayDb; return passCount(p)
    }

    // MARK: The intents, pinned by sweeping (not hand-set blind)

    /// The detectability floor is the genuinely tight, load-bearing knob:
    /// 7/7 only holds in a narrow window (~[-30, -22] dBFS). Too low and the
    /// hand-ramp's fast-dB phase is visible and false-flags; too high and a
    /// ring case is missed. This is the knob the corpus actually pins.
    @Test func detectabilityFloorIsTheTightlyConstrainedKnob() {
        for floor: Float in [-30, -27, -25, -22] {
            let n = passCount(detectFloorDb: floor)
            #expect(n == 7, "floor \(floor) should clear the corpus")
        }
        let tooLow = passCount(detectFloorDb: -40)
        let tooHigh = passCount(detectFloorDb: -18)
        #expect(tooLow < 7, "a low floor exposes the hand-ramp's fast-dB phase")
        #expect(tooHigh < 7, "too high a floor misses a ring case")
    }

    /// The rise amount is moderately constrained: 7/7 across ~[4, 7] dB over
    /// the window; below that it over-fires, above it starts missing.
    @Test func riseThresholdPassingBand() {
        for rise: Float in [4, 5, 6, 7] {
            let n = passCount(riseThresholdDb: rise)
            #expect(n == 7, "riseThreshold \(rise) should clear the corpus")
        }
        #expect(passCount(riseThresholdDb: 3) < 7, "too sensitive -> false flags")
        #expect(passCount(riseThresholdDb: 10) < 7, "too strict -> misses")
    }

    /// The hotness level is only loosely bounded by the synthetic corpus: any
    /// value between the moderate tone (~-14 dBFS) and the hot cases (~-1
    /// dBFS) works. -6 is a mid pick; -14 wrongly treats the moderate tone as
    /// hot.
    @Test func hotThresholdIsLooselyBounded() {
        for hot: Float in [-12, -8, -6, -2] {
            let n = passCount(hotThresholdDb: hot)
            #expect(n == 7, "hotThreshold \(hot) should clear the corpus")
        }
        #expect(passCount(hotThresholdDb: -14) < 7, "as low as the moderate tone -> flags it")
    }

    /// The fall-away margin is NOT constrained by the synthetic corpus at all
    /// -- the room mode's decay clears any reasonable value. A real
    /// steady-driven mode (only in the #37 capture tier) is what would pin it.
    @Test func fallAwayIsUnconstrainedBySyntheticCorpus() {
        for fall: Float in [2, 4, 8, 12, 20] {
            let n = passCount(fallAwayDb: fall)
            #expect(n == 7, "fallAway \(fall) should still clear the corpus")
        }
    }

    /// Grounds the "shape lever is the wrong tool" claim: with the lever on,
    /// the exponential ring-ups (1, 2) still PASS (straight line in dB) -- it
    /// is specifically the concave-down room-mode bloom (4) it wrongly
    /// rejects, not feedback.
    @Test func shapeLeverStillPassesExponentialRingUps() {
        var shapeOn = PrototypeParams.tuned
        shapeOn.requireNonDecelerating = true
        let ringUp = score(number: 1, shapeOn).flaggedTargetEver
        let saturate = score(number: 2, shapeOn).flaggedTargetEver
        #expect(ringUp == true)
        #expect(saturate == true)
    }

    // MARK: The pinned result

    /// The headline: the tuned criteria clear the entire synthetic corpus.
    @Test func tunedCriteriaClearTheWholeCorpus() {
        let scores = scorePrototype(.tuned)
        let passCount = scores.filter(\.verdict).count
        #expect(passCount == AnomalyCorpus.cases.count)
        #expect(passCount == 7)
    }

    /// The two baseline false positives are gone -- the anchoring bug (5) and
    /// the hand-ramp (7) no longer flag.
    @Test func tunedFixesTheBaselineFalsePositives() {
        let steadyTone = score(number: 5, .tuned).flaggedTargetEver
        let handRamp = score(number: 7, .tuned).flaggedTargetEver
        #expect(steadyTone == false)
        #expect(handRamp == false)
    }

    /// Zero false negatives on the must-flag set -- every ring case still
    /// caught (the hard gate).
    @Test func tunedStillCatchesEveryRingCase() {
        for number in [1, 2, 3, 4] {
            let flagged = score(number: number, .tuned).flaggedTargetEver
            #expect(flagged == true, "ring case \(number) must still flag")
        }
    }

    /// The catchable ring-up (1) is flagged within the ~500 ms bar.
    @Test func tunedFlagsTheRingUpWithinTheLatencyBar() {
        let latency = score(number: 1, .tuned).flagLatencyMs
        let withinBar = (latency ?? .greatestFiniteMagnitude) <= 500
        #expect(latency != nil)
        #expect(withinBar)
    }

    /// The room-mode signal (corpus number 4) is flagged while building —
    /// and its case-6 aspect holds too: the flag clears once it rings down
    /// (fall-away release), so `flaggedAtEnd` is false.
    @Test func tunedFlagsRoomModeWhileBuildingAndClearsOnDecay() {
        let mode = score(number: 4, .tuned)
        let flaggedEver = mode.flaggedTargetEver
        let flaggedAtEnd = mode.flaggedTargetAtEnd
        #expect(flaggedEver == true)
        #expect(flaggedAtEnd == false)
    }

    /// The whole point: the prototype beats today's detector on the same
    /// corpus (7/7 vs 5/7), fixing exactly the two false positives.
    @Test func tunedBeatsTheBaseline() {
        let prototype = scorePrototype(.tuned).filter(\.verdict).count
        let baseline = scorer.scoreAll(cases: AnomalyCorpus.cases) {
            BaselineDetector.makeProcess(config: config)
        }.filter(\.verdict).count
        #expect(prototype == 7)
        #expect(baseline == 5)
        #expect(prototype > baseline)
    }

    // MARK: Why the two refinement levers are NOT used (recorded findings)

    /// Plain "climb now" at a low floor still false-flags the hand-ramp (7):
    /// the ramp's fast-dB phase near silence trips the rise gate. This is why
    /// the pinned params raise the detectability floor to -25 dBFS rather
    /// than reaching for the accelerating-shape lever.
    @Test func simpleClimbAtALowFloorStillFalseFlagsTheHandRamp() {
        let handRampFlagged = score(number: 7, .simpleClimb).flaggedTargetEver
        #expect(handRampFlagged == true)
    }

    /// The accelerating-shape lever is the WRONG tool: a real room-mode bloom
    /// is concave-down (same shape as a hand-ramp), so requiring a
    /// non-decelerating climb rejects the room mode too (4) -- a false
    /// negative on a must-flag case. So the lever stays off.
    @Test func accelerationShapeLeverBreaksTheRoomModeBloom() {
        var shapeOn = PrototypeParams.tuned
        shapeOn.requireNonDecelerating = true
        let roomModeFlagged = score(number: 4, shapeOn).flaggedTargetEver
        #expect(roomModeFlagged == false)
    }

    /// Prints the tuned scorecard (visible in Xcode's console), mirrored in
    /// docs/research/anomaly-criteria-prototype.md.
    @Test func recordsPrototypeScorecard() {
        let scores = scorePrototype(.tuned)
        print("\n=== Prototype criteria scorecard (ticket #36, params = .tuned) ===")
        print(Scorecard.render(scores))
        print("=== end scorecard ===\n")
        #expect(scores.count == AnomalyCorpus.cases.count)
    }
}
