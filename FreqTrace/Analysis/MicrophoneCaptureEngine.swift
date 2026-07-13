//
//  MicrophoneCaptureEngine.swift
//  FreqTrace
//
//  The capture stage of the shared pipeline (ADR 0002): taps the system
//  default input device via AVAudioEngine and copies samples into an
//  AudioRingBuffer. The tap callback runs on the real-time audio thread, so
//  it does the absolute minimum: a pointer copy into the ring buffer, no
//  allocation, no locking, no FFT. Everything else (FFT, tracking) happens
//  off-thread in AudioAnalysisPipeline.
//
//  Explicit input device selection is ticket #4 -- this always uses
//  AVAudioEngine's system default input.
//
//  Not unit-testable in this environment (no real audio hardware / mic
//  permission in CI/sandbox) -- see FreqTraceTests/FrequencyTrackerTests.swift
//  for the pure, hardware-independent analysis seam this feeds.
//

import AVFoundation

enum MicrophoneCaptureError: Error {
    case engineStartFailed(any Error)
}

@MainActor
final class MicrophoneCaptureEngine {
    private let engine = AVAudioEngine()
    private let ringBuffer: AudioRingBuffer
    private(set) var isRunning = false

    /// The input hardware's actual sample rate, populated once start()
    /// succeeds. May differ from AnalysisConfig.default's nominal 48 kHz --
    /// callers should reconfigure the analysis pipeline to match.
    private(set) var sampleRate: Double?

    init(ringBuffer: AudioRingBuffer) {
        self.ringBuffer = ringBuffer
    }

    func start() throws {
        guard !isRunning else { return }

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        sampleRate = format.sampleRate

        let ringBuffer = self.ringBuffer
        input.installTap(onBus: 0, bufferSize: 2048, format: format) { buffer, _ in
            // Real-time audio thread: minimal work only.
            guard let channelData = buffer.floatChannelData else { return }
            ringBuffer.write(channelData[0], count: Int(buffer.frameLength))
        }

        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw MicrophoneCaptureError.engineStartFailed(error)
        }

        isRunning = true
    }

    func stop() {
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
    }
}
