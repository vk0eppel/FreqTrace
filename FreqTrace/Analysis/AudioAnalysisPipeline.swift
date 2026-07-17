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
    /// Power magnitude per FFT bin (length config.windowSize / 2) -- the
    /// waterfall's per-frame row and the RTA's source spectrum (see
    /// WaterfallHistoryBuffer, RTABinning). Weighted (FrequencyTracker.
    /// weightedSpectrum) and Time-Averaging-blended, same as Tracked
    /// Frequency -- so the display responds to both controls. The Anomaly
    /// Candidate detector does NOT read this field; it consumes
    /// spectrum(in:)'s raw output directly inside the pipeline, since ADR
    /// 0001 requires it to catch a resonance regardless of weighting.
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
    /// Time Averaging (ticket #7, CONTEXT.md "Time Averaging"): feeds
    /// Tracked Frequency's argmax and the display spectrum
    /// (AnalysisResult.magnitudes -- waterfall/RTA). SPL and the Anomaly
    /// Candidate detector both keep reading the raw, unblended `magnitudes`
    /// variable below, not this blended one.
    private var timeAveraging: TimeAveragingPreset = .fast
    private var timeAveragingBlender = TimeAveragingBlender()
    /// Anomaly Candidate detection (ticket #5) runs on the raw spectrum,
    /// never the Time-Averaging-blended one -- hardcoded to Fast
    /// (CONTEXT.md "Time Averaging"): the detector's own rolling sustain
    /// window is what governs its responsiveness, not this pipeline's
    /// user-selectable Tracked Frequency smoothing.
    private var anomalyDetector = AnomalyDetector()
    private var pollTask: Task<Void, Never>?

    init(config: AnalysisConfig, ringBuffer: AudioRingBuffer, weighting: Weighting = .default, timeAveraging: TimeAveragingPreset = .fast) {
        self.config = config
        self.ringBuffer = ringBuffer
        self.tracker = FrequencyTracker(config: config)
        self.rollingWindow = [Float](repeating: 0, count: config.windowSize)
        self.weighting = weighting
        self.timeAveraging = timeAveraging
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
                // If this persists (the underlying AVAudioEngine tap died --
                // see MicrophoneCaptureEngine's header comment), AudioPipeline
                // ViewModel's watchdog notices no hop has been delivered in a
                // while and restarts capture; this loop doesn't need to know
                // that's happening, it just keeps polling.
                try? await Task.sleep(nanoseconds: 5_000_000)
                continue
            }

            // Bug fix (root cause of both remaining reports -- "16384
            // still freezes" and inconsistent tracked frequency after
            // switching): this loop's success path had no suspension
            // point at all, only the failure path (the Task.sleep above).
            // When reads keep succeeding -- true whenever hopSize is small
            // enough that the ring buffer almost always has enough new
            // data already (confirmed via log instrumentation: a 1024-hop
            // pipeline logged 200+ hops in ~5s with no failed reads) --
            // this actor never naturally suspends, so it never yields its
            // executor to any OTHER queued work on the same actor. That
            // starves AudioPipelineViewModel's `await oldPipeline.stop()`
            // (queued on this same actor when a new FFT size is selected)
            // indefinitely: the old, small-hopSize pipeline keeps winning
            // the race for every new ring-buffer sample in tiny chunks,
            // so a newly-started, larger-hopSize pipeline can never
            // accumulate enough to complete a single read, and the
            // cancellation that's supposed to stop the old one never gets
            // a chance to run. An explicit yield every iteration (not just
            // on failure) guarantees cancellation is observed promptly
            // regardless of read-success rate.
            await Task.yield()
            guard !Task.isCancelled else { break }

            rollingWindow.removeFirst(config.hopSize)
            rollingWindow.append(contentsOf: hopBuffer)

            // Run the FFT once per hop and derive all three outputs from
            // it, rather than calling trackedFrequency(in:weighting:),
            // spectrum(in:), and weightedLevelDb(...) separately (each
            // would redo the same FFT).
            if let magnitudes = tracker.spectrum(in: rollingWindow) {
                // Direct mutating calls on the stored properties: possible
                // ever since TimeAveragingBlender/AnomalyDetector became
                // `nonisolated` (Swift 6 warning cleanup). While they were
                // implicitly @MainActor, calling them from this actor was
                // rejected ("cannot be passed 'inout' to implicitly 'async'
                // function call") and a copy-out/mutate/copy-back dance was
                // needed here -- the isolation fix dissolved it.
                let blendedForTracking = timeAveragingBlender.blend(magnitudes, preset: timeAveraging)
                if let frequency = tracker.trackedFrequency(fromMagnitudes: blendedForTracking, weighting: weighting) {
                    let splDb = tracker.weightedLevelDb(fromMagnitudes: magnitudes, weighting: weighting)
                    let levelDb = tracker.trackedFrequencyLevelDb(fromMagnitudes: blendedForTracking, weighting: weighting) ?? -Double.infinity
                    // Raw, unblended, unweighted magnitudes -- ADR 0001
                    // requires the true measured spectrum so a genuine
                    // low-frequency resonance isn't hidden by A-weighting's
                    // roll-off or smoothed away by Slow averaging.
                    let anomalyCandidates = anomalyDetector.process(magnitudes: magnitudes, config: config)
                    // What the waterfall/RTA actually display: Weighting
                    // and Time Averaging both applied, unlike magnitudes
                    // above (found by user report: these controls
                    // previously had no visible effect on either view).
                    let displaySpectrum = tracker.weightedSpectrum(fromMagnitudes: blendedForTracking, weighting: weighting)
                    continuation.yield(AnalysisResult(
                        trackedFrequencyHz: frequency, magnitudes: displaySpectrum, splDb: splDb,
                        trackedFrequencyLevelDb: levelDb, anomalyCandidates: anomalyCandidates,
                        fullScalePower: tracker.fullScalePower, timestamp: Date()
                    ))
                }
            }
        }
        continuation.finish()
    }
}
