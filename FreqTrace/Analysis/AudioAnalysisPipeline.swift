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
    let timestamp: Date
}

actor AudioAnalysisPipeline {
    private let config: AnalysisConfig
    private let ringBuffer: AudioRingBuffer
    private let tracker: FrequencyTracker

    private var rollingWindow: [Float]
    private var weighting: Weighting
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

            // Run the FFT once per hop and derive both outputs from it,
            // rather than calling trackedFrequency(in:weighting:) and
            // spectrum(in:) separately (each would redo the same FFT).
            if let magnitudes = tracker.spectrum(in: rollingWindow),
               let frequency = tracker.trackedFrequency(fromMagnitudes: magnitudes, weighting: weighting) {
                continuation.yield(AnalysisResult(trackedFrequencyHz: frequency, magnitudes: magnitudes, timestamp: Date()))
            }
        }
        continuation.finish()
    }
}
