//
//  SignalGeneratorCore.swift
//  FreqTrace
//
//  Ties waveform selection + level together into the single call the audio
//  engine's render block needs per sample: "give me the next sample for
//  this waveform at this amplitude." Holds one live generator per waveform
//  (rather than recreating on every switch) so phase/noise-filter state
//  isn't lost and rebuilt each time the tech flips the waveform picker.
//
//  Pure / no AVAudioEngine dependency -- see SignalGeneratorCoreTests.
//

import Foundation

// Pure value type, nonisolated: opts out of the module's default
// @MainActor isolation (Swift 6) -- runs on the audio render thread and
// in nonisolated unit tests.
nonisolated struct SignalGeneratorCore<RNG: RandomNumberGenerator> {
    /// Default sine frequency before the tech picks an ISO Band or types a
    /// custom Hz value (ticket #14, CONTEXT.md "ISO Band"). 1000Hz is also
    /// itself a standard ISO Band center.
    static var defaultSineFrequency: Double { 1000 }

    private var sine: SineOscillator
    private var white: WhiteNoiseGenerator<RNG>
    private var pink: PinkNoiseGenerator<RNG>

    init(sampleRate: Double, rng: RNG, sineFrequency: Double = SignalGeneratorCore.defaultSineFrequency) {
        sine = SineOscillator(frequency: sineFrequency, sampleRate: sampleRate)

        var pinkRNG = rng
        // Advance pinkRNG's state before use so it doesn't produce a stream
        // identical to the white generator's (both start from the same
        // copied seed).
        for _ in 0..<7 {
            _ = pinkRNG.next()
        }
        white = WhiteNoiseGenerator(rng: rng)
        pink = PinkNoiseGenerator(rng: pinkRNG)
    }

    /// Updates the sine oscillator's frequency in place (ticket #14 -- ISO
    /// Band stepping / free Hz entry). Preserves the oscillator's current
    /// phase so changing frequency mid-tone doesn't produce an audible
    /// click from a phase discontinuity.
    mutating func setSineFrequency(_ frequency: Double) {
        sine.frequency = frequency
    }

    /// Advances only the selected waveform's generator and returns its next
    /// sample scaled by `amplitude` (a linear multiplier, see `Decibels`).
    mutating func nextSample(waveform: Waveform, amplitude: Double) -> Double {
        switch waveform {
        case .sine:
            sine.nextSample() * amplitude
        case .whiteNoise:
            white.nextSample() * amplitude
        case .pinkNoise:
            pink.nextSample() * amplitude
        }
    }
}

// nonisolated: an extension is a separate declaration scope, so it takes the
// module default @MainActor again even though the primary `struct` above is
// nonisolated -- without this the convenience init is main-actor-isolated and
// can't be called from SignalGeneratorRenderState's nonisolated init (which
// runs the render state off the main actor for the audio thread).
nonisolated extension SignalGeneratorCore where RNG == SystemRandomNumberGenerator {
    init(sampleRate: Double, sineFrequency: Double = SignalGeneratorCore.defaultSineFrequency) {
        self.init(sampleRate: sampleRate, rng: SystemRandomNumberGenerator(), sineFrequency: sineFrequency)
    }
}
