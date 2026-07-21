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
}

struct AnomalyDetectorTests {

    private let config = AnalysisConfig.default
    private let binHz: Double

    init() {
        binHz = config.sampleRate / Double(config.windowSize)
    }

    private func spectrum(withPeaksAt bins: [(bin: Int, power: Float)]) -> [Float] {
        var magnitudes = [Float](repeating: 1e-8, count: config.windowSize / 2)
        for (bin, power) in bins {
            magnitudes[bin] = power
        }
        return magnitudes
    }

    @Test func aSustainedNarrowbandToneIsFlaggedAfterEnoughFrames() {
        var detector = AnomalyDetector()
        let toneBin = 500
        var lastCandidates: [AnomalyCandidate] = []

        for _ in 0..<(AnomalyDetector.sustainFrameCount(for: .default) + 2) {
            lastCandidates = detector.process(magnitudes: spectrum(withPeaksAt: [(toneBin, 1.0)]), config: config)
        }

        #expect(lastCandidates.contains { abs($0.frequencyHz - Double(toneBin) * binHz) < 1 })
    }

    @Test func aBriefTransientIsNotFlagged() {
        var detector = AnomalyDetector()
        let toneBin = 500

        // Only one frame of energy -- well short of sustainFrameCount.
        let candidates = detector.process(magnitudes: spectrum(withPeaksAt: [(toneBin, 1.0)]), config: config)

        #expect(!candidates.contains { $0.frequencyHz > 0 && abs($0.frequencyHz - Double(toneBin) * binHz) < 1 })
    }

    @Test func aNormalHarmonicSeriesIsNeverFlagged() {
        var detector = AnomalyDetector()
        // A fundamental plus 2nd/3rd harmonics, all sustained -- a musical
        // note, not feedback (ADR 0001's negative case).
        let bins: [(Int, Float)] = [(100, 1.0), (200, 0.6), (300, 0.4)]
        var lastCandidates: [AnomalyCandidate] = []

        for _ in 0..<(AnomalyDetector.sustainFrameCount(for: .default) + 2) {
            lastCandidates = detector.process(magnitudes: spectrum(withPeaksAt: bins), config: config)
        }

        #expect(lastCandidates.isEmpty)
    }

    @Test func twoSimultaneousSustainedTonesBothAppearRankedBySeverity() {
        var detector = AnomalyDetector()
        let quietBin = 300
        let loudBin = 700
        var lastCandidates: [AnomalyCandidate] = []

        for _ in 0..<(AnomalyDetector.sustainFrameCount(for: .default) + 2) {
            lastCandidates = detector.process(
                magnitudes: spectrum(withPeaksAt: [(quietBin, 0.1), (loudBin, 1.0)]), config: config
            )
        }

        #expect(lastCandidates.count == 2)
        #expect(lastCandidates[0].severityDb > lastCandidates[1].severityDb)
        #expect(abs(lastCandidates[0].frequencyHz - Double(loudBin) * binHz) < 1)
    }

    @Test func zeroCandidatesWhenNothingIsSustained() {
        var detector = AnomalyDetector()

        let candidates = detector.process(magnitudes: [Float](repeating: 1e-8, count: config.windowSize / 2), config: config)

        #expect(candidates.isEmpty)
    }

    // Regression tests for two bugs found by code review on #5.

    @Test func aSinglePeakWithinReleaseToleranceDoesNotResetSustainProgress() {
        var detector = AnomalyDetector()
        let toneBin = 500

        // Build up sustain progress right to the edge of promotion.
        for _ in 0..<(AnomalyDetector.sustainFrameCount(for: .default) - 1) {
            _ = detector.process(magnitudes: spectrum(withPeaksAt: [(toneBin, 1.0)]), config: config)
        }
        // One missed frame (e.g. the peak momentarily fell at a bin
        // boundary) -- within releaseFrameCount's tolerance.
        _ = detector.process(magnitudes: spectrum(withPeaksAt: []), config: config)
        // The very next frame the tone reappears -- sustain progress
        // should have been preserved, not reset to 0.
        let candidates = detector.process(magnitudes: spectrum(withPeaksAt: [(toneBin, 1.0)]), config: config)

        #expect(candidates.contains { abs($0.frequencyHz - Double(toneBin) * binHz) < 1 })
    }

    @Test func twoDistinctSimultaneousPeaksOneBinApartAreTrackedSeparatelyNotCollapsed() {
        var detector = AnomalyDetector()
        // Establish a single track at bin 500 first.
        _ = detector.process(magnitudes: spectrum(withPeaksAt: [(500, 1.0)]), config: config)

        // Now two distinct peaks appear, both within +-1 bin of the
        // existing track -- must not silently collapse into one.
        var lastCandidates: [AnomalyCandidate] = []
        for _ in 0..<(AnomalyDetector.sustainFrameCount(for: .default) + 2) {
            lastCandidates = detector.process(magnitudes: spectrum(withPeaksAt: [(499, 1.0), (501, 1.0)]), config: config)
        }

        #expect(lastCandidates.count == 2)
    }
}
