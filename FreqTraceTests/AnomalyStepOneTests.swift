//
//  AnomalyStepOneTests.swift
//  FreqTraceTests
//
//  Step 1 of the room-free continuation (#37 partial): extend the synthetic
//  tier to pin the intents the core corpus left loose -- the harmonic gate,
//  the hotness lower bound, and the fall-away lower bound -- none of which
//  need a real room. See docs/research/anomaly-criteria-prototype.md.
//

import Foundation
import Testing
@testable import FreqTrace

struct AnomalyStepOneTests {

    private let config = AnalysisConfig.default
    private var scorer: CorpusScorer { CorpusScorer(config: config, detectabilityFloorDb: -25) }

    private func score(_ testCase: CorpusCase, _ params: PrototypeParams) -> CaseScore {
        scorer.score(testCase, process: PrototypeAnomalyDetector.makeProcess(params: params, config: config))
    }

    // MARK: Harmonic gate — decided: keep binary

    /// The binary harmonic gate is load-bearing: a musical crescendo (rising
    /// fundamental + harmonics) would trip the rise trigger without it, and
    /// the gate is exactly what keeps it out.
    @Test func harmonicGateIsLoadBearingForAMusicalCrescendo() {
        var gateOff = PrototypeParams.tuned
        gateOff.harmonicGateEnabled = false
        let withGate = score(AnomalyCorpus.musicNoteCrescendo, .tuned).flaggedTargetEver
        let withoutGate = score(AnomalyCorpus.musicNoteCrescendo, gateOff).flaggedTargetEver
        #expect(withGate == false, "the harmonic gate must keep a rising musical note out")
        #expect(withoutGate == true, "without the gate the rising fundamental trips the rise trigger")
    }

    /// The tuned criteria (binary gate) correctly reject the music note --
    /// the corpus's first harmonically-rich must-not-flag case.
    @Test func tunedRejectsTheMusicNote() {
        let verdict = score(AnomalyCorpus.musicNoteCrescendo, .tuned).verdict
        #expect(verdict == true)
    }

    // MARK: Hotness lower bound — pinned by a loud steady tone

    /// A deliberately loud but steady −8 dBFS tone must not flag: it never
    /// rises, and the hotness trigger must sit above it. Drop the hotness
    /// threshold below the tone's level and it false-flags — so the tone pins
    /// the hotness lower bound above ~−8 dBFS.
    @Test func loudSteadyTonePinsTheHotnessLowerBound() {
        var hotTooLow = PrototypeParams.tuned
        hotTooLow.hotThresholdDb = -9
        let atTuned = score(AnomalyCorpus.loudSteadyTone, .tuned).flaggedTargetEver
        let atTooLow = score(AnomalyCorpus.loudSteadyTone, hotTooLow).flaggedTargetEver
        #expect(atTuned == false, "a -8 dBFS steady tone must not hot-flag at hotness -6")
        #expect(atTooLow == true, "dropping hotness below the tone's level false-flags it")
    }

    // MARK: Fall-away lower bound — pinned by a transient dip

    /// Saturated feedback that briefly ducks ~7 dB must stay flagged through
    /// the dip. With the tuned 8 dB margin it survives; shrink the margin
    /// below the dip and the flag is wrongly released — so the dip pins the
    /// fall-away lower bound above a transient duck.
    @Test func transientDipPinsTheFallAwayLowerBound() {
        var fallTooSmall = PrototypeParams.tuned
        fallTooSmall.fallAwayDb = 4
        let atTuned = score(AnomalyCorpus.feedbackWithDip, .tuned).flaggedTargetAtEnd
        let atTooSmall = score(AnomalyCorpus.feedbackWithDip, fallTooSmall).flaggedTargetAtEnd
        #expect(atTuned == true, "an 8 dB margin survives a ~7 dB dip")
        #expect(atTooSmall == false, "a 4 dB margin wrongly releases feedback on a transient dip")
    }
}
