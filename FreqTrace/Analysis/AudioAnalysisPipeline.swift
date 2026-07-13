//
//  AudioAnalysisPipeline.swift
//  FreqTrace
//
//  The background actor half of the shared capture -> FFT -> tracking
//  pipeline (ADR 0002): drains AudioRingBuffer in hop-sized chunks, keeps a
//  rolling FFT window, runs FrequencyTracker, and publishes results via
//  AsyncStream. Everything here runs off the real-time audio thread.
//

import Foundation

struct AnalysisResult: Sendable {
    let trackedFrequencyHz: Double
    /// Raw, unweighted power magnitude per FFT bin (length config.windowSize
    /// / 2) -- the waterfall's per-frame row (see WaterfallHistoryBuffer).
    /// Deliberately unweighted; see FrequencyTracker.spectrum(in:).
    let magnitudes: [Float]
    /// Weighted overall level in dB, self-calibrated so full-scale reads
    /// ~0dB -- the SPL meter's raw (pre-offset) reading (ticket #6,
    /// CONTEXT.md "SPL Offset"). Uses the same shared Weighting as
    /// trackedFrequencyHz.
    let splDb: Double
    /// The level (dB) of the tracked-frequency bin itself (ticket #12,
    /// CONTEXT.md "Peak" -- "Tracked Frequency level") -- distinct from
    /// splDb, which sums across the whole weighted spectrum.
    let trackedFrequencyLevelDb: Double
    /// Top 2-3 Anomaly Candidates, ranked by severity (ticket #5, ADR
    /// 0001, CONTEXT.md "Anomaly Candidate"), or empty when nothing is
    /// currently flagged.
    let anomalyCandidates: [AnomalyCandidate]
    /// FrequencyTracker.fullScalePower -- the reference the waterfall/RTA
    /// must divide raw magnitudes by before applying MagnitudeScaling's
    /// dB floor/ceiling (bug fix: raw vDSP power isn't already on a
    /// [0,1]/dBFS scale).
    let fullScalePower: Float
    let timestamp: Date
}

actor AudioAnalysisPipeline {
    private let config: AnalysisConfig
    private let ringBuffer: AudioRingBuffer
    private let tracker: FrequencyTracker

    private var rollingWindow: [Float]
    private var weighting: Weighting
    /// Time Averaging (ticket #7, CONTEXT.md "Time Averaging"): only feeds
    /// Tracked Frequency's argmax (and its paired level reading) -- the
    /// spectrum published in AnalysisResult.magnitudes stays the true,
    /// unblended measurement (waterfall/RTA/SPL all need that).
    private var timeAveraging: TimeAveragingPreset = .fast
    private var timeAveragingBlender = TimeAveragingBlender()
    /// Anomaly Candidate detection (ticket #5) runs on the raw spectrum,
    /// never the Time-Averaging-blended one -- hardcoded to Fast
    /// (CONTEXT.md "Time Averaging"): the detector's own rolling sustain
    /// window is what governs its responsiveness, not this pipeline's
    /// user-selectable Tracked Frequency smoothing.
    private var anomalyDetector = AnomalyDetector()
    private var pollTask: Task<Void, Never>?

    init(config: AnalysisConfig, ringBuffer: AudioRingBuffer, weighting: Weighting = .default) {
        self.config = config
        self.ringBuffer = ringBuffer
        self.tracker = FrequencyTracker(config: config)
        self.rollingWindow = [Float](repeating: 0, count: config.windowSize)
        self.weighting = weighting
    }

    func setWeighting(_ weighting: Weighting) {
        self.weighting = weighting
    }

    func setTimeAveraging(_ preset: TimeAveragingPreset) {
        self.timeAveraging = preset
    }

    /// Starts (or restarts) draining the ring buffer and returns a stream of
    /// results, one per hop once enough samples have accumulated. Cancelling
    /// the consuming Task or letting the stream deinit terminates polling.
    func start() -> AsyncStream<AnalysisResult> {
        pollTask?.cancel()
        return AsyncStream { continuation in
            let task = Task { [weak self] in
                guard let self else { return }
                await self.pollLoop(continuation: continuation)
            }
            pollTask = task
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    private func pollLoop(continuation: AsyncStream<AnalysisResult>.Continuation) async {
        var hopBuffer = [Float](repeating: 0, count: config.hopSize)

        while !Task.isCancelled {
            let read = ringBuffer.read(into: &hopBuffer, count: config.hopSize)
            guard read == config.hopSize else {
                // Not enough new samples yet -- wait roughly one hop's worth
                // of real time before checking again rather than busy-polling.
                try? await Task.sleep(nanoseconds: 5_000_000)
                continue
            }

            rollingWindow.removeFirst(config.hopSize)
            rollingWindow.append(contentsOf: hopBuffer)

            // Run the FFT once per hop and derive all three outputs from
            // it, rather than calling trackedFrequency(in:weighting:),
            // spectrum(in:), and weightedLevelDb(...) separately (each
            // would redo the same FFT).
            if let magnitudes = tracker.spectrum(in: rollingWindow) {
                // Copy-out/mutate/copy-back, not a direct mutating call on
                // the stored property (found by code review, and
                // confirmed by trying the direct call): Swift's actor
                // isolation checker rejects `timeAveragingBlender.blend(...)`
                // / `anomalyDetector.process(...)` called directly here
                // ("cannot be passed 'inout' to implicitly 'async' function
                // call") -- a real compiler limitation in this context, not
                // a mistake to simplify away. A generic keyPath-based
                // helper was tried too (to de-duplicate the two identical
                // call sites) but keyPaths can't be formed to
                // actor-isolated stored properties either, so this stays
                // duplicated rather than fighting the type system further.
                var blender = timeAveragingBlender
                let blendedForTracking = blender.blend(magnitudes, preset: timeAveraging)
                timeAveragingBlender = blender
                if let frequency = tracker.trackedFrequency(fromMagnitudes: blendedForTracking, weighting: weighting) {
                    let splDb = tracker.weightedLevelDb(fromMagnitudes: magnitudes, weighting: weighting)
                    let levelDb = tracker.trackedFrequencyLevelDb(fromMagnitudes: blendedForTracking, weighting: weighting) ?? -Double.infinity
                    var detector = anomalyDetector
                    let anomalyCandidates = detector.process(magnitudes: magnitudes, config: config)
                    anomalyDetector = detector
                    continuation.yield(AnalysisResult(
                        trackedFrequencyHz: frequency, magnitudes: magnitudes, splDb: splDb,
                        trackedFrequencyLevelDb: levelDb, anomalyCandidates: anomalyCandidates,
                        fullScalePower: tracker.fullScalePower, timestamp: Date()
                    ))
                }
            }
        }
        continuation.finish()
    }
}
