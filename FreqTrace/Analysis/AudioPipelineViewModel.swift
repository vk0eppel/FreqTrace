//
//  AudioPipelineViewModel.swift
//  FreqTrace
//
//  @MainActor @Observable presentation layer for the shared capture -> FFT
//  -> tracking pipeline (ADR 0002): owns the ring buffer, capture engine,
//  and analysis pipeline; republishes AudioAnalysisPipeline's AsyncStream
//  as plain @Observable state every analysis view can read directly. This
//  is the seam CLAUDE.md's Architecture section describes as "Results are
//  published via AsyncStream to a @MainActor @Observable view model."
//
//  Originally named TrackedFrequencyViewModel (ticket #3); renamed here
//  (ticket #8) when the waterfall became a second consumer of the same
//  pipeline instance -- ADR 0002 explicitly designs for one shared pipeline
//  feeding every analysis view (Anomaly Candidate, SPL, RTA are still to
//  come), so this is the front door for all of them, not just Tracked
//  Frequency.
//

import Foundation
import Observation

@MainActor
@Observable
final class AudioPipelineViewModel {
    private(set) var trackedFrequencyHz: Double?
    /// Raw, unweighted power magnitude spectrum from the most recent hop --
    /// the waterfall's per-frame row. See FrequencyTracker.spectrum(in:).
    private(set) var latestMagnitudes: [Float] = []
    /// Raw (pre-offset) weighted level in dB from the most recent hop. See
    /// FrequencyTracker.weightedLevelDb(fromMagnitudes:weighting:).
    private(set) var splDb: Double?
    /// The SPL meter's manual numeric offset (CONTEXT.md "SPL Offset"),
    /// default 0 -- no real calibration in v1 (ADR 0003); this is a bare
    /// user-entered value, not derived from anything.
    var splOffsetDb: Double = 0
    /// Arbitrary but generous headroom for the offset field -- no
    /// calibration workflow exists yet to derive a "correct" range from.
    static let splOffsetRangeDB: ClosedRange<Double> = -60...60
    private(set) var isCaptureActive = false

    var weighting: Weighting = .default {
        didSet {
            guard weighting != oldValue else { return }
            let pipeline = pipeline
            Task { await pipeline.setWeighting(weighting) }
        }
    }

    /// FFT configuration in effect -- the waterfall needs this to map FFT
    /// bins to frequencies (see FrequencyAxis).
    let config: AnalysisConfig

    private let ringBuffer: AudioRingBuffer
    private let pipeline: AudioAnalysisPipeline
    private let captureEngine: MicrophoneCaptureEngine
    private var streamTask: Task<Void, Never>?

    init(config: AnalysisConfig = .default) {
        self.config = config
        // Two seconds of headroom at the configured sample rate -- generous
        // relative to the ~43ms hop cadence (2048 samples @ 48kHz), so a
        // brief scheduling delay on the consumer actor doesn't drop samples.
        let ringBufferCapacity = Int(config.sampleRate) * 2
        let ringBuffer = AudioRingBuffer(capacity: ringBufferCapacity)
        self.ringBuffer = ringBuffer
        self.pipeline = AudioAnalysisPipeline(config: config, ringBuffer: ringBuffer, weighting: .default)
        self.captureEngine = MicrophoneCaptureEngine(ringBuffer: ringBuffer)
    }

    /// Starts capturing from the system default input device and streaming
    /// analysis updates. Safe to call multiple times; a no-op once already
    /// running.
    func start() {
        guard !isCaptureActive else { return }
        do {
            try captureEngine.start()
        } catch {
            // No hardware/permission in this environment (or denied by the
            // user) -- readouts simply stay at their placeholder state. A
            // future ticket may surface this as an explicit disconnected
            // indicator (see ADR 0006 for the equivalent Input Device
            // disconnect behavior).
            return
        }
        isCaptureActive = true

        let pipeline = pipeline
        streamTask = Task { [weak self] in
            let stream = await pipeline.start()
            for await result in stream {
                guard !Task.isCancelled else { break }
                self?.trackedFrequencyHz = result.trackedFrequencyHz
                self?.latestMagnitudes = result.magnitudes
                self?.splDb = result.splDb
            }
        }
    }

    func stop() {
        streamTask?.cancel()
        streamTask = nil
        captureEngine.stop()
        isCaptureActive = false
        trackedFrequencyHz = nil
        latestMagnitudes = []
        splDb = nil
    }

    /// "2.34 kHz"-style formatting for the Measured Data row's hero number,
    /// or an em dash placeholder before capture produces a first result.
    var formattedFrequency: String {
        guard let hz = trackedFrequencyHz else { return "\u{2014}" }
        return String(format: "%.2f kHz", hz / 1000)
    }

    /// "86 dB"-style formatting for the SPL block, including the manual
    /// offset -- displayed = raw dBFS + offset (ticket #6), or an em dash
    /// placeholder before capture produces a first result.
    var formattedSPL: String {
        guard let splDb else { return "\u{2014}" }
        return "\(Int((splDb + splOffsetDb).rounded())) dB"
    }
}
