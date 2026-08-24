//
//  AnomalyDetectionTests.swift
//  FreqTraceTests
//
//  Exercises the pure Anomaly Candidate detection stack (ticket #5, ADR
//  0001, CONTEXT.md "Anomaly Candidate"): PeakFinder (narrowband peaks by
//  spectral prominence), HarmonicRelation (integer-multiple frequency
//  matching, so a normal musical note's harmonic series isn't flagged),
//  and AnomalyDetector (a rolling per-bin sustain tracker promoting a
//  narrowband, harmonically-unrelated peak to a candidate only once it's
//  held for several consecutive hops). None of this touches real audio
//  hardware -- see FrequencyTracker.spectrum(in:) for the FFT seam these
//  synthetic magnitude arrays stand in for.
//

import Foundation
import Testing
@testable import FreqTrace

struct PeakFinderTests {

    private let config = AnalysisConfig.default

    private func spectrum(withPeaksAt bins: [(bin: Int, power: Float)], floorPower: Float = 1e-8) -> [Float] {
        var magnitudes = [Float](repeating: floorPower, count: config.windowSize / 2)
        for (bin, power) in bins {
            magnitudes[bin] = power
        }
        return magnitudes
    }

    @Test func findsALoneNarrowbandPeak() {
        let magnitudes = spectrum(withPeaksAt: [(500, 1.0)])

        let peaks = PeakFinder.findPeaks(magnitudes: magnitudes, config: config)

        #expect(peaks.contains { $0.bin == 500 })
    }

    @Test func flatSpectrumHasNoPeaks() {
        let magnitudes = [Float](repeating: 1e-6, count: config.windowSize / 2)

        let peaks = PeakFinder.findPeaks(magnitudes: magnitudes, config: config)

        #expect(peaks.isEmpty)
    }

    @Test func aBumpBelowTheProminenceThresholdIsNotAPeak() {
        // Only 3dB above the floor -- below PeakFinder.prominenceDb (6dB).
        let floor: Float = 1e-6
        let bump = floor * Float(pow(10, 3.0 / 10.0))
        let magnitudes = spectrum(withPeaksAt: [(500, bump)], floorPower: floor)

        let peaks = PeakFinder.findPeaks(magnitudes: magnitudes, config: config)

        #expect(peaks.isEmpty)
    }
}

struct HarmonicRelationTests {

    private func peak(bin: Int, hz: Double) -> SpectralPeak {
        SpectralPeak(bin: bin, frequencyHz: hz, magnitudeDb: 0)
    }

    @Test func aLoneFundamentalIsNotHarmonicallyRelated() {
        let fundamental = peak(bin: 1, hz: 100)

        #expect(!HarmonicRelation.isHarmonicallyRelated(fundamental, to: [fundamental]))
    }

    @Test func anExactSecondHarmonicIsHarmonicallyRelated() {
        let fundamental = peak(bin: 1, hz: 100)
        let secondHarmonic = peak(bin: 2, hz: 200)

        #expect(HarmonicRelation.isHarmonicallyRelated(secondHarmonic, to: [fundamental, secondHarmonic]))
        #expect(HarmonicRelation.isHarmonicallyRelated(fundamental, to: [fundamental, secondHarmonic]))
    }

    @Test func anUnrelatedPeakIsNotHarmonicallyRelated() {
        let a = peak(bin: 1, hz: 100)
        let b = peak(bin: 2, hz: 137) // not near any integer multiple of 100

        #expect(!HarmonicRelation.isHarmonicallyRelated(b, to: [a, b]))
    }

    // Regression (user report): a 1250Hz tone's higher harmonics were flagged
    // as phantom Anomaly Candidates because the old 2...8 cap didn't recognize
    // anything above the 8th harmonic. High harmonics must now count as
    // related in either direction.
    @Test func harmonicsAboveTheEighthAreStillRecognized() {
        let fundamental = peak(bin: 1, hz: 1250)
        let eleventh = peak(bin: 11, hz: 13750)
        let thirteenth = peak(bin: 13, hz: 16250)
        let all = [fundamental, eleventh, thirteenth]

        #expect(HarmonicRelation.isHarmonicallyRelated(eleventh, to: all))
        #expect(HarmonicRelation.isHarmonicallyRelated(thirteenth, to: all))
        // And the fundamental is related to them (a detected harmonic above it).
        #expect(HarmonicRelation.isHarmonicallyRelated(fundamental, to: all))
    }

