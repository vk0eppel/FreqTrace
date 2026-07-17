//
//  WhiteNoiseGenerator.swift
//  FreqTrace
//
//  Pure uniform-random noise generator -- no AVAudioEngine dependency, see
//  SignalGeneratorCoreTests. Generic over RandomNumberGenerator so tests can
//  inject SeededRandomNumberGenerator for reproducible assertions while
//  playback uses SystemRandomNumberGenerator.
//

import Foundation

// Pure value type, nonisolated: opts out of the module's default
// @MainActor isolation (Swift 6) -- runs on the audio render thread and
// in nonisolated unit tests.
nonisolated struct WhiteNoiseGenerator<RNG: RandomNumberGenerator> {
    private var rng: RNG

    init(rng: RNG) {
        self.rng = rng
    }

    /// Returns the next uniformly-distributed sample in [-1, 1].
    mutating func nextSample() -> Double {
        Double.random(in: -1...1, using: &rng)
    }
}

extension WhiteNoiseGenerator where RNG == SystemRandomNumberGenerator {
    init() {
        self.init(rng: SystemRandomNumberGenerator())
    }
}
