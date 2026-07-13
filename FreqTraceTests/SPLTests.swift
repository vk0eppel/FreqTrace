//
//  SPLTests.swift
//  FreqTraceTests
//
//  Exercises FrequencyTracker.weightedLevelDb(fromMagnitudes:weighting:) --
//  the SPL meter's seam (ticket #6, CONTEXT.md "SPL Offset"). Self-
//  calibrated at init against a synthetic full-scale reference tone (see
//  FrequencyTracker's init), so these tests check the *relationship*
//  between signals (full-scale reads ~0dB, half-amplitude reads ~-6dB,
//  weighting changes the reading), not an assumed absolute FFT/window
//  scaling constant.
//

import Foundation
import Testing
@testable import FreqTrace

struct SPLTests {

    private let config = AnalysisConfig.default

    private func sineWave(frequency: Double, amplitude: Float, sampleRate: Double, count: Int) -> [Float] {
        (0..<count).map { i in
            amplitude * Float(sin(2 * Double.pi * frequency * Double(i) / sampleRate))
        }
    }

    @Test func fullScaleToneReadsApproximatelyZeroDB() throws {
        let tracker = FrequencyTracker(config: config)
        let samples = sineWave(frequency: 1000, amplitude: 1.0, sampleRate: config.sampleRate, count: config.windowSize)
        let magnitudes = try #require(tracker.spectrum(in: samples))

        let level = tracker.weightedLevelDb(fromMagnitudes: magnitudes, weighting: .z)

        #expect(abs(level) < 0.5)
    }

    @Test func halfAmplitudeReadsAboutSixDBLower() throws {
        let tracker = FrequencyTracker(config: config)
        let full = sineWave(frequency: 1000, amplitude: 1.0, sampleRate: config.sampleRate, count: config.windowSize)
        let half = sineWave(frequency: 1000, amplitude: 0.5, sampleRate: config.sampleRate, count: config.windowSize)

        let fullMagnitudes = try #require(tracker.spectrum(in: full))
        let halfMagnitudes = try #require(tracker.spectrum(in: half))

        let fullLevel = tracker.weightedLevelDb(fromMagnitudes: fullMagnitudes, weighting: .z)
        let halfLevel = tracker.weightedLevelDb(fromMagnitudes: halfMagnitudes, weighting: .z)

        // Power scales with amplitude^2, so halving amplitude is -6.02dB.
        #expect(abs((fullLevel - halfLevel) - 6.02) < 0.5)
    }

    @Test func isMonotonicWithLoudness() throws {
        let tracker = FrequencyTracker(config: config)
        let quiet = sineWave(frequency: 1000, amplitude: 0.1, sampleRate: config.sampleRate, count: config.windowSize)
        let loud = sineWave(frequency: 1000, amplitude: 0.9, sampleRate: config.sampleRate, count: config.windowSize)

        let quietLevel = tracker.weightedLevelDb(fromMagnitudes: try #require(tracker.spectrum(in: quiet)), weighting: .z)
        let loudLevel = tracker.weightedLevelDb(fromMagnitudes: try #require(tracker.spectrum(in: loud)), weighting: .z)

        #expect(loudLevel > quietLevel)
    }

    @Test func weightingChangesTheReadingForALowFrequencyTone() throws {
        // Ticket #6: "Changing the global Weighting control visibly
        // affects the SPL reading." A-weighting attenuates low frequencies
        // steeply (CONTEXT.md "Weighting"); Z-weighting is flat.
        let tracker = FrequencyTracker(config: config)
        let samples = sineWave(frequency: 50, amplitude: 1.0, sampleRate: config.sampleRate, count: config.windowSize)
        let magnitudes = try #require(tracker.spectrum(in: samples))

        let zLevel = tracker.weightedLevelDb(fromMagnitudes: magnitudes, weighting: .z)
        let aLevel = tracker.weightedLevelDb(fromMagnitudes: magnitudes, weighting: .a)

        #expect(aLevel < zLevel - 1.0)
    }

    @Test func aWeightingAt1kHzMatchesZWeightingApproximately() throws {
        // A/C-weighting are normalized to 0dB gain at 1kHz (CONTEXT.md /
        // Weighting.swift), so a 1kHz tone should read about the same
        // regardless of which weighting is selected.
        let tracker = FrequencyTracker(config: config)
        let samples = sineWave(frequency: 1000, amplitude: 1.0, sampleRate: config.sampleRate, count: config.windowSize)
        let magnitudes = try #require(tracker.spectrum(in: samples))

        let zLevel = tracker.weightedLevelDb(fromMagnitudes: magnitudes, weighting: .z)
        let aLevel = tracker.weightedLevelDb(fromMagnitudes: magnitudes, weighting: .a)

        #expect(abs(zLevel - aLevel) < 0.5)
    }
}
