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

    /// Sum of the (unweighted) magnitude spectrum for a synthetic
    /// full-scale (amplitude 1.0) 1kHz reference tone, computed once at
    /// init through the exact same FFT/window pipeline every real
    /// measurement uses. weightedLevelDb(fromMagnitudes:weighting:)
    /// normalizes against this so a full-scale signal reads ~0dB --
    /// self-calibrating rather than a hardcoded constant, so it stays
    /// correct if `config` (window size, sample rate) ever changes,
    /// without needing to derive vDSP's FFT/window scaling convention by
    /// hand. See SPLTests.
    private let fullScalePower: Float

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

        // Self-calibration: run a synthetic reference tone through the
        // static (self-independent) FFT helper, since all other stored
        // properties above are already set but fullScalePower itself isn't
        // yet -- Swift requires every stored property to have a value
        // before any instance method call, so this can't call the
        // instance-method computeMagnitudes(in:) here.
        let referenceTone = Self.sineWave(frequency: 1000, amplitude: 1.0, sampleRate: config.sampleRate, count: config.windowSize)
        let referenceMagnitudes = Self.computeMagnitudes(
            in: referenceTone, hannWindow: window, fftSetup: setup, log2n: log2n, windowSize: config.windowSize
        ) ?? []
        self.fullScalePower = referenceMagnitudes.reduce(0, +)
    }

    deinit {
        vDSP_destroy_fftsetup(fftSetup)
    }

    /// Returns the highest-energy frequency (Hz) in `samples` per `weighting`,
    /// or `nil` if fewer than `config.windowSize` samples were supplied. Only
    /// the most recent `config.windowSize` samples are analyzed.
    func trackedFrequency(in samples: [Float], weighting: Weighting) -> Double? {
        guard let magnitudes = computeMagnitudes(in: samples) else { return nil }
        return trackedFrequency(fromMagnitudes: magnitudes, weighting: weighting)
    }

    /// Returns the raw, unweighted power magnitude spectrum (length
    /// `config.windowSize / 2`, one entry per FFT bin) for `samples`, or
    /// `nil` if fewer than `config.windowSize` samples were supplied. This
    /// is the seam the waterfall (see WaterfallHistoryBuffer) consumes --
    /// deliberately unweighted, since Weighting only applies to Tracked
    /// Frequency / SPL (CONTEXT.md "Weighting"), not the true measured
    /// spectrum a spectrogram displays.
    func spectrum(in samples: [Float]) -> [Float]? {
        computeMagnitudes(in: samples)
    }

    /// Weighted argmax over an already-computed magnitude spectrum. Lets a
    /// caller needing both Tracked Frequency and the raw spectrum from the
    /// same samples (see AudioAnalysisPipeline) run the FFT once via
    /// spectrum(in:) and derive both from it, rather than running the FFT
    /// twice per hop.
    func trackedFrequency(fromMagnitudes magnitudes: [Float], weighting: Weighting) -> Double? {
        let binHz = config.sampleRate / Double(config.windowSize)
        let nyquist = config.sampleRate / 2

        var bestBin = -1
        var bestWeightedMagnitude: Float = -Float.greatestFiniteMagnitude
        // Bin 0 is DC (no meaningful frequency) -- skip it.
        for bin in 1..<magnitudes.count {
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

    /// Weighted overall level in dB from an already-computed magnitude
    /// spectrum, normalized against fullScalePower so a full-scale signal
    /// reads ~0dB ("dBFS") -- the SPL meter's seam (ticket #6, CONTEXT.md
    /// "SPL Offset"). Sums weighted power across all bins rather than
    /// picking a single peak (contrast with trackedFrequency(fromMagnitudes:)),
    /// since an overall level describes the whole spectrum's energy, not
    /// one dominant frequency.
    func weightedLevelDb(fromMagnitudes magnitudes: [Float], weighting: Weighting) -> Double {
        let binHz = config.sampleRate / Double(config.windowSize)
        var weightedPower: Double = 0
        for bin in 1..<magnitudes.count {
            let frequency = Double(bin) * binHz
            let gainLinearPower = pow(10, weighting.gainDb(at: frequency) / 10)
            weightedPower += Double(magnitudes[bin]) * gainLinearPower
        }
        guard fullScalePower > 0 else { return -Double.infinity }
        return 10 * log10(max(weightedPower, 1e-12) / Double(fullScalePower))
    }

    private func computeMagnitudes(in samples: [Float]) -> [Float]? {
        Self.computeMagnitudes(in: samples, hannWindow: hannWindow, fftSetup: fftSetup, log2n: log2n, windowSize: config.windowSize)
    }

    private static func sineWave(frequency: Double, amplitude: Float, sampleRate: Double, count: Int) -> [Float] {
        (0..<count).map { i in
            amplitude * Float(sin(2 * Double.pi * frequency * Double(i) / sampleRate))
        }
    }

    private static func computeMagnitudes(
        in samples: [Float], hannWindow: [Float], fftSetup: FFTSetup, log2n: vDSP_Length, windowSize: Int
    ) -> [Float]? {
        let n = windowSize
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

        return magnitudes
    }
}
