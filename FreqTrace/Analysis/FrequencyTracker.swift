//
//  FrequencyTracker.swift
//  FreqTrace
//
//  The pure analysis engine at the heart of the Tracked Frequency feature
//  (see CONTEXT.md "Tracked Frequency"): takes a raw sample buffer and a
//  Weighting, produces the single highest-energy frequency. Deliberately
//  decoupled from AVAudioEngine/AudioAnalysisPipeline -- this is the test
//  seam (see FreqTraceTests/FrequencyTrackerTests.swift), fed synthetic sine
//  waves rather than real hardware audio.
//
//  Uses vDSP's real-to-complex FFT (vDSP_fft_zrip). The FFT setup is cached
//  per instance since AudioAnalysisPipeline calls this on every hop and
//  vDSP_create_fftsetup is not cheap to redo per call.
//

import Accelerate
import Foundation

// This module defaults new types to @MainActor isolation
// (SWIFT_DEFAULT_ACTOR_ISOLATION), but this is called synchronously from the
// AudioAnalysisPipeline actor on a background thread, so it opts out
// explicitly and relies on its own internal synchronization guarantee
// instead: all mutable state (the cached FFT setup/window) is set up once in
// init and never mutated afterward.
nonisolated final class FrequencyTracker: @unchecked Sendable {
    let config: AnalysisConfig

    private let log2n: vDSP_Length
    private let fftSetup: FFTSetup
    private let hannWindow: [Float]

    init(config: AnalysisConfig) {
        precondition(
            config.windowSize > 0 && (config.windowSize & (config.windowSize - 1)) == 0,
            "windowSize must be a power of two, got \(config.windowSize)"
        )
        self.config = config
        self.log2n = vDSP_Length(log2(Double(config.windowSize)))
        guard let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else {
            preconditionFailure("vDSP_create_fftsetup failed for windowSize \(config.windowSize)")
        }
        self.fftSetup = setup

        var window = [Float](repeating: 0, count: config.windowSize)
        vDSP_hann_window(&window, vDSP_Length(config.windowSize), Int32(vDSP_HANN_NORM))
        self.hannWindow = window
    }

    deinit {
        vDSP_destroy_fftsetup(fftSetup)
    }

    /// Returns the highest-energy frequency (Hz) in `samples` per `weighting`,
    /// or `nil` if fewer than `config.windowSize` samples were supplied. Only
    /// the most recent `config.windowSize` samples are analyzed.
    func trackedFrequency(in samples: [Float], weighting: Weighting) -> Double? {
        let n = config.windowSize
        guard samples.count >= n else { return nil }
        let windowStart = samples.count - n

        var windowed = [Float](repeating: 0, count: n)
        samples.withUnsafeBufferPointer { samplesPtr in
            vDSP_vmul(samplesPtr.baseAddress! + windowStart, 1, hannWindow, 1, &windowed, 1, vDSP_Length(n))
        }

        let halfN = n / 2
        var realp = [Float](repeating: 0, count: halfN)
        var imagp = [Float](repeating: 0, count: halfN)
        var magnitudes = [Float](repeating: 0, count: halfN)

        realp.withUnsafeMutableBufferPointer { realPtr in
            imagp.withUnsafeMutableBufferPointer { imagPtr in
                var splitComplex = DSPSplitComplex(realp: realPtr.baseAddress!, imagp: imagPtr.baseAddress!)
                windowed.withUnsafeBufferPointer { windowedPtr in
                    windowedPtr.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: halfN) { complexPtr in
                        vDSP_ctoz(complexPtr, 2, &splitComplex, 1, vDSP_Length(halfN))
                    }
                }
                vDSP_fft_zrip(fftSetup, &splitComplex, 1, log2n, FFTDirection(FFT_FORWARD))
                vDSP_zvmags(&splitComplex, 1, &magnitudes, 1, vDSP_Length(halfN))
            }
        }

        let binHz = config.sampleRate / Double(n)
        let nyquist = config.sampleRate / 2

        var bestBin = -1
        var bestWeightedMagnitude: Float = -Float.greatestFiniteMagnitude
        // Bin 0 is DC (no meaningful frequency) -- skip it.
        for bin in 1..<halfN {
            let frequency = Double(bin) * binHz
            guard frequency <= nyquist else { break }
            let gainDb = weighting.gainDb(at: frequency)
            // magnitudes[] from vDSP_zvmags is power (amplitude^2), so the
            // weighting gain (an amplitude-domain dB value) is applied
            // twice in the dB->linear conversion to stay in power terms.
            let gainLinearPower = Float(pow(10, gainDb / 10))
            let weighted = magnitudes[bin] * gainLinearPower
            if weighted > bestWeightedMagnitude {
                bestWeightedMagnitude = weighted
                bestBin = bin
            }
        }

        guard bestBin > 0 else { return nil }
        return Double(bestBin) * binHz
    }
}
