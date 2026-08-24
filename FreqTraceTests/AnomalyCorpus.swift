//
//  AnomalyCorpus.swift
//  FreqTraceTests
//
//  The SYNTHETIC tier of the anomaly-candidate validation corpus
//  (docs/research/anomaly-validation-corpus.md, ticket #20 / map #18). Each
//  case is an envelope-over-time shape (steady / ring-up / saturate /
//  bloom-decay / hand-ramp / silence) for a single narrowband tone. The
//  scorer turns each envelope into a per-hop magnitude spectrum and runs it
//  through the detector offline, no mic (see AnomalyScoring.swift).
//
//  Spectra are synthesized DIRECTLY (a clean floor with the target bin
//  raised to the envelope's windowed power), the same seam the existing
//  AnomalyDetectionTests use -- NOT by FFT-ing a synthetic time signal. A
//  pure synthetic tone through the real FFT has a floating-point-roundoff
//  far-field that PeakFinder reads as hundreds of spurious per-bin peaks,
//  which the harmonic gate then relates to each other so nothing is ever
//  flagged -- an artifact of synthetic roundoff (real mic audio has a
//  smooth, correlated noise floor that doesn't do this), unrepresentative
//  of the detector's real behavior and contradicting the known steady-tone
//  bug. Real-FFT leakage/noise realism is the real-capture tier's job
//  (#35/#37); this tier tests the detector's TEMPORAL logic on clean tones.
//
//  Convention (CLAUDE.md): pure value types are nonisolated.
//

import Foundation
@testable import FreqTrace

/// What a trustworthy detector is expected to do with a case.
nonisolated enum CorpusExpectation: Sendable {
    /// The target frequency must be flagged. `withinMs` is the latency
    /// target measured from the moment the target first becomes a findable
    /// narrowband peak (the corpus spec's "within ~500 ms of becoming a
    /// sustained narrowband peak") -- `nil` for the saturated/fast-howl
    /// cases, which may show no rising edge and are caught via the memory
    /// path, so only "flagged at all" is required.
    case mustFlag(withinMs: Double?)
    /// The target frequency must never be flagged.
    case mustNotFlag
}

/// One tone in a case's signal: a frequency plus its amplitude envelope
/// (0...1, 1.0 == full scale) over time. A single-tone case has one; a
/// musical note or a feedback-with-harmonics case has several.
nonisolated struct ToneComponent: Sendable {
    let hz: Double
    let envelope: @Sendable (Double) -> Float
}

/// One synthetic corpus case: one or more tones (`components`), scored on the
/// behaviour at `targetHz` -- the frequency the expectation is about.
nonisolated struct CorpusCase: Sendable {
    /// Corpus case number from the spec (1-10) or an extension number
    /// (11+), for cross-referencing.
    let number: Int
    let name: String
    let targetHz: Double
    let durationSec: Double
    let expectation: CorpusExpectation
    let components: [ToneComponent]

    /// Corpus case 6 lives on the same signal as case 4 (a room mode blooms
    /// then settles): case 4 asks it be flagged while building, case 6 asks
    /// the flag clear once it settles. When set, the scorer additionally
    /// checks the target is NOT flagged in the final hops.
    let mustClearByEnd: Bool

    /// Single-tone case: the target tone follows `envelope`.
    init(
        number: Int,
        name: String,
        targetHz: Double,
        durationSec: Double,
        expectation: CorpusExpectation,
        mustClearByEnd: Bool = false,
        envelope: @escaping @Sendable (Double) -> Float
    ) {
        self.init(
            number: number, name: name, targetHz: targetHz, durationSec: durationSec,
            expectation: expectation, mustClearByEnd: mustClearByEnd,
            components: [ToneComponent(hz: targetHz, envelope: envelope)]
        )
    }

    /// Multi-tone case (harmonic series, feedback + spurious harmonics, …).
    init(
        number: Int,
        name: String,
        targetHz: Double,
        durationSec: Double,
        expectation: CorpusExpectation,
        mustClearByEnd: Bool = false,
        components: [ToneComponent]
    ) {
        self.number = number
        self.name = name
        self.targetHz = targetHz
        self.durationSec = durationSec
        self.expectation = expectation
        self.mustClearByEnd = mustClearByEnd
        self.components = components
    }
}

