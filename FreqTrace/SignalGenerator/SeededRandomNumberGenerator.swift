//
//  SeededRandomNumberGenerator.swift
//  FreqTrace
//
//  A deterministic RandomNumberGenerator (xorshift64*) so the noise
//  generators can be driven reproducibly in unit tests without touching
//  SystemRandomNumberGenerator's non-deterministic output. Not used for
//  the real playback path, where SystemRandomNumberGenerator is fine.
//

import Foundation

// Pure value type, nonisolated: opts out of the module's default
// @MainActor isolation (Swift 6) -- runs on the audio render thread and
// in nonisolated unit tests.
nonisolated struct SeededRandomNumberGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        // xorshift64* is undefined at a zero state, so nudge away from it.
        self.state = seed == 0 ? 0x9e3779b97f4a7c15 : seed
    }

    mutating func next() -> UInt64 {
        state ^= state >> 12
        state ^= state << 25
        state ^= state >> 27
        return state &* 2685821657736338717
    }
}
