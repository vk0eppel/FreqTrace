//
//  FrequencyTrackerTests.swift
//  FreqTraceTests
//
//  Exercises the pure analysis engine seam (FrequencyTracker) with
//  synthetic sine waves at known frequencies, independent of AVAudioEngine
//  -- see MicrophoneCaptureEngine.swift for why the hardware capture glue
//  itself is not unit-tested here.
//

import Foundation
import Testing
@testable import FreqTrace

struct FrequencyTrackerTests {

    private let config = AnalysisConfig.default // 48kHz / 4096-window / 2048-hop
    private var binResolutionHz: Double { config.binResolutionHz } // ~11.72 Hz

    // Reuses FrequencyTracker.sineWave(...) via @testable import rather
    // than hand-rolling a duplicate generator.
    private func sineWave(frequency: Double, amplitude: Float = 1.0, sampleRate: Double, count: Int) -> [Float] {
        FrequencyTracker.sineWave(frequency: frequency, amplitude: amplitude, sampleRate: sampleRate, count: count)
    }

    @Test func tracks1kHzToneWithinBinResolution() throws {
        let tracker = FrequencyTracker(config: config)
        let samples = sineWave(frequency: 1000, sampleRate: config.sampleRate, count: config.windowSize)

        let frequency = try #require(tracker.trackedFrequency(in: samples, weighting: .z))

        #expect(abs(frequency - 1000) <= binResolutionHz)
    }

    @Test func tracks440HzToneWithinBinResolution() throws {
        let tracker = FrequencyTracker(config: config)
        let samples = sineWave(frequency: 440, sampleRate: config.sampleRate, count: config.windowSize)

        let frequency = try #require(tracker.trackedFrequency(in: samples, weighting: .z))

        #expect(abs(frequency - 440) <= binResolutionHz)
    }

    @Test func usesOnlyTheMostRecentWindowWhenGivenMoreSamplesThanNeeded() throws {
        let tracker = FrequencyTracker(config: config)
        // Prepend a full window of a different, louder tone -- only the
        // trailing `windowSize` samples (the 1kHz tone) should be analyzed.
        let stale = sineWave(frequency: 200, amplitude: 5.0, sampleRate: config.sampleRate, count: config.windowSize)
        let fresh = sineWave(frequency: 1000, sampleRate: config.sampleRate, count: config.windowSize)

        let frequency = try #require(tracker.trackedFrequency(in: stale + fresh, weighting: .z))

        #expect(abs(frequency - 1000) <= binResolutionHz)
    }

    @Test func returnsNilWhenFewerThanWindowSizeSamplesAreProvided() {
        let tracker = FrequencyTracker(config: config)
        let tooShort = [Float](repeating: 0, count: config.windowSize - 1)

        #expect(tracker.trackedFrequency(in: tooShort, weighting: .z) == nil)
    }

    // The core Weighting requirement (CLAUDE.md / CONTEXT.md "Weighting"):
    // switching the control must visibly change the reading for program
    // material where A/C-weighting would disagree. A loud low tone (50 Hz)
    // plus a much quieter mid tone (1 kHz) is exactly that case -- A-weighting
    // suppresses low frequencies steeply enough that the quieter mid tone
    // wins, while C/Z barely touch 50 Hz so the loud low tone still wins.
    @Test func weightingChangesTheWinnerForADisagreeingTwoToneSignal() throws {
        let tracker = FrequencyTracker(config: config)
        let low = sineWave(frequency: 50, amplitude: 1.0, sampleRate: config.sampleRate, count: config.windowSize)
        let mid = sineWave(frequency: 1000, amplitude: 0.1, sampleRate: config.sampleRate, count: config.windowSize)
        let mixed = zip(low, mid).map(+)

        let zResult = try #require(tracker.trackedFrequency(in: mixed, weighting: .z))
        let cResult = try #require(tracker.trackedFrequency(in: mixed, weighting: .c))
        let aResult = try #require(tracker.trackedFrequency(in: mixed, weighting: .a))

        #expect(abs(zResult - 50) <= binResolutionHz)
        #expect(abs(cResult - 50) <= binResolutionHz)
        #expect(abs(aResult - 1000) <= binResolutionHz)
    }

    // spectrum() is the seam the waterfall (ticket #8) consumes: the raw,
    // unweighted power magnitude per FFT bin, reusing the same FFT the
    // Tracked Frequency computation runs (see AudioAnalysisPipeline, which
    // calls this once per hop rather than running the FFT twice).

    @Test func spectrumReturnsNilWhenFewerThanWindowSizeSamplesAreProvided() {
        let tracker = FrequencyTracker(config: config)
        let tooShort = [Float](repeating: 0, count: config.windowSize - 1)

        #expect(tracker.spectrum(in: tooShort) == nil)
    }

    @Test func spectrumHasHalfTheWindowSizeInBins() throws {
        let tracker = FrequencyTracker(config: config)
        let samples = sineWave(frequency: 1000, sampleRate: config.sampleRate, count: config.windowSize)

        let magnitudes = try #require(tracker.spectrum(in: samples))

        #expect(magnitudes.count == config.windowSize / 2)
    }

    @Test func spectrumPeaksAtTheTonesBin() throws {
        let tracker = FrequencyTracker(config: config)
        let samples = sineWave(frequency: 1000, sampleRate: config.sampleRate, count: config.windowSize)

        let magnitudes = try #require(tracker.spectrum(in: samples))
        let peakBin = magnitudes.indices.max(by: { magnitudes[$0] < magnitudes[$1] })!
        let peakFrequency = Double(peakBin) * binResolutionHz

        #expect(abs(peakFrequency - 1000) <= binResolutionHz)
    }