    @Test func aHighNonIntegerMultipleIsStillUnrelated() {
        let fundamental = peak(bin: 1, hz: 1250)
        // 13100Hz = 10.48x, not near any integer multiple -> genuinely unrelated.
        let stray = peak(bin: 2, hz: 13100)

        #expect(!HarmonicRelation.isHarmonicallyRelated(stray, to: [fundamental, stray]))
    }

    // The Sabine isolation margin (#38): a STRONG harmonic (within the margin)
    // excludes; a WEAK one (beyond it) does not -- the correction that lets a
    // real howl through when it merely coincides with a weak program harmonic.

    private func peak(bin: Int, hz: Double, db: Float) -> SpectralPeak {
        SpectralPeak(bin: bin, frequencyHz: hz, magnitudeDb: db)
    }

    @Test func aStrongHarmonicExcludesUnderTheMargin() {
        let fundamental = peak(bin: 1, hz: 1000, db: -10)
        let strongHarmonic = peak(bin: 2, hz: 2000, db: -16) // 6dB down, within a 10dB margin
        #expect(HarmonicRelation.isStronglyRelated(fundamental, to: [fundamental, strongHarmonic], withinDb: 10))
    }

    @Test func aWeakHarmonicDoesNotExcludeUnderTheMargin() {
        let fundamental = peak(bin: 1, hz: 1000, db: -10)
        let weakHarmonic = peak(bin: 2, hz: 2000, db: -30) // 20dB down, beyond a 10dB margin
        #expect(!HarmonicRelation.isStronglyRelated(fundamental, to: [fundamental, weakHarmonic], withinDb: 10))
        // Binary would still have excluded it -- the whole point of the margin.
        #expect(HarmonicRelation.isHarmonicallyRelated(fundamental, to: [fundamental, weakHarmonic]))
    }
}

struct AnomalyDetectorTests {

    private let config = AnalysisConfig.default
    private let fullScalePower: Float = 1.0   // so power == dBFS directly
    private var binHz: Double { config.sampleRate / Double(config.windowSize) }
    private var riseWindow: Int { AnomalyDetector.riseWindowFrames(for: config) }
    private var confirm: Int { AnomalyDetector.confirmFrames(for: config) }

    /// A spectrum with each named bin set to a given dBFS level (power =
    /// 10^(dB/10)), everything else at a -80 dBFS floor.
    private func spectrum(_ tones: [(bin: Int, db: Float)]) -> [Float] {
        var magnitudes = [Float](repeating: 1e-8, count: config.windowSize / 2)
        for (bin, db) in tones { magnitudes[bin] = Float(pow(10.0, Double(db) / 10.0)) }
        return magnitudes
    }

    private func flagged(_ candidates: [AnomalyCandidate], bin: Int) -> Bool {
        candidates.contains { abs($0.frequencyHz - Double(bin) * binHz) < binHz }
    }

    private func run(_ detector: inout AnomalyDetector, _ spectrum: [Float]) -> [AnomalyCandidate] {
        detector.process(magnitudes: spectrum, fullScalePower: fullScalePower, config: config)
    }

    // MARK: The four-state life-cycle

    /// A climbing tone (a ring-up) is flagged.
    @Test func aRisingToneIsFlagged() {
        var detector = AnomalyDetector()
        var last: [AnomalyCandidate] = []
        for i in 0..<(riseWindow + confirm + 2) {          // climbs 1 dB/frame from -40 dBFS
            last = run(&detector, spectrum([(500, -40 + Float(i))]))
        }
        #expect(flagged(last, bin: 500))
    }

    /// A steady, flat tone is NOT flagged -- the anchoring bug (a steady
    /// signal-generator tone read as an anomaly) is fixed structurally: it
    /// never rose, and it's below the hotness trigger.
    @Test func aSteadyToneIsNotFlagged() {
        var detector = AnomalyDetector()
        var last: [AnomalyCandidate] = []
        for _ in 0..<(riseWindow + 5) { last = run(&detector, spectrum([(500, -20)])) }
        #expect(!flagged(last, bin: 500))
    }

