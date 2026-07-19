//
//  SignalGeneratorEngine.swift
//  FreqTrace
//
//  AVAudioEngine glue for the Signal Generator (issue #9). Deliberately its
//  own AVAudioEngine instance, separate from the capture pipeline's (ADR
//  0002) -- this is playback/output, so it has no dependency on capture
//  being active and keeps running through a future Freeze/Stop on the
//  analysis side (see CONTEXT.md "Signal Generator On/Off").
//
//  Output Device routing (ticket #14, CONTEXT.md "Output Device"): routes
//  the underlying output audio unit at a specific Core Audio device via
//  kAudioOutputUnitProperty_CurrentDevice, mirroring MicrophoneCaptureEngine's
//  input-side routing. Disconnect handling reuses DeviceConnectionState, the
//  same pure state machine backing the Input Device's disconnected
//  indicator (ADR 0006): the selected output device disappearing stops the
//  generator and shows an explicit disconnected state, never a silent
//  fallback to another output. Picking a device while the generator is off
//  only records the selection -- it deliberately does NOT auto-start
//  playback, since that would defeat the point of the explicit On/Off
//  switch (CONTEXT.md "Signal Generator On/Off").
//
//  Not unit-tested directly -- it drives real audio hardware, which this
//  sandboxed environment cannot exercise. The pure math it wraps
//  (SignalGeneratorCore, SineOscillator, noise generators, Decibels,
//  ISOBand) is fully covered by SignalGeneratorCoreTests / ISOBandTests, and
//  device selection/disconnect logic by InputDeviceTests.swift's
//  AudioDeviceSelector/DeviceConnectionState coverage (shared with Input
//  Device, not duplicated here). Actually hearing the tone/noise, and the
//  device routing/disconnect behavior, need manual verification on real
//  hardware.
//

import AVFoundation
import CoreAudio
import Observation

enum SignalGeneratorError: Error {
    case deviceRoutingFailed(OSStatus)
    case deviceNotFound
}

@MainActor
@Observable
final class SignalGeneratorEngine {
    /// Signal Generator Level's editable range (CONTEXT.md: a numeric dB
    /// box, e.g. "-66dB"). -96dB is a conventional digital noise floor
    /// (16-bit dynamic range); 0dB is unity/full-scale, the loudest the
    /// generator can output. Not specified by issue #9 -- flagged in the
    /// report as a decision worth confirming for the domain docs.
    static let levelRangeDB: ClosedRange<Double> = -96...0
    static let defaultLevelDB: Double = -66

    var waveform: Waveform = .sine {
        didSet { syncRenderState() }
    }

    var levelDB: Double = SignalGeneratorEngine.defaultLevelDB {
        didSet { syncRenderState() }
    }

    /// The sine waveform's frequency (ticket #14, CONTEXT.md "ISO Band"):
    /// set via the ISO Band step buttons or the free numeric Hz field.
    /// Meaningless for pink/white noise -- the UI disables/hides the
    /// control for those waveforms, but the value is preserved underneath
    /// so switching back to sine restores the last frequency.
    var sineFrequencyHz: Double = SignalGeneratorCore<SystemRandomNumberGenerator>.defaultSineFrequency {
        didSet { syncRenderState() }
    }

    /// The free Hz field's editable range -- matches the ISO Band series'
    /// own low/high bounds, so a hand-typed value can't exceed what the
    /// step buttons could ever reach.
    static let sineFrequencyRangeHz: ClosedRange<Double> = ISOBand.centers.first!...ISOBand.centers.last!

    /// ISO Band step buttons (ticket #14, CONTEXT.md "ISO Band"): jump to
    /// the next/previous standard 1/3-octave center from the current
    /// frequency (which may itself be off-grid, from the free Hz field).
    func stepSineFrequencyUp() {
        sineFrequencyHz = ISOBand.stepUp(from: sineFrequencyHz)
    }

    func stepSineFrequencyDown() {
        sineFrequencyHz = ISOBand.stepDown(from: sineFrequencyHz)
    }

    private(set) var isOn: Bool = false
    private(set) var startupError: String?

    /// Output devices currently exposing at least one output stream
    /// (CONTEXT.md "Output Device"), refreshed at init and whenever Core
    /// Audio reports the device list changed. Independent of the app's
    /// Input Device list (AudioPipelineViewModel.availableInputDevices) --
    /// its own AudioDeviceEnumerator instance, own scope.
    private(set) var availableOutputDevices: [AudioDevice] = []
    /// The Output Device picker's current selection.
    private(set) var selectedOutputDeviceID: String?
    /// Drives the disconnected indicator (ticket #14, ADR 0006): the active
    /// output device disappearing transitions this to `.disconnected`
    /// rather than silently reassigning to a different device.
    private(set) var connectionState: DeviceConnectionState = .stopped

    private let engine = AVAudioEngine()
    private let renderState: SignalGeneratorRenderState
    private let deviceEnumerator = AudioDeviceEnumerator(scope: .output)

    /// Persists the tech's last explicit Output Device choice across
    /// launches, same shape as Input Device's persisted choice.
    private static let persistedDeviceIDDefaultsKey = "FreqTrace.selectedOutputDeviceID"

