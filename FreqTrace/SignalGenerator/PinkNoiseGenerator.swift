//
//  PinkNoiseGenerator.swift
//  FreqTrace
//
//  Voss-McCartney pink noise (-3dB/octave rolloff): a fixed number of
//  "rows", each holding a random value; on every sample exactly one row
//  (chosen by the trailing-zero-bit count of an incrementing counter, so
//  low rows update on nearly every sample and high rows update rarely) is
//  re-rolled, plus one extra always-fresh white component (McCartney's
//  refinement, avoids the plain Voss algorithm's audible "stepping"). The
//  running sum of all rows, averaged, is the pink sample -- bounded to
//  [-1, 1] since it's an average of values already in that range.
//
//  Pure / no AVAudioEngine dependency, see SignalGeneratorCoreTests.
//

import Foundation

// Pure value type, nonisolated: opts out of the module's default
// @MainActor isolation (Swift 6) -- runs on the audio render thread and
// in nonisolated unit tests.
nonisolated struct PinkNoiseGenerator<RNG: RandomNumberGenerator> {
    private var rng: RNG
    private var rows: [Double]
    private var runningSum: Double = 0
    private var counter: UInt64 = 0
    private let rowCount: Int

    init(rng: RNG, rowCount: Int = 16) {
        self.rng = rng
        self.rowCount = max(rowCount, 1)
        self.rows = []
        self.rows.reserveCapacity(self.rowCount)
        for _ in 0..<self.rowCount {
            let value = Double.random(in: -1...1, using: &self.rng)
            self.rows.append(value)
            self.runningSum += value
        }
    }

    /// Returns the next pink-noise sample in [-1, 1].
    mutating func nextSample() -> Double {
        counter += 1
        let index = min(counter.trailingZeroBitCount, rowCount - 1)
        let newValue = Double.random(in: -1...1, using: &rng)
        runningSum += newValue - rows[index]
        rows[index] = newValue

        let whiteComponent = Double.random(in: -1...1, using: &rng)
        return (runningSum + whiteComponent) / Double(rowCount + 1)
    }
}

extension PinkNoiseGenerator where RNG == SystemRandomNumberGenerator {
    init(rowCount: Int = 16) {
        self.init(rng: SystemRandomNumberGenerator(), rowCount: rowCount)
    }
}
