//
//  RTABinningTests.swift
//  FreqTraceTests
//
//  Exercises RTABinning.bars, the pure log-frequency bar-binning logic
//  behind the RTA view (ticket #11): resamples a raw FFT magnitude
//  spectrum (FrequencyTracker.spectrum(in:)'s output) into a fixed number
//  of log-frequency-spaced, normalized [0,1] bars, reusing FrequencyAxis
//  (log mapping) and MagnitudeScaling (dB normalization) -- both already
//  covered by WaterfallLogicTests.swift, so these tests focus on the
//  binning behavior itself, not re-testing the shared math.
//

import Foundation
import Testing
@testable import FreqTrace

struct RTABinningTests {

    private let config = AnalysisConfig.default // 48kHz / 4096-window / 2048-hop

    @Test func producesExactlyBarCountBars() {
        let magnitudes = [Float](repeating: 0, count: config.windowSize / 2)

        let bars = RTABinning.bars(magnitudes: magnitudes, config: config, barCount: 32, fullScalePower: 1.0)

        #expect(bars.count == 32)
    }

    @Test func emptyMagnitudesProducesEmptyBars() {
        let bars = RTABinning.bars(magnitudes: [], config: config, barCount: 32, fullScalePower: 1.0)

        #expect(bars.isEmpty)
    }

    @Test func loudToneProducesAPeakInTheBarMatchingItsLogFrequencyPosition() {
        var magnitudes = [Float](repeating: 0, count: config.windowSize / 2)
        let binHz = config.sampleRate / Double(config.windowSize)
        let toneBin = Int(1000 / binHz) // 1kHz
        magnitudes[toneBin] = 1.0 // full-scale power

        let barCount = 48
        let bars = RTABinning.bars(magnitudes: magnitudes, config: config, barCount: barCount, fullScalePower: 1.0)

        let expectedBar = min(barCount - 1, Int(FrequencyAxis.normalizedPosition(forHz: 1000) * Double(barCount)))
        let loudestBar = bars.indices.max(by: { bars[$0] < bars[$1] })!

        #expect(loudestBar == expectedBar)
        #expect(bars[expectedBar] > 0.9) // near full-scale after normalization
    }

    @Test func silentSpectrumProducesBarsAtTheFloor() {
        let magnitudes = [Float](repeating: 0, count: config.windowSize / 2)

        let bars = RTABinning.bars(magnitudes: magnitudes, config: config, barCount: 32, fullScalePower: 1.0)

        #expect(bars.allSatisfy { $0 == 0 })
    }

    // Regression test for a real bug: raw vDSP FFT power is NOT already
    // normalized to a [0,1]/dBFS scale (a full-scale tone's raw power is
    // on the order of 10^6-10^7 for this window size, not ~1.0) --
    // without dividing by a full-scale reference first, MagnitudeScaling's
    // -80/0dB floor/ceiling clamped virtually everything to the ceiling,
    // pegging every bar to max regardless of actual loudness (reported by
    // the user as "RTA is out of window" / "everything looks too high").
    @Test func rawUnnormalizedVDSPScalePowerIsCorrectlyReferencedAgainstFullScalePower() {
        // A realistic full-scale-tone raw power magnitude for a 4096-point
        // FFT (order of magnitude only -- the exact vDSP constant doesn't
        // matter, what matters is it's nowhere near 1.0).
        let realisticFullScaleRawPower: Float = 4_000_000
        var loudMagnitudes = [Float](repeating: 0, count: config.windowSize / 2)
        var quietMagnitudes = [Float](repeating: 0, count: config.windowSize / 2)
        let binHz = config.sampleRate / Double(config.windowSize)
        let toneBin = Int(1000 / binHz)
        loudMagnitudes[toneBin] = realisticFullScaleRawPower
        // -12dB half-amplitude-squared-ish quieter tone (power, not
        // amplitude, so -12dB power ~ a quarter of the full-scale power).
        quietMagnitudes[toneBin] = realisticFullScaleRawPower * Float(pow(10, -12.0 / 10.0))

        let loudBars = RTABinning.bars(
            magnitudes: loudMagnitudes, config: config, barCount: 48, fullScalePower: realisticFullScaleRawPower
        )
        let quietBars = RTABinning.bars(
            magnitudes: quietMagnitudes, config: config, barCount: 48, fullScalePower: realisticFullScaleRawPower
        )
        let bin = min(47, Int(FrequencyAxis.normalizedPosition(forHz: 1000) * 48))

        // Both must NOT simply peg to 1.0 -- the quieter tone should read
        // meaningfully lower than the loud one, proving the raw power was
        // actually referenced against fullScalePower before normalizing.
        #expect(loudBars[bin] > 0.9)
        #expect(quietBars[bin] < loudBars[bin])
        #expect(quietBars[bin] > 0.0)
    }
}
