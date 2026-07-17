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
//  AVAudioEngine's system default. Disconnect detection (ADR 0006) is
//  driven entirely by AudioDeviceEnumerator's Core Audio device-list
//  listener, not by AVAudioEngine's own configuration-change notification
//  -- the two would otherwise race to report the same event, and the HAL
//  device list is the more direct source of truth for "did this device
//  disappear."
//
//  Not unit-testable in this environment (no real audio hardware / mic
//  permission in CI/sandbox) -- see FreqTraceTests/FrequencyTrackerTests.swift
//  for the pure, hardware-independent analysis seam this feeds.
//
//  An `actor`, not @MainActor (bug fix -- user report: "the app freezes
//  when i change the built in mic to 44.1[kHz]", diagnosed via `sample` of
//  the frozen process): AVAudioEngine's start/stop/inputNode calls make
//  *synchronous mach IPC into coreaudiod* (the sample showed the main
//  thread parked in HALC_ProxyObject::GetPropertyData -> mach_msg2_trap,
//  under MicrophoneCaptureEngine.route(to:)). Those calls are normally
//  fast, but while the daemon is busy reconfiguring a device (a sample-
//  rate change in Audio MIDI Setup) -- or outright wedged, which this
//  machine's third-party HAL drivers have produced twice -- they block for
//  seconds to forever. On the main actor that froze the entire UI, and the
//  stall watchdog re-entered the same blocking call every 3s. As an actor,
//  the blocking happens on this actor's executor thread; the main actor
//  just awaits, and the UI stays responsive no matter how sick coreaudiod
//  is.
//

import AVFoundation
import CoreAudio

enum MicrophoneCaptureError: Error {
    case engineStartFailed(any Error)
    case deviceRoutingFailed(OSStatus)
}

actor MicrophoneCaptureEngine {
    /// var, not let (bug fix -- diagnosed via log instrumentation, user
    /// report: switching FFT size repeatedly eventually left capture
    /// silently dead -- AudioRingBuffer.write's writeIndex simply stopped
    /// advancing, forever, even though start() kept reporting success).
    /// Repeatedly stop()/installTap()/start()-ing the SAME persistent
    /// AVAudioEngine instance across several rapid reconfigurations (each
    /// FFT size switch tears capture down and restarts it) eventually left
    /// it no longer actually delivering tap buffers -- a known AVAudioEngine
    /// robustness issue with reusing one engine across many rapid
    /// reconfigurations, not specific to any particular FFT size (whichever
    /// switch happened to be the Nth rapid one in a row was the one that hit
    /// it). A brand-new engine constructed on every start() avoids
    /// accumulating whatever bad internal state repeated reconfiguration of
    /// one persistent instance was causing.
    private var engine = AVAudioEngine()
    private let ringBuffer: AudioRingBuffer
    private(set) var isRunning = false

    /// The input hardware's actual sample rate, populated once start()
    /// succeeds. May differ from AnalysisConfig.default's nominal 48 kHz --
    /// start(deviceID:) also returns it directly so the caller can
    /// reconfigure the analysis pipeline to match without a second await.
    private(set) var sampleRate: Double?

    /// Fired when the running engine invalidates itself (bug fix -- user
    /// report: capture never recovered after changing the mic's sample
    /// rate in Audio MIDI Setup; unified log showed "iounit configuration
    /// changed > stopping the engine" ~43ms after every start). AVAudioEngine
    /// *stops itself* when the device's IO configuration changes under it
    /// and posts AVAudioEngineConfigurationChange -- ignoring it (as this
    /// class used to; the header's device-list rationale only covers
    /// disconnects, which rate changes are not) left isRunning reporting a
    /// live engine whose tap was permanently dead, with recovery waiting on
    /// the stall watchdog's much slower timeout. The owner restarts capture
    /// promptly instead -- re-reading the (possibly changed) hardware rate
    /// on the way, which also re-triggers sample-rate adaptation.
    private var onConfigurationChange: (@Sendable () -> Void)?
    private var configChangeObserver: (any NSObjectProtocol)?

    init(ringBuffer: AudioRingBuffer) {
        self.ringBuffer = ringBuffer
    }

    func setConfigurationChangeHandler(_ handler: @escaping @Sendable () -> Void) {
        onConfigurationChange = handler
    }

    /// Starts capture, optionally routed at a specific Core Audio device
    /// (`nil` uses AVAudioEngine's system default input). Returns the
    /// hardware's actual sample rate.
    @discardableResult
    func start(deviceID: AudioDeviceID? = nil) throws -> Double {
        if isRunning, let sampleRate { return sampleRate }
        engine = AVAudioEngine()

        if let deviceID {
            try route(to: deviceID)
        }

        let input = engine.inputNode
        // inputFormat(forBus:), NOT outputFormat(forBus:) (bug fix -- user
        // report: "the waterfall/rta never starts right away" plus an
        // unrecoverable watchdog restart loop after changing the device's
        // sample rate, log-verified): the input node's *output* format is
        // the client-side format, and on a brand-new engine it can report a
        // stale rate (48kHz while the device nominal + inputFormat both say
        // 44.1kHz -- reproduced deterministically on this machine).
        // Installing the tap with that stale format makes AVAudioEngine
        // fail tap creation *silently* ("Failed to create tap, config
        // change pending!" -10877 in the log, no error thrown), so start()
        // reported success while zero buffers ever arrived -- the watchdog
        // then restarted into the exact same stale format forever.
        // inputFormat(forBus:) is the hardware-side format and tracks the
        // device's real rate.
        let format = input.inputFormat(forBus: 0)
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

        // Re-registered per engine instance (object: engine), torn down in
        // stop() -- a notification from a previous, discarded engine must
        // never trigger a restart of the current one.
        if let configChangeObserver {
            NotificationCenter.default.removeObserver(configChangeObserver)
        }
        let handler = onConfigurationChange
        configChangeObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: nil
        ) { _ in
            handler?()
        }

        isRunning = true
        return format.sampleRate
    }

    /// Whether the current AVAudioEngine instance is itself still running --
    /// distinct from `isRunning` (this class's intent state). AVAudioEngine
    /// posts AVAudioEngineConfigurationChange both when it *stops itself*
    /// (device rate changed under it -- needs a restart) and for benign
    /// graph reconfigurations it survives (observed ~100ms after every
    /// successful start on this machine, engine still delivering buffers)
    /// -- restarting on those tore capture down three times in a row on
    /// every single Start press. The owner checks this to tell the two
    /// apart.
    var engineIsRunning: Bool { engine.isRunning }

    func stop() {
        if let configChangeObserver {
            NotificationCenter.default.removeObserver(configChangeObserver)
            self.configChangeObserver = nil
        }
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
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