    init() {
        let sampleRate = engine.outputNode.outputFormat(forBus: 0).sampleRate
        let effectiveSampleRate = sampleRate > 0 ? sampleRate : 48000
        renderState = SignalGeneratorRenderState(sampleRate: effectiveSampleRate)

        let format = AVAudioFormat(standardFormatWithSampleRate: effectiveSampleRate, channels: 1)!
        // @Sendable pins the render block as nonisolated: it's formed here in
        // SignalGeneratorEngine's @MainActor context, so without it the closure
        // is inferred @MainActor and CoreAudio calling it on the real-time audio
        // thread trips Swift 6's runtime executor check (dispatch_assert_queue),
        // crashing the app the moment the generator is switched on.
        let sourceNode = AVAudioSourceNode(format: format) { @Sendable [renderState] isSilence, timestamp, frameCount, audioBufferList in
            renderState.render(
                isSilence: isSilence,
                timestamp: timestamp,
                frameCount: frameCount,
                audioBufferList: audioBufferList
            )
        }

        engine.attach(sourceNode)
        engine.connect(sourceNode, to: engine.mainMixerNode, format: format)
        engine.prepare()

        syncRenderState()

        deviceEnumerator.onChange = { [weak self] in self?.refreshAvailableOutputDevices() }
        deviceEnumerator.startObserving()
        refreshAvailableOutputDevices()
        selectedOutputDeviceID = AudioDeviceSelector.resolve(
            availableDevices: availableOutputDevices,
            persistedDeviceID: UserDefaults.standard.string(forKey: Self.persistedDeviceIDDefaultsKey),
            systemDefaultDeviceID: deviceEnumerator.systemDefaultDeviceID()
        )
    }

    /// Explicit on/off per CONTEXT.md "Signal Generator On/Off" -- a real
    /// switch that actually starts/stops audible output, never a passive
    /// status indicator.
    func setOn(_ on: Bool) {
        guard on != isOn else { return }
        guard on else {
            haltEngine()
            connectionState = connectionState.stopping()
            return
        }
        startEngine(deviceID: selectedOutputDeviceID)
    }

    /// Explicit device selection from the Output Device picker (or a
    /// reconnect from the disconnected state). Only re-routes playback if
    /// the generator is already on -- selecting a device while off must not
    /// silently start audible output (CONTEXT.md "Signal Generator On/Off").
    func selectOutputDevice(id: String) {
        UserDefaults.standard.set(id, forKey: Self.persistedDeviceIDDefaultsKey)
        selectedOutputDeviceID = id
        if isOn {
            startEngine(deviceID: id)
        }
    }

    /// Attempts to (re)start playback, optionally routed at `deviceID`. On
    /// failure, leaves neither stale -- resets to `.stopped` rather than
    /// reporting a device as selected/running that never actually started
    /// (mirrors the fix ticket #4's code review made to the equivalent
    /// input-side path).
    private func startEngine(deviceID: String?) {
        haltEngine()
        do {
            if let deviceID {
                // A specific device was requested -- if Core Audio can no
                // longer resolve it (vanished between selection and start),
                // fail outright rather than silently starting on whatever
                // AVAudioEngine's default output happens to be (found by
                // code review: this previously fell through to the default
                // output while still reporting `.running(deviceID)`,
                // exactly the silent fallback ADR 0006 forbids).
                guard let coreAudioDeviceID = deviceEnumerator.deviceID(forUID: deviceID) else {
                    throw SignalGeneratorError.deviceNotFound
                }
                try route(to: coreAudioDeviceID)
            }
            try engine.start()
            isOn = true
            startupError = nil
            connectionState = deviceID.map { connectionState.selecting(deviceID: $0) } ?? .stopped
        } catch {
            isOn = false
            startupError = error.localizedDescription
            connectionState = .stopped
        }
    }

    private func haltEngine() {
        guard isOn else { return }
        engine.stop()
        isOn = false
    }

    /// Reacts to Core Audio reporting the output device list changed --
    /// the disconnect half of ADR 0006 applied to Output Device: the active
    /// device disappearing stops the generator and shows disconnected
    /// (never a silent fallback). Unlike Input Device, a reappearing device
    /// deliberately does NOT auto-resume playback (found by code review):
    /// Input's passive reconnect only resumes silent analysis, but here it
    /// would resume *audible* output with no tech action -- exactly the
    /// "a test tone could suddenly start playing... audible to an
    /// audience" risk ADR 0006 itself warns about. The tech must explicitly
    /// turn the generator back on.
    private func refreshAvailableOutputDevices() {
        availableOutputDevices = deviceEnumerator.availableDevices()
        let availableIDs = Set(availableOutputDevices.map(\.id))
        let nextState = connectionState.handlingDeviceListChange(availableDeviceIDs: availableIDs)

        switch (connectionState, nextState) {
        case (.running, .disconnected):
            haltEngine()
            connectionState = nextState
        case (.disconnected, .running):
            connectionState = .stopped
        default:
            connectionState = nextState
        }
    }

    private func route(to deviceID: AudioDeviceID) throws {
        guard let audioUnit = engine.outputNode.audioUnit else { return }
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
            throw SignalGeneratorError.deviceRoutingFailed(status)
        }
    }

    private func syncRenderState() {
        let amplitude = Decibels.linearAmplitude(fromDecibels: levelDB)
        renderState.update(waveform: waveform, amplitude: amplitude, sineFrequency: sineFrequencyHz)
    }
}
