//
//  MicrophoneCaptureEngine.swift
//  FreqTrace
//
//  The capture stage of the shared pipeline (ADR 0002): taps an input
//  device via AVAudioEngine and copies samples into an AudioRingBuffer. The
//  tap callback runs on the real-time audio thread, so it does the absolute
//  minimum: a pointer copy into the ring buffer, no allocation, no locking,
//  no FFT. Everything else (FFT, tracking) happens off-thread in
//  AudioAnalysisPipeline.
//
//  Device selection (ticket #4): start(deviceID:) optionally routes the
//  underlying input audio unit at a specific Core Audio device via
//  kAudioOutputUnitProperty_CurrentDevice before starting; nil uses
//  AVAudioEngine's system default. onConfigurationChange fires when the
//  engine's I/O configuration changes (e.g. the active device disappearing)
//  so AudioPipelineViewModel can drive CaptureConnectionState (ADR 0006).
//
//  Not unit-testable in this environment (no real audio hardware / mic
//  permission in CI/sandbox) -- see FreqTraceTests/FrequencyTrackerTests.swift
//  for the pure, hardware-independent analysis seam this feeds.
//

import AVFoundation
import CoreAudio

enum MicrophoneCaptureError: Error {
    case engineStartFailed(any Error)
    case deviceRoutingFailed(OSStatus)
}

@MainActor
final class MicrophoneCaptureEngine {
    private let engine = AVAudioEngine()
    private let ringBuffer: AudioRingBuffer
    private(set) var isRunning = false
    private var configurationChangeObserver: NSObjectProtocol?

    /// The input hardware's actual sample rate, populated once start()
    /// succeeds. May differ from AnalysisConfig.default's nominal 48 kHz --
    /// callers should reconfigure the analysis pipeline to match.
    private(set) var sampleRate: Double?

    /// Fires when AVAudioEngine reports its I/O configuration changed --
    /// notably, the active device being unplugged/disconnected.
    var onConfigurationChange: (() -> Void)?

    init(ringBuffer: AudioRingBuffer) {
        self.ringBuffer = ringBuffer
    }

    /// Starts capture, optionally routed at a specific Core Audio device.
    /// `nil` uses AVAudioEngine's system default input.
    func start(deviceID: AudioDeviceID? = nil) throws {
        guard !isRunning else { return }

        if let deviceID {
            try route(to: deviceID)
        }

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        sampleRate = format.sampleRate

        let ringBuffer = self.ringBuffer
        input.installTap(onBus: 0, bufferSize: 2048, format: format) { buffer, _ in
            // Real-time audio thread: minimal work only.
            guard let channelData = buffer.floatChannelData else { return }
            ringBuffer.write(channelData[0], count: Int(buffer.frameLength))
        }

        configurationChangeObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            self?.onConfigurationChange?()
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
        if let configurationChangeObserver {
            NotificationCenter.default.removeObserver(configurationChangeObserver)
            self.configurationChangeObserver = nil
        }
        isRunning = false
    }

    private func route(to deviceID: AudioDeviceID) throws {
        guard let audioUnit = engine.inputNode.audioUnit else { return }
        var mutableDeviceID = deviceID
        let status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &mutableDeviceID,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        guard status == noErr else {
            throw MicrophoneCaptureError.deviceRoutingFailed(status)
        }
    }
}
