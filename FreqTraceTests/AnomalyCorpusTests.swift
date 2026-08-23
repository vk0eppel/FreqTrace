//
//  AnomalyCorpusTests.swift
//  FreqTraceTests
//
//  Ticket #34 (map #18): builds the synthetic anomaly-candidate validation
//  corpus + a scoring harness, and records the BASELINE scorecard of
//  today's detector against it. The baseline is expected to FAIL the two
//  false-positive cases -- the steady test tone (5, the anchoring bug) and
//  the hand-ramped tone (7) -- while passing the must-flag ring cases. That
//  gap is the number the #36 criteria prototype has to beat.
//
//  See AnomalyScoring.swift for how each case's amplitude envelope becomes a
//  per-hop magnitude spectrum, and why (roundoff artifact) this synthesizes
//  spectra directly rather than FFT-ing a synthetic time signal.
//

import Foundation
import Testing
@testable import FreqTrace

struct AnomalyCorpusHarnessTests {

    private let config = AnalysisConfig.default

    /// Sanity: the harness distinguishes a flagged tone from silence when
    /// driven by today's detector -- if these two don't separate, the
    /// harness itself is broken and every other result is meaningless.
    @Test func harnessSeparatesASteadyToneFromSilence() {
        let scorer = CorpusScorer(config: config)
        let tone = scorer.score(AnomalyCorpus.steadyTestTone, process: BaselineDetector.makeProcess(config: config))
        let silence = scorer.score(AnomalyCorpus.silence, process: BaselineDetector.makeProcess(config: config))

        #expect(tone.flaggedTargetEver)
        #expect(!silence.flaggedTargetEver)
    }

    /// The corpus signals actually contain the frequency they claim to --
    /// each non-silent target must become a findable peak at some point
    /// (else a "never flagged" result would be meaningless).
    @Test func everyNonSilentCaseProducesADetectablePeak() {
        let scorer = CorpusScorer(config: config)

        for testCase in AnomalyCorpus.cases where testCase.number != 10 {
            let score = scorer.score(testCase, process: BaselineDetector.makeProcess(config: config))
            #expect(score.firstDetectableHop != nil, "case \(testCase.number) (\(testCase.name)) never produced a detectable peak")
        }
    }

    /// Latency is measured from detectable-peak onset, so a flag can never
    /// precede detectability and latency is never negative.
    @Test func flagNeverPrecedesDetectability() {
        let scorer = CorpusScorer(config: config)

        for testCase in AnomalyCorpus.cases {
            let score = scorer.score(testCase, process: BaselineDetector.makeProcess(config: config))
            if let flag = score.firstFlagHop, let detect = score.firstDetectableHop {
                #expect(flag >= detect, "case \(testCase.number): flagged before detectable")
                #expect((score.flagLatencyMs ?? 0) >= 0)
            }
        }
    }
}

struct AnomalyBaselineScorecardTests {

    private let config = AnalysisConfig.default

    private func baseline() -> [CaseScore] {
        let scorer = CorpusScorer(config: config)
        return scorer.scoreAll(cases: AnomalyCorpus.cases) {
            BaselineDetector.makeProcess(config: config)
        }
    }

    /// Prints the baseline scorecard (visible in Xcode's console) -- the
    /// human-readable record of where today's detector stands, mirrored in
    /// docs/research/anomaly-corpus-baseline.md. The verdict assertions
    /// below encode the same result in executable form.
    @Test func recordsBaselineScorecard() {
        let scores = baseline()
        print("\n=== Anomaly detector BASELINE scorecard (ticket #34) ===")
        print(Scorecard.render(scores))
        print("=== end scorecard ===\n")
        #expect(scores.count == AnomalyCorpus.cases.count)
    }

    /// The anchoring bug, encoded: today's "flat-or-growing sustain" rule
    /// flags a steady test tone (case 5). This is the headline reason the
    /// criteria are being rethought (#21).
    @Test func baselineFalseFlagsTheSteadyTestTone() {
        let case5 = baseline().first { $0.number == 5 }
        #expect(case5?.flaggedTargetEver == true)
        #expect(case5?.verdict == false, "steady tone must-not-flag; baseline is expected to fail it")
    }

    /// The second false positive: a slowly hand-ramped tone also satisfies
    /// flat-or-growing, so today's detector flags it too (case 7).
    @Test func baselineFalseFlagsTheHandRampedTone() {
        let case7 = baseline().first { $0.number == 7 }
        #expect(case7?.flaggedTargetEver == true)
        #expect(case7?.verdict == false, "hand-ramped tone must-not-flag; baseline is expected to fail it")
    }

    /// Today's detector does catch the genuine ring cases -- the rethink
    /// must preserve this while fixing the false positives above.
    @Test func baselineCatchesTheFeedbackRingCases() {
        let scores = baseline()
        for number in [1, 2, 3] {
            let score = scores.first { $0.number == number }
            #expect(score?.flaggedTargetEver == true, "case \(number) (a feedback case) should be flagged even by today's detector")
        }
    }

    /// The building room mode (case 4) is flagged while blooming, and today's
    /// sustain rule drops it once it rings down (case 6's clear-once-settled).
    @Test func baselineFlagsTheBloomingRoomModeAndClearsOnDecay() {
        let mode = baseline().first { $0.number == 4 }
        #expect(mode?.flaggedTargetEver == true, "room mode should flag while building")
        #expect(mode?.flaggedTargetAtEnd == false, "room mode should have cleared once it rang down")
    }

    /// Silence never flags -- a floor sanity check that must hold for any
    /// detector, baseline or prototype.
    @Test func baselineNeverFlagsSilence() {
        let silence = baseline().first { $0.number == 10 }
        #expect(silence?.flaggedTargetEver == false)
        #expect(silence?.verdict == true)
    }
}