    @Test func spectrumIsUnweighted() throws {
        // Unlike trackedFrequency, spectrum() must not apply Weighting --
        // the waterfall shows true measured magnitude, not a
        // perceptually-biased view (Weighting only applies to Tracked
        // Frequency / SPL per CONTEXT.md "Weighting").
        let tracker = FrequencyTracker(config: config)
        let low = sineWave(frequency: 50, amplitude: 1.0, sampleRate: config.sampleRate, count: config.windowSize)
        let mid = sineWave(frequency: 1000, amplitude: 0.1, sampleRate: config.sampleRate, count: config.windowSize)
        let mixed = zip(low, mid).map(+)

        let magnitudes = try #require(tracker.spectrum(in: mixed))
        let peakBin = magnitudes.indices.max(by: { magnitudes[$0] < magnitudes[$1] })!
        let peakFrequency = Double(peakBin) * binResolutionHz

        // A-weighting would have made the 1kHz tone win (see
        // weightingChangesTheWinnerForADisagreeingTwoToneSignal above); the
        // raw spectrum must still show the physically louder 50Hz tone.
        #expect(abs(peakFrequency - 50) <= binResolutionHz)
    }

    @Test func louderToneProducesLargerMagnitudeAtItsBin() throws {
        let tracker = FrequencyTracker(config: config)
        let quiet = sineWave(frequency: 1000, amplitude: 0.2, sampleRate: config.sampleRate, count: config.windowSize)
        let loud = sineWave(frequency: 1000, amplitude: 0.8, sampleRate: config.sampleRate, count: config.windowSize)

        let quietMagnitudes = try #require(tracker.spectrum(in: quiet))
        let loudMagnitudes = try #require(tracker.spectrum(in: loud))
        let bin = Int((1000 / binResolutionHz).rounded())

        #expect(loudMagnitudes[bin] > quietMagnitudes[bin])
    }
}

struct WeightingTests {

    @Test func aAndCWeightingAreUnityAt1kHz() {
        #expect(abs(Weighting.a.gainDb(at: 1000)) < 0.1)
        #expect(abs(Weighting.c.gainDb(at: 1000)) < 0.1)
    }

    @Test func zWeightingIsFlatAtEveryFrequency() {
        #expect(Weighting.z.gainDb(at: 50) == 0)
        #expect(Weighting.z.gainDb(at: 10_000) == 0)
    }

    @Test func aWeightingAttenuatesLowFrequenciesMoreSteeplyThanC() {
        #expect(Weighting.a.gainDb(at: 50) < Weighting.c.gainDb(at: 50))
    }

    @Test func defaultWeightingIsA() {
        #expect(Weighting.default == .a)
    }
}

struct AudioRingBufferTests {

    @Test func writeThenReadRoundTrips() {
        let buffer = AudioRingBuffer(capacity: 16)
        let samples: [Float] = [1, 2, 3, 4, 5]

        samples.withUnsafeBufferPointer { pointer in
            buffer.write(pointer.baseAddress!, count: pointer.count)
        }
        var out = [Float](repeating: 0, count: 5)
        let read = buffer.read(into: &out, count: 5)

        #expect(read == 5)
        #expect(out == samples)
    }

    @Test func readReturnsZeroWhenBufferIsEmpty() {
        let buffer = AudioRingBuffer(capacity: 16)
        var out = [Float](repeating: 0, count: 5)

        #expect(buffer.read(into: &out, count: 5) == 0)
    }

    @Test func writeBeyondCapacityDropsOldestSamplesRatherThanCrashing() {
        let buffer = AudioRingBuffer(capacity: 4)
        let samples: [Float] = [1, 2, 3, 4, 5, 6]

        samples.withUnsafeBufferPointer { pointer in
            buffer.write(pointer.baseAddress!, count: pointer.count)
        }
        var out = [Float](repeating: 0, count: 4)
        let read = buffer.read(into: &out, count: 4)

        // Newest samples (3,4,5,6) should survive; oldest (1,2) are dropped.
        #expect(read == 4)
        #expect(out == [3, 4, 5, 6])
    }

    @Test func overflowAcrossMultipleWritesResyncsOnRead() {
        // Regression test: an earlier version had write() and read() racing
        // to mutate readIndex independently, which could un-drop data that
        // a later write had already overwritten. This exercises the
        // multi-write overflow path (no read() call between writes) that
        // read() must now resync past on its own.
        let buffer = AudioRingBuffer(capacity: 4)

        let first: [Float] = [1, 2]
        first.withUnsafeBufferPointer { buffer.write($0.baseAddress!, count: $0.count) }

        let second: [Float] = [3, 4, 5, 6, 7]
        second.withUnsafeBufferPointer { buffer.write($0.baseAddress!, count: $0.count) }

        var out = [Float](repeating: 0, count: 4)
        let read = buffer.read(into: &out, count: 4)

        // Total written: 1,2,3,4,5,6,7 (7 samples into a 4-capacity buffer).
        // Only the newest 4 (4,5,6,7) should be readable; nothing stale or
        // torn from the already-overwritten 1,2,3.
        #expect(read == 4)
        #expect(out == [4, 5, 6, 7])
    }
}