    /// A screaming-hot tone flags on loudness alone, with no rising edge
    /// (the fast-howl / already-saturated path).
    @Test func aHotToneIsFlaggedWithoutRising() {
        var detector = AnomalyDetector()
        var last: [AnomalyCandidate] = []
        for _ in 0..<(confirm + 2) { last = run(&detector, spectrum([(500, -3)])) }  // -3 >= hotness -6
        #expect(flagged(last, bin: 500))
    }

    /// A rising tone that stays below the detectability floor is ignored.
    @Test func aRisingToneBelowTheFloorIsNotFlagged() {
        var detector = AnomalyDetector()
        var last: [AnomalyCandidate] = []
        for i in 0..<(riseWindow + 5) {                    // -70 .. ~-64 dBFS, always below -45
            last = run(&detector, spectrum([(500, -70 + Float(i) * 0.3)]))
        }
        #expect(!flagged(last, bin: 500))
    }

    /// A flagged tone is released once it falls away from its held peak.
    @Test func aFlaggedToneIsReleasedWhenItFallsAway() {
        var detector = AnomalyDetector()
        var last: [AnomalyCandidate] = []
        for i in 0..<(riseWindow + confirm + 2) { last = run(&detector, spectrum([(500, -40 + Float(i))])) }
        #expect(flagged(last, bin: 500), "should be flagged after ringing up")
        for _ in 0..<(AnomalyDetector.releaseFrameCount + 2) { last = run(&detector, spectrum([(500, -35)])) }  // > fall-away below the held peak
        #expect(!flagged(last, bin: 500), "should release once it drops away")
    }

    // MARK: Harmonic isolation (Sabine margin)

    /// A rising musical note (fundamental + a strong harmonic) is not flagged.
    @Test func aRisingToneWithAStrongHarmonicIsNotFlagged() {
        var detector = AnomalyDetector()
        var last: [AnomalyCandidate] = []
        for i in 0..<(riseWindow + confirm + 2) {
            let db = -30 + Float(i) * 0.8
            last = run(&detector, spectrum([(100, db), (200, db - 6)]))  // 2nd harmonic 6 dB down (within 10 dB margin)
        }
        #expect(!flagged(last, bin: 100))
    }

    /// The Sabine benefit (enabled by the -45 floor): a rising tone whose only
    /// harmonic is WEAK (beyond the margin) IS flagged -- the binary gate
    /// would have wrongly suppressed it.
    @Test func aRisingToneWithOnlyAWeakHarmonicIsFlagged() {
        var detector = AnomalyDetector()
        var last: [AnomalyCandidate] = []
        for i in 0..<(riseWindow + confirm + 2) {
            let db = -30 + Float(i) * 0.8                                 // fundamental stays below hotness
            last = run(&detector, spectrum([(100, db), (200, db - 15)]))  // harmonic 15 dB down (> 10 dB margin), above floor
        }
        #expect(flagged(last, bin: 100))
    }

    // MARK: Floor / infrastructure

    @Test func zeroCandidatesForSilence() {
        var detector = AnomalyDetector()
        #expect(run(&detector, spectrum([])).isEmpty)
    }

    /// Two loud tones one bin apart are tracked separately, not collapsed
    /// (regression: the `matchedKeys` collision guard).
    @Test func twoPeaksOneBinApartAreTrackedSeparately() {
        var detector = AnomalyDetector()
        _ = run(&detector, spectrum([(500, -3)]))          // establish a track at 500
        var last: [AnomalyCandidate] = []
        for _ in 0..<(confirm + 3) { last = run(&detector, spectrum([(499, -3), (501, -3)])) }
        #expect(last.count == 2)
    }

    /// A single missed frame within the release tolerance doesn't reset a
    /// track's progress toward latching (regression).
    @Test func aBriefMissDoesNotResetProgressTowardFlagging() {
        var detector = AnomalyDetector()
        _ = run(&detector, spectrum([(500, -3)]))          // hot, streak 1
        _ = run(&detector, spectrum([]))                   // one missed frame (within release tolerance)
        let last = run(&detector, spectrum([(500, -3)]))   // reappears -> streak reaches confirm -> flags
        #expect(flagged(last, bin: 500))
    }
}
