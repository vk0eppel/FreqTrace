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

import CoreAudio
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
    /// The level (dB) of the tracked-frequency bin itself (ticket #12,
    /// CONTEXT.md "Peak" -- "Tracked Frequency level"). See
    /// FrequencyTracker.trackedFrequencyLevelDb(fromMagnitudes:weighting:).
    private(set) var trackedFrequencyLevelDb: Double?
    /// Top 2-3 Anomaly Candidates (ticket #5, ADR 0001, CONTEXT.md
    /// "Anomaly Candidate"), ranked by severity -- empty (not nil) when
    /// nothing is currently flagged, so the Measured Data row can show
    /// nothing rather than a placeholder.
    private(set) var anomalyCandidates: [AnomalyCandidate] = []
    /// The SPL meter's manual numeric offset (CONTEXT.md "SPL Offset"),
    /// default 0 -- no real calibration in v1 (ADR 0003); this is a bare
    /// user-entered value, not derived from anything.
    var splOffsetDb: Double = 0
    /// Arbitrary but generous headroom for the offset field -- no
    /// calibration workflow exists yet to derive a "correct" range from.
    static let splOffsetRangeDb: ClosedRange<Double> = -60...60

    /// Input devices currently exposing at least one input stream
    /// (CONTEXT.md "Input Device"), refreshed on start() and whenever Core
    /// Audio reports the device list changed.
    private(set) var availableInputDevices: [AudioDevice] = []
    /// The Input Device picker's current selection -- see
    /// DeviceConnectionState for whether it's actually running.
    private(set) var selectedInputDeviceID: String?
    /// Drives the disconnected indicator (ticket #4, ADR 0006): the active
    /// device disappearing transitions this to `.disconnected` rather than
    /// silently reassigning to a different device.
    private(set) var connectionState: DeviceConnectionState = .stopped

    var isCaptureActive: Bool {
        if case .running = connectionState { return true }
        return false
    }

    /// Gates all three published-from-one-hop properties
    /// (trackedFrequencyHz/latestMagnitudes/splDb) together as a single
    /// AnalysisResult, rather than three separate gates -- they always
    /// update in lockstep from one hop, so one gate is simpler and still
    /// gives every consumer (waterfall, Measured Data row) the same
    /// instant-catch-up snapshot.
    private var freezeGate = FreezeGate<AnalysisResult>()

    /// Freeze (CONTEXT.md "Freeze"): pauses on-screen updates only -- the
    /// capture/FFT/tracking pipeline underneath keeps running and its
    /// results keep flowing into `freezeGate`. Distinct from
    /// `connectionState`, which tracks the pipeline itself and is untouched
    /// by freezing.
    var isFrozen: Bool { freezeGate.isFrozen }

    /// Toggles Freeze. Unfreezing immediately applies the most recently
    /// held result, if the pipeline produced one while frozen -- the
    /// "instant catch-up" the AC requires, never a queued replay.
    func toggleFreeze() {
        if freezeGate.isFrozen {
            if let result = freezeGate.unfreeze() {
                apply(result)
            }
        } else {
            freezeGate.freeze()
        }
    }

    /// Peak (ticket #12, CONTEXT.md "Peak"): one tracker shared by SPL, the
    /// Tracked Frequency level, and each RTA bar (keyed by bar index) so a
    /// single manual reset clears all of them together, per the AC. Never
    /// applies to the waterfall -- nothing here is read by WaterfallZoneView's
    /// waterfall branch.
    enum PeakKey: Hashable {
        case spl
        case trackedFrequencyLevel
        case rtaBar(Int)
    }
    private var peakTracker = PeakHoldTracker<PeakKey>()

    var splPeakDb: Float? { peakTracker.peak(for: .spl) }
    var trackedFrequencyLevelPeakDb: Float? { peakTracker.peak(for: .trackedFrequencyLevel) }
    func peakForRTABar(_ index: Int) -> Float? { peakTracker.peak(for: .rtaBar(index)) }

    /// The manual reset (AC: "A manual reset control clears all held
    /// peaks").
    func resetPeaks() {
        peakTracker.reset()
    }

    var weighting: Weighting = .default {
        didSet {
            guard weighting != oldValue else { return }
            let pipeline = pipeline
            Task { await pipeline.setWeighting(weighting) }
        }
    }

    /// Time Averaging (ticket #7, CONTEXT.md "Time Averaging"): Fast/Slow
    /// preset controlling how quickly Tracked Frequency responds. Only this
    /// ticket's scope -- other views may later expose their own Fast/Slow
    /// choice (CONTEXT.md), but that's not implemented here.
    var timeAveraging: TimeAveragingPreset = .fast {
        didSet {
            guard timeAveraging != oldValue else { return }
            let pipeline = pipeline
            Task { await pipeline.setTimeAveraging(timeAveraging) }
        }
    }

    /// FFT configuration in effect -- the waterfall needs this to map FFT
    /// bins to frequencies (see FrequencyAxis).
    let config: AnalysisConfig

    private let ringBuffer: AudioRingBuffer
    private let pipeline: AudioAnalysisPipeline
    private let captureEngine: MicrophoneCaptureEngine
    private let deviceEnumerator = AudioDeviceEnumerator(scope: .input)
    private var streamTask: Task<Void, Never>?

    /// Persists the tech's last explicit Input Device choice across
    /// launches (CONTEXT.md "Input Device").
    private static let persistedDeviceIDDefaultsKey = "FreqTrace.selectedInputDeviceID"

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

    /// Starts capturing and streaming analysis updates. Resolves which
    /// input device to use (AudioDeviceSelector) from the persisted last
    /// explicit choice, falling back to the system default. Safe to call
    /// multiple times; a no-op once already running.
    func start() {
        guard !isCaptureActive else { return }

        deviceEnumerator.onChange = { [weak self] in self?.refreshAvailableDevices() }
        deviceEnumerator.startObserving()
        refreshAvailableDevices()

        guard let deviceID = AudioDeviceSelector.resolve(
            availableDevices: availableInputDevices,
            persistedDeviceID: UserDefaults.standard.string(forKey: Self.persistedDeviceIDDefaultsKey),
            systemDefaultDeviceID: deviceEnumerator.systemDefaultDeviceID()
        ) else {
            // No input devices available at all -- stay stopped.
            return
        }
        startCapture(deviceID: deviceID, persistChoice: false)
    }

    /// Explicit device selection from the Input Device picker (or a
    /// reconnect from the disconnected state): always (re)starts capture at
    /// the chosen device and persists it as the new last explicit choice.
    func selectInputDevice(id: String) {
        startCapture(deviceID: id, persistChoice: true)
    }

    func stop() {
        haltCapture()
        connectionState = connectionState.stopping()
    }

    /// Resumes capture after Stop (CONTEXT.md "Stop"): re-initializes
    /// capture against the currently-selected Input Device, the same
    /// resolution `startCapture` already performs -- not a fresh device
    /// pick, so the choice isn't re-persisted. Falls back to `start()`'s
    /// system-default/persisted-choice resolution if no device is known yet
    /// (e.g. Stop was hit before capture ever started successfully). A
    /// no-op if capture is already active.
    func resumeCapture() {
        guard !isCaptureActive else { return }
        guard let deviceID = selectedInputDeviceID else {
            start()
            return
        }
        startCapture(deviceID: deviceID, persistChoice: false)
    }

    /// Attempts to (re)start capture at `deviceID`. On success, updates
    /// `selectedInputDeviceID`/`connectionState` and persists the choice if
    /// requested. On failure, leaves neither stale -- resets to `.stopped`
    /// rather than reporting a device as selected/running that never
    /// actually started (found by code review on #4).
    private func startCapture(deviceID: String, persistChoice: Bool) {
        haltCapture()

        let coreAudioDeviceID = deviceEnumerator.deviceID(forUID: deviceID)
        do {
            try captureEngine.start(deviceID: coreAudioDeviceID)
        } catch {
            // No hardware/permission in this environment (or denied by the
            // user), or the device vanished between resolving it and
            // starting -- readouts stay at their placeholder state.
            connectionState = .stopped
            return
        }

        if persistChoice {
            UserDefaults.standard.set(deviceID, forKey: Self.persistedDeviceIDDefaultsKey)
        }
        selectedInputDeviceID = deviceID
        connectionState = connectionState.selecting(deviceID: deviceID)

        let pipeline = pipeline
        streamTask = Task { [weak self] in
            let stream = await pipeline.start()
            for await result in stream {
                guard !Task.isCancelled else { break }
                self?.receive(result)
            }
        }
    }

    /// Routes one hop's result through `freezeGate`: published immediately
    /// when not frozen, held silently when frozen (CONTEXT.md "Freeze") --
    /// the pipeline itself never knows or cares whether the display is
    /// frozen.
    private func receive(_ result: AnalysisResult) {
        guard let toPublish = freezeGate.receive(result) else { return }
        apply(toPublish)
    }

    /// Applies one AnalysisResult to the three published properties the
    /// UI reads directly.
    private func apply(_ result: AnalysisResult) {
        trackedFrequencyHz = result.trackedFrequencyHz
        latestMagnitudes = result.magnitudes
        splDb = result.splDb
        trackedFrequencyLevelDb = result.trackedFrequencyLevelDb
        anomalyCandidates = result.anomalyCandidates
        if result.splDb.isFinite {
            peakTracker.update(Float(result.splDb), for: .spl)
        }
        if result.trackedFrequencyLevelDb.isFinite {
            peakTracker.update(Float(result.trackedFrequencyLevelDb), for: .trackedFrequencyLevel)
        }
        // Computed here (every hop, regardless of whether RTA is the
        // currently-visible view) rather than from RTAView's onChange, so
        // RTA bar peaks accumulate continuously like SPL/Tracked Frequency
        // level's peaks -- Peak hold is supposed to be indefinite
        // (CONTEXT.md "Peak"), not paused whenever the tech is looking at
        // the waterfall instead (found by code review).
        let bars = RTABinning.bars(magnitudes: result.magnitudes, config: config)
        for (index, value) in bars.enumerated() {
            peakTracker.update(value, for: .rtaBar(index))
        }
    }

    /// Reacts to Core Audio reporting the device list changed -- the single
    /// source of truth for both directions of ADR 0006's disconnect
    /// behavior: the active device disappearing (-> `.disconnected`, engine
    /// stopped) and a previously-disconnected device reappearing (passive
    /// reconnect -> resumes capture, distinct from the tech manually
    /// picking a device via selectInputDevice).
    private func refreshAvailableDevices() {
        availableInputDevices = deviceEnumerator.availableDevices()
        let availableIDs = Set(availableInputDevices.map(\.id))
        let nextState = connectionState.handlingDeviceListChange(availableDeviceIDs: availableIDs)

        switch (connectionState, nextState) {
        case (.running, .disconnected):
            haltCapture()
            connectionState = nextState
        case (.disconnected, .running(let deviceID)):
            startCapture(deviceID: deviceID, persistChoice: false)
        default:
            connectionState = nextState
        }
    }

    /// Stops the underlying pipeline. If the display is frozen (CONTEXT.md
    /// "Freeze"), the on-screen snapshot is left exactly as-is rather than
    /// force-cleared to a placeholder -- Stop (or a disconnect) happening
    /// underneath a frozen display must not itself count as an "on-screen
    /// update" (found by code review: this previously cleared the three
    /// published properties directly, bypassing `freezeGate`, so Stop while
    /// frozen silently blanked what was supposed to be a static snapshot).
    private func haltCapture() {
        streamTask?.cancel()
        streamTask = nil
        captureEngine.stop()
        guard !isFrozen else { return }
        trackedFrequencyHz = nil
        latestMagnitudes = []
        splDb = nil
        trackedFrequencyLevelDb = nil
        anomalyCandidates = []
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
        guard let splDb, splDb.isFinite else { return "\u{2014}" }
        return "\(Int((splDb + splOffsetDb).rounded())) dB"
    }

    /// "PEAK -12dB"-style secondary readout (ticket #12, CONTEXT.md
    /// "Peak"), or nil before any peak has been recorded (no placeholder --
    /// this is an optional overlay, not a hero value).
    var formattedSPLPeak: String? {
        guard let splPeakDb, splPeakDb.isFinite else { return nil }
        return "PEAK \(Int((splPeakDb + Float(splOffsetDb)).rounded())) dB"
    }

    var formattedTrackedFrequencyLevelPeak: String? {
        guard let trackedFrequencyLevelPeakDb, trackedFrequencyLevelPeakDb.isFinite else { return nil }
        return "PEAK \(Int(trackedFrequencyLevelPeakDb.rounded())) dB"
    }
}
