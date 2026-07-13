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

    private func sineWave(frequency: Double, amplitude: Float = 1.0, sampleRate: Double, count: Int) -> [Float] {
        (0..<count).map { i in
            amplitude * Float(sin(2 * Double.pi * frequency * Double(i) / sampleRate))
        }
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
}