nonisolated enum AnomalyCorpus {

    // MARK: Level references (sine amplitude, 1.0 == full scale)

    /// A sane working test-tone / mode level -- well above the floor,
    /// nowhere near clipping.
    static let moderateAmplitude: Float = 0.2
    /// Runaway / clipping-hot: what a saturated feedback howl pins at.
    static let hotAmplitude: Float = 0.9

    // MARK: The cases

    /// The synthetic tier: cases 1-7 and 10 (cases 8, 9 are real program
    /// material -- the #35 capture tier).
    static var cases: [CorpusCase] {
        [
            nearThresholdRingUp,
            ringUpThenSaturate,
            fastHowl,
            buildingSettlingRoomMode,
            steadyTestTone,
            handRampedTone,
            silence,
        ]
    }

    /// Case 1: a slow near-threshold "singing" ring -- amplitude climbs
    /// exponentially. Must flag within ~500 ms of becoming a peak.
    static let nearThresholdRingUp = CorpusCase(
        number: 1,
        name: "Near-threshold ring-up",
        targetHz: 1000,
        durationSec: 2.5,
        expectation: .mustFlag(withinMs: 500)
    ) { t in
        expEnvelope(t: t, start: 0.004, tau: 0.35, ceiling: 0.3)
    }

    /// Case 2: ring-up that clips flat at the ceiling and holds -- the
    /// memory case. No latency requirement, but must stay flagged through
    /// the flat phase.
    static let ringUpThenSaturate = CorpusCase(
        number: 2,
        name: "Ring-up \u{2192} saturate",
        targetHz: 1000,
        durationSec: 2.5,
        expectation: .mustFlag(withinMs: nil)
    ) { t in
        expEnvelope(t: t, start: 0.01, tau: 0.18, ceiling: hotAmplitude)
    }

    /// Case 3: a howl that erupts to full blast within ~one hop -- arrives
    /// already flat, no visible rising edge. Must still flag (loudness path).
    static let fastHowl = CorpusCase(
        number: 3,
        name: "Fast howl (arrives flat)",
        targetHz: 1000,
        durationSec: 2.0,
        expectation: .mustFlag(withinMs: nil)
    ) { t in
        t < 0.02 ? 0 : hotAmplitude
    }

    /// Cases 4 & 6: a room mode that blooms (must flag while building) then
    /// rings down (must clear once settled). One signal, two phases.
    static let buildingSettlingRoomMode = CorpusCase(
        number: 4,
        name: "Room mode (bloom + settle)",
        targetHz: 80,
        durationSec: 3.0,
        expectation: .mustFlag(withinMs: 500),
        mustClearByEnd: true
    ) { t in
        bloomDecayEnvelope(t: t, peak: 0.35, riseSec: 0.5, holdSec: 0.4, decaySec: 1.2)
    }

    /// Case 5: a steady sine at a sane level, flat from switch-on -- the
    /// anchoring false positive. Must never flag.
    static let steadyTestTone = CorpusCase(
        number: 5,
        name: "Steady test tone",
        targetHz: 1000,
        durationSec: 2.0,
        expectation: .mustNotFlag
    ) { _ in moderateAmplitude }

    /// Case 7: a tone whose level is ramped up slowly by hand (linear, over
    /// ~2 s) -- rises like feedback but is benign. Must not flag.
    static let handRampedTone = CorpusCase(
        number: 7,
        name: "Hand-ramped test tone",
        targetHz: 1000,
        durationSec: 2.5,
        expectation: .mustNotFlag
    ) { t in
        linearRamp(t: t, start: 0.002, peak: moderateAmplitude, rampSec: 2.0)
    }

    /// Case 10: digital silence. Must not flag.
    static let silence = CorpusCase(
        number: 10,
        name: "Silence / digital zero",
        targetHz: 1000,
        durationSec: 1.5,
        expectation: .mustNotFlag
    ) { _ in 0 }

    // MARK: Step-1 extension cases (#37, room-free) -- pin the intents the
    // synthetic core (cases 1-7,10) left loose. Kept OUT of `cases` so the
    // core corpus's 7/7 (baseline #34, prototype #36) is unchanged; scored by
    // their own tests.

    /// Case 8 (the spec's sustained-music slot, here a synthetic stand-in): a
    /// musical note that *crescendos* -- a rising fundamental with a full
    /// harmonic series. Absent the harmonic gate its rising fundamental would
    /// trip the rise trigger; the gate must keep it out. Must not flag.
    static let musicNoteCrescendo: CorpusCase = {
        let fundamental: @Sendable (Double) -> Float = { t in linearRamp(t: t, start: 0.02, peak: 0.35, rampSec: 0.8) }
        func partial(_ scale: Float) -> @Sendable (Double) -> Float { { t in scale * fundamental(t) } }
        return CorpusCase(
            number: 8,
            name: "Music note (crescendo + harmonics)",
            targetHz: 500,
            durationSec: 2.0,
            expectation: .mustNotFlag,
            components: [
                ToneComponent(hz: 500, envelope: fundamental),
                ToneComponent(hz: 1000, envelope: partial(0.5)),
                ToneComponent(hz: 1500, envelope: partial(0.33)),
                ToneComponent(hz: 2000, envelope: partial(0.2)),
            ]
        )
    }()

    /// Case 12: a deliberately loud but steady test tone (~-8 dBFS, flat) --
    /// a tech running a hot check tone. Must not flag: it never rises, and it
    /// must sit *below* the hotness trigger. Pins the hotness lower bound.
    static let loudSteadyTone = CorpusCase(
        number: 12,
        name: "Loud steady test tone (-8 dBFS)",
        targetHz: 1500,
        durationSec: 2.0,
        expectation: .mustNotFlag
    ) { _ in 0.4 }   // 0.4^2 ≈ -8 dBFS

    /// Case 13: saturated feedback that briefly ducks near the end (a ~7 dB
    /// dip, e.g. someone momentarily pulls the fader) then would hold -- still
    /// feedback, must stay flagged through the dip. Pins the fall-away lower
    /// bound: the margin must exceed a transient dip.
    static let feedbackWithDip = CorpusCase(
        number: 13,
        name: "Saturated feedback with a transient dip",
        targetHz: 1000,
        durationSec: 2.0,
        expectation: .mustFlag(withinMs: nil)
    ) { t in
        let rung = expEnvelope(t: t, start: 0.1, tau: 0.12, ceiling: 0.9)   // ~-0.9 dBFS held
        return t > 1.4 ? 0.4 : rung                                          // dip to ~-8 dBFS (~7 dB) at the end
    }

    // MARK: Envelope builders

    /// Exponential ring-up `start * e^(t/tau)`, clamped at `ceiling`.
    static func expEnvelope(t: Double, start: Double, tau: Double, ceiling: Float) -> Float {
        Float(min(Double(ceiling), start * exp(t / tau)))
    }

    /// Linear rise from `start` to `peak` over `rampSec`, then hold at `peak`.
    static func linearRamp(t: Double, start: Float, peak: Float, rampSec: Double) -> Float {
        guard t < rampSec else { return peak }
        let frac = Float(t / rampSec)
        return start + (peak - start) * frac
    }

    /// Bloom then ring-down: linear rise to `peak` over `riseSec`, hold for
    /// `holdSec`, then exponential decay over `decaySec` back toward zero.
    static func bloomDecayEnvelope(t: Double, peak: Float, riseSec: Double, holdSec: Double, decaySec: Double) -> Float {
        if t < riseSec {
            return peak * Float(t / riseSec)
        }
        if t < riseSec + holdSec {
            return peak
        }
        let decayT = t - riseSec - holdSec
        // ~5 time-constants across decaySec -> effectively silent by the end.
        return peak * Float(exp(-5 * decayT / decaySec))
    }
}
