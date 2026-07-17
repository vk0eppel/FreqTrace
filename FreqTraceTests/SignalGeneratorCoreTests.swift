//
//  SignalGeneratorCoreTests.swift
//  FreqTraceTests
//
//  Tests for the pure, AVAudioEngine-free waveform-generation seam (see
//  CLAUDE.md's Signal Generator bullet and issue #9). These exercise only
//  math -- no audio hardware, no AVAudioEngine -- so they run fully in CI
//  and in this sandbox with no manual verification needed. The engine glue
//  built on top of this (SignalGeneratorEngine) is NOT covered here; it
//  needs manual on-hardware verification instead.
//

import Foundation
import Testing
@testable import FreqTrace

struct DecibelsTests {

    @Test func zeroDBIsUnityAmplitude() {
        #expect(abs(Decibels.linearAmplitude(fromDecibels: 0) - 1.0) < 0.0001)
    }

    @Test func minusSixDBIsApproximatelyHalfAmplitude() {
        let amplitude = Decibels.linearAmplitude(fromDecibels: -6)
        #expect(abs(amplitude - 0.501187) < 0.0005)
    }

    @Test func minusSixtySixDBIsVerySmallButNonzero() {
        let amplitude = Decibels.linearAmplitude(fromDecibels: -66)
        #expect(amplitude > 0)
        #expect(amplitude < 0.001)
    }

    @Test func roundTripsThroughDecibelsAndBack() {
        for db in stride(from: -90.0, through: 0.0, by: 6.0) {
            let amplitude = Decibels.linearAmplitude(fromDecibels: db)
            let roundTripped = Decibels.decibels(fromLinearAmplitude: amplitude)
            #expect(abs(roundTripped - db) < 0.001)
        }
    }

    @Test func unityAmplitudeRoundTripsToZeroDB() {
        #expect(abs(Decibels.decibels(fromLinearAmplitude: 1.0) - 0.0) < 0.0001)
    }
}

struct SineOscillatorTests {

    @Test func producesExpectedPeriodicity() {
        // 1kHz tone at 48kHz sample rate has an exact 48-sample period, so
        // sample[n] and sample[n + 48] must match once the oscillator has
        // wrapped at least once.
        var oscillator = SineOscillator(frequency: 1000, sampleRate: 48000)
        let first = (0..<48).map { _ in oscillator.nextSample() }
        var oscillatorAgain = SineOscillator(frequency: 1000, sampleRate: 48000)
        for _ in 0..<48 { _ = oscillatorAgain.nextSample() }
        let second = (0..<48).map { _ in oscillatorAgain.nextSample() }
        for i in 0..<48 {
            #expect(abs(first[i] - second[i]) < 0.0001)
        }
    }

    @Test func zeroCrossingsMatchExpectedFrequency() {
        // A 1kHz tone sampled for exactly 1 second at 48kHz should cross
        // zero (rising) almost exactly 1000 times.
        let sampleRate = 48000.0
        let frequency = 1000.0
        var oscillator = SineOscillator(frequency: frequency, sampleRate: sampleRate)
        var samples: [Double] = []
        samples.reserveCapacity(Int(sampleRate))
        for _ in 0..<Int(sampleRate) {
            samples.append(oscillator.nextSample())
        }
        var risingCrossings = 0
        for i in 1..<samples.count {
            if samples[i - 1] < 0 && samples[i] >= 0 {
                risingCrossings += 1
            }
        }
        #expect(abs(Double(risingCrossings) - frequency) <= 1)
    }

    @Test func staysWithinUnityAmplitude() {
        var oscillator = SineOscillator(frequency: 440, sampleRate: 48000)
        for _ in 0..<48000 {
            let sample = oscillator.nextSample()
            #expect(sample >= -1.0001 && sample <= 1.0001)
        }
    }
}

struct WhiteNoiseGeneratorTests {

    @Test func staysWithinUnityAmplitudeBounds() {
        let rng = SeededRandomNumberGenerator(seed: 1)
        var generator = WhiteNoiseGenerator(rng: rng)
        for _ in 0..<10_000 {
            let sample = generator.nextSample()
            #expect(sample >= -1.0 && sample <= 1.0)
        }
        _ = rng // silence unused-var warning if generator copies internally
    }

    @Test func isNotConstantOrSilent() {
        var generator = WhiteNoiseGenerator(rng: SeededRandomNumberGenerator(seed: 42))
        let samples = (0..<1000).map { _ in generator.nextSample() }
        let distinctValues = Set(samples.map { ($0 * 1_000_000).rounded() })
        #expect(distinctValues.count > 500)
        let allZero = samples.allSatisfy { $0 == 0 }
        #expect(!allZero)
    }

