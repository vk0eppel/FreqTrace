//
//  SineOscillator.swift
//  FreqTrace
//
//  Pure phase-accumulator sine generator -- no AVAudioEngine dependency, so
//  it's directly unit-testable (see SignalGeneratorCoreTests). The audio
//  engine glue (SignalGeneratorEngine) pulls samples from this on the
//  real-time render thread.
//

import Foundation

struct SineOscillator {
    var frequency: Double
    var sampleRate: Double
    private var phase: Double

    init(frequency: Double, sampleRate: Double, initialPhase: Double = 0) {
        self.frequency = frequency
        self.sampleRate = sampleRate
        self.phase = initialPhase
    }

    /// Advances the oscillator by one sample and returns the new value,
    /// in [-1, 1].
    mutating func nextSample() -> Double {
        let sample = sin(phase)
        phase += 2 * .pi * frequency / sampleRate
        if phase >= 2 * .pi {
            phase -= 2 * .pi
        }
        return sample
    }
}
