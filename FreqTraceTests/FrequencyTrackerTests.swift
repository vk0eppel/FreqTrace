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

    private let config = AnalysisConfig.default // 48kHz / 8192-window / 4096-hop
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

    // Parabolic sub-bin interpolation (user report: "the tracked frequency
    // value change with fft size"). A tone sitting *between* two bin centers
    // must resolve far tighter than the raw bin width -- a pure argmax could
    // only ever report one of the two flanking centers (~+/-6Hz off here at
    // the 8192/48kHz default), whereas interpolation locates the true peak
    // between them.
    @Test func interpolatesAToneBetweenBinCentersFarTighterThanBinWidth() throws {
        let tracker = FrequencyTracker(config: config)
        // Halfway between bins: bin index (1000/binHz rounded) + 0.5.
        let midBinHz = (Double(Int(1000 / binResolutionHz)) + 0.5) * binResolutionHz
        let samples = sineWave(frequency: midBinHz, sampleRate: config.sampleRate, count: config.windowSize)

        let frequency = try #require(tracker.trackedFrequency(in: samples, weighting: .z))

        // Well inside a quarter-bin -- unreachable without interpolation.
        #expect(abs(frequency - midBinHz) <= binResolutionHz / 4)
    }

    // The whole point of the change: the same physical tone reads ~the same
    // value regardless of FFT size, instead of snapping to each size's own bin
    // grid (46.9Hz bins at 1024 down to 2.93Hz at 16384).
    @Test func reportsAStableFrequencyAcrossFFTSizes() throws {
        let trueHz = 997.0 // deliberately off every size's bin grid
        var readings: [Double] = []
        for size in FFTWindowSize.allCases {
            let config = size.config(sampleRate: 48_000)
            let tracker = FrequencyTracker(config: config)
            let samples = FrequencyTracker.sineWave(frequency: trueHz, sampleRate: config.sampleRate, count: config.windowSize)
            let frequency = try #require(tracker.trackedFrequency(in: samples, weighting: .z))
            readings.append(frequency)
        }
        // Every size lands within a few Hz of the true tone, so the spread
        // across sizes is small -- the drift the user reported is gone.
        for reading in readings {
            #expect(abs(reading - trueHz) <= 3.0)
        }
        let spread = (readings.max() ?? 0) - (readings.min() ?? 0)
        #expect(spread <= 4.0)
    }

    // Edge safety: a near-DC winner (where interpolation would reach toward
    // bin 0) still returns a finite value and doesn't crash.
    @Test func handlesANearDCToneWithoutCrashing() throws {
        let tracker = FrequencyTracker(config: config)
        // Bin 1 territory at the default config (~5.86Hz).
        let samples = sineWave(frequency: binResolutionHz, sampleRate: config.sampleRate, count: config.windowSize)

        let frequency = try #require(tracker.trackedFrequency(in: samples, weighting: .z))
        #expect(frequency.isFinite)
        #expect(frequency > 0)
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
        // spectrum(in:) itself is always the raw, unweighted seam -- the
        // Anomaly Candidate detector (ADR 0001) consumes it directly and
        // must see true measured magnitude regardless of Weighting, so a
        // genuine low-frequency resonance isn't hidden by A-weighting's
        // roll-off. AudioAnalysisPipeline separately calls
        // weightedSpectrum(fromMagnitudes:weighting:) to produce what the
        // waterfall/RTA actually display.
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

    // weightedSpectrum (user report: "weighting doesn't seem to affect the
    // waterfall and RTA" -- previously true by design, now intentionally
    // wired through): applies Weighting's per-bin gain across the whole
    // spectrum, unlike trackedFrequency's single-winner argmax.

    @Test func weightedSpectrumAttenuatesLowFrequenciesUnderAWeighting() throws {
        let tracker = FrequencyTracker(config: config)
        let low = sineWave(frequency: 50, amplitude: 1.0, sampleRate: config.sampleRate, count: config.windowSize)
        let magnitudes = try #require(tracker.spectrum(in: low))
        let bin = Int((50 / binResolutionHz).rounded())

        let zWeighted = tracker.weightedSpectrum(fromMagnitudes: magnitudes, weighting: .z)
        let aWeighted = tracker.weightedSpectrum(fromMagnitudes: magnitudes, weighting: .a)

        // Z-weighting is flat (unchanged); A-weighting rolls off steeply
        // below 1kHz, so the same 50Hz bin should read much lower under A.
        #expect(zWeighted[bin] == magnitudes[bin])
        #expect(aWeighted[bin] < zWeighted[bin])
    }

    @Test func weightedSpectrumLeavesA1kHzToneUnchangedSinceAAndZAgreeThere() throws {
        let tracker = FrequencyTracker(config: config)
        let mid = sineWave(frequency: 1000, amplitude: 1.0, sampleRate: config.sampleRate, count: config.windowSize)
        let magnitudes = try #require(tracker.spectrum(in: mid))
        let bin = Int((1000 / binResolutionHz).rounded())

        let aWeighted = tracker.weightedSpectrum(fromMagnitudes: magnitudes, weighting: .a)

        #expect(abs(aWeighted[bin] - magnitudes[bin]) < magnitudes[bin] * 0.01)
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

    // trackedFrequencyLevelDb (ticket #12, CONTEXT.md "Peak" -- "Tracked
    // Frequency level"): the level of whichever bin trackedFrequency(
    // fromMagnitudes:weighting:) picked, in dB -- distinct from SPL (a sum
    // across the whole weighted spectrum) and from the Hz value itself.

    @Test func trackedFrequencyLevelIsLouderForALouderTone() throws {
        let tracker = FrequencyTracker(config: config)
        let quiet = sineWave(frequency: 1000, amplitude: 0.2, sampleRate: config.sampleRate, count: config.windowSize)
        let loud = sineWave(frequency: 1000, amplitude: 0.8, sampleRate: config.sampleRate, count: config.windowSize)

        let quietMagnitudes = try #require(tracker.spectrum(in: quiet))
        let loudMagnitudes = try #require(tracker.spectrum(in: loud))

        let quietLevel = try #require(tracker.trackedFrequencyLevelDb(fromMagnitudes: quietMagnitudes, weighting: .z))
        let loudLevel = try #require(tracker.trackedFrequencyLevelDb(fromMagnitudes: loudMagnitudes, weighting: .z))

        #expect(loudLevel > quietLevel)
    }

    @Test func trackedFrequencyLevelIsNilWhenSpectrumHasOnlyTheDCBin() {
        // Mirrors trackedFrequency(fromMagnitudes:weighting:)'s own nil
        // case: bin 0 (DC) is skipped as not a meaningful frequency, so a
        // single-bin spectrum has nothing left to pick a winner from.
        let tracker = FrequencyTracker(config: config)
        let dcOnly: [Float] = [1.0]

        #expect(tracker.trackedFrequencyLevelDb(fromMagnitudes: dcOnly, weighting: .z) == nil)
    }
}

// Regression coverage (user report: "the highest [FFT size] value just
// freeze") -- diagnosis traced this to FFTWindowSize not being marked
// `nonisolated`, so this module's default @MainActor isolation applied to
// it, making AnalysisConfig.default's initializer (`FFTWindowSize.default.
// config(sampleRate:)`) a real actor-isolation violation -- silently only a
// warning today ("this is an error in the Swift 6 language mode"), not a
// hard compile error, which is exactly the kind of undefined cross-actor
// access that produces intermittent hangs. This struct isn't @MainActor
// (Swift Testing test types aren't, unless annotated), so it exercises
// FFTWindowSize/FrequencyTracker construction from a genuinely nonisolated
// context the same way AudioAnalysisPipeline's background actor does --
// if FFTWindowSize (or a similarly-shaped future type) loses its
// `nonisolated` again, this reintroduces the same warning class, and
// results below would stop resolving correctly if the isolation mismatch
// ever became a hard failure rather than a silently-tolerated one.
struct FFTWindowSizeTests {

    @Test(arguments: FFTWindowSize.allCases)
    func constructsAWorkingFrequencyTrackerAtEverySize(_ size: FFTWindowSize) throws {
        let config = size.config(sampleRate: 48_000)
        #expect(config.windowSize == size.windowSize)
        #expect(config.hopSize == size.hopSize)

        let tracker = FrequencyTracker(config: config)
        let samples = FrequencyTracker.sineWave(frequency: 1000, sampleRate: config.sampleRate, count: config.windowSize)
        let frequency = try #require(tracker.trackedFrequency(in: samples, weighting: .z))
        #expect(abs(frequency - 1000) <= config.binResolutionHz)
    }

    // Root cause of the "RTA stutters, worse at high FFT size" report:
    // hop used to be hard-coupled to window size (always windowSize / 2),
    // so the whole pipeline's update rate degraded as the window grew --
    // ~6 spectra/second at 16384, measured via log instrumentation as the
    // RTA's bar targets only changing every ~170ms. No display smoothing
    // can hide a 6Hz data rate (smoothing reads as lag, snapping reads as
    // stutter), so the fix is at the source: hop is capped at 2048 samples
    // (~43ms at 48kHz), meaning larger windows overlap *more* instead of
    // updating slower -- the same trick real analyzers use.
    @Test func hopDurationNeverDegradesWithWindowSize() {
        for size in FFTWindowSize.allCases {
            let config = size.config(sampleRate: 48_000)
            let hopDuration = Double(config.hopSize) / config.sampleRate
            #expect(hopDuration <= 2048.0 / 48_000 + 0.0001)
        }
    }

    @Test func overlapIsAtLeastFiftyPercentAtEverySize() {
        for size in FFTWindowSize.allCases {
            #expect(size.hopSize <= size.windowSize / 2)
            #expect(size.hopSize > 0)
        }
    }

    @Test func defaultMatchesAnalysisConfigDefault() {
        #expect(AnalysisConfig.default == FFTWindowSize.default.config(sampleRate: AnalysisConfig.default.sampleRate))
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