    @Test func hasSubstantialAmplitudeSpread() {
        // A real noise source should exercise a wide portion of its range,
        // not cluster near zero.
        var generator = WhiteNoiseGenerator(rng: SeededRandomNumberGenerator(seed: 7))
        let samples = (0..<10_000).map { _ in generator.nextSample() }
        let maxAbs = samples.map { abs($0) }.max() ?? 0
        #expect(maxAbs > 0.9)
    }
}

struct PinkNoiseGeneratorTests {

    @Test func staysWithinUnityAmplitudeBounds() {
        var generator = PinkNoiseGenerator(rng: SeededRandomNumberGenerator(seed: 1))
        for _ in 0..<10_000 {
            let sample = generator.nextSample()
            #expect(sample >= -1.0 && sample <= 1.0)
        }
    }

    @Test func isNotConstantOrSilent() {
        var generator = PinkNoiseGenerator(rng: SeededRandomNumberGenerator(seed: 42))
        let samples = (0..<1000).map { _ in generator.nextSample() }
        let distinctValues = Set(samples.map { ($0 * 1_000_000).rounded() })
        #expect(distinctValues.count > 200)
        let allZero = samples.allSatisfy { $0 == 0 }
        #expect(!allZero)
    }

    @Test func hasLowerHighFrequencyEnergyThanWhiteNoise() {
        // Pink noise's defining property is a -3dB/octave rolloff, i.e.
        // less energy at high frequencies than white noise. A cheap,
        // implementation-agnostic proxy for that: pink noise's sample-to-
        // sample deltas (a high-pass-ish measure) should have lower average
        // magnitude, relative to its own amplitude spread, than white
        // noise's -- pink noise is "smoother" sample to sample.
        var pink = PinkNoiseGenerator(rng: SeededRandomNumberGenerator(seed: 3))
        var white = WhiteNoiseGenerator(rng: SeededRandomNumberGenerator(seed: 3))
        let count = 20_000
        let pinkSamples = (0..<count).map { _ in pink.nextSample() }
        let whiteSamples = (0..<count).map { _ in white.nextSample() }

        func averageAbsoluteDelta(_ samples: [Double]) -> Double {
            var sum = 0.0
            for i in 1..<samples.count {
                sum += abs(samples[i] - samples[i - 1])
            }
            return sum / Double(samples.count - 1)
        }

        func rms(_ samples: [Double]) -> Double {
            sqrt(samples.reduce(0) { $0 + $1 * $1 } / Double(samples.count))
        }

        let pinkSmoothness = averageAbsoluteDelta(pinkSamples) / rms(pinkSamples)
        let whiteSmoothness = averageAbsoluteDelta(whiteSamples) / rms(whiteSamples)
        #expect(pinkSmoothness < whiteSmoothness)
    }
}

struct SignalGeneratorCoreTests {

    @Test func appliesAmplitudeToSineOutput() {
        var core = SignalGeneratorCore(sampleRate: 48000, rng: SeededRandomNumberGenerator(seed: 1))
        let fullScale = (0..<48).map { _ in core.nextSample(waveform: .sine, amplitude: 1.0) }

        var coreAtHalf = SignalGeneratorCore(sampleRate: 48000, rng: SeededRandomNumberGenerator(seed: 1))
        let halfScale = (0..<48).map { _ in coreAtHalf.nextSample(waveform: .sine, amplitude: 0.5) }

        for i in 0..<48 {
            #expect(abs(halfScale[i] - fullScale[i] * 0.5) < 0.0001)
        }
    }

    @Test func silentAtZeroAmplitude() {
        var core = SignalGeneratorCore(sampleRate: 48000, rng: SeededRandomNumberGenerator(seed: 1))
        for waveform in Waveform.allCases {
            for _ in 0..<100 {
                #expect(core.nextSample(waveform: waveform, amplitude: 0.0) == 0.0)
            }
        }
    }

    @Test func switchingWaveformProducesDistinctCharacter() {
        var core = SignalGeneratorCore(sampleRate: 48000, rng: SeededRandomNumberGenerator(seed: 5))
        let sine = (0..<256).map { _ in core.nextSample(waveform: .sine, amplitude: 1.0) }
        let white = (0..<256).map { _ in core.nextSample(waveform: .whiteNoise, amplitude: 1.0) }
        #expect(sine != white)
    }
}

struct WaveformTests {

    @Test func hasExactlyThreeCasesNoSweeps() {
        #expect(Waveform.allCases.count == 3)
        #expect(Waveform.allCases.contains(.sine))
        #expect(Waveform.allCases.contains(.pinkNoise))
        #expect(Waveform.allCases.contains(.whiteNoise))
    }
}
