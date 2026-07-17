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
import os

private let diagLog = Logger(subsystem: "com.freqtrace.diagnostic", category: "viewmodel")

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
    /// Reference power a full-scale signal produces (FrequencyTracker.
    /// fullScalePower) -- the waterfall/RTA divide raw magnitudes by this
    /// before applying MagnitudeScaling's dB floor/ceiling. Defaults to 1
    /// only until the first hop arrives; harmless since latestMagnitudes
    /// is empty until then too.
    private(set) var fullScalePower: Float = 1
    /// Cached per-hop RTA bar values (perf fix, user request "reduce CPU
    /// load"): RTABinning.bars(...) was independently recomputed by three
    /// separate call sites every hop -- this class's own peak-tracking scan
    /// below, RTAView's Canvas render, and WaterfallZoneView's hover
    /// overlay -- even though all three want the exact same array for the
    /// exact same hop. Computed once in apply(); RTAView and the hover
    /// overlay now just read this instead. Kept in sync with
    /// bandingResolution's didSet (recomputed immediately from the last
    /// known magnitudes, not just on the next hop) so a resolution switch
    /// never leaves this array's length mismatched against
    /// RTABinning.bandEdges(barsPerOctave:)'s current bar count.
    private(set) var latestRTABars: [Float] = []
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
    /// The selected device's hardware operating format (user request:
    /// "indicate sample rate and bit depth near the input device"), shown
    /// as a dimmed sub-caption in the Input Device plate. Refreshed
    /// whenever the selection lands (performStartCapture) and whenever the
    /// device list changes; a mid-capture rate change also refreshes it,
    /// since recovery goes back through performStartCapture.
    private(set) var selectedInputDeviceFormat: AudioDeviceFormat?
    /// Drives the disconnected indicator (ticket #4, ADR 0006): the active
    /// device disappearing transitions this to `.disconnected` rather than
    /// silently reassigning to a different device.
    private(set) var connectionState: DeviceConnectionState = .stopped

    /// Drives the "CAPTURE UNAVAILABLE" indicator (closed the last piece of
    /// CLAUDE.md's former known gap: the watchdog's exponential backoff
    /// against a wedged coreaudiod used to look like a silently frozen app).
    /// True once a stall has survived the watchdog's first restart attempt
    /// (~9s in) -- one transient stall that the first restart cures never
    /// shows it, since flashing a scary indicator for a self-healing blip
    /// is noise. Cleared by the next real hop (receive(_:)) or by Stop.
    /// Only meaningful while `isCaptureActive`; the UI gates on both.
    private(set) var isCaptureStalled = false

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

    /// Octave-banding resolution (user request: selectable "bars per
    /// octave," 1/1 through 1/48 -- see RTABandingResolution), shared
    /// between RTA and the waterfall (confirmed with user: one setting,
    /// not independent per view) rather than duplicated per view. Lives
    /// here, not on RTAView, because RTA bar peaks are computed every hop
    /// regardless of which view is visible (see `apply(_:)` below), so
    /// that continuous peak computation and RTAView's own live rendering
    /// must agree on the same bar count; the waterfall reads it too, to
    /// pre-bin its magnitudes before writing to the GPU texture
    /// (RTABinning.steppedMagnitudes, called from MetalWaterfallView).
    /// Changing it clears only the RTA bars' held peaks -- a bar index no
    /// longer means the same frequency once the bar count changes, so an
    /// old peak at that index would be stale data on the new layout, not a
    /// real held peak for it.
    var bandingResolution: RTABandingResolution = .oneOverTwelve {
        didSet {
            guard bandingResolution != oldValue else { return }
            peakTracker.removeAll { key in
                if case .rtaBar = key { return true }
                return false
            }
            // Recomputed immediately, not left for the next hop -- latestRTABars
            // must never sit at the old bar count while RTAView/the hover
            // overlay already query bandEdges(barsPerOctave:) at the new one
            // (out-of-bounds risk if the two length-mismatch).
            latestRTABars = RTABinning.bars(magnitudes: latestMagnitudes, config: config, barsPerOctave: bandingResolution.rawValue, fullScalePower: fullScalePower)
        }
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

    /// Selectable FFT window size (user request, FFTWindowSize.swift): not
    /// a lightweight hot-swap like weighting/timeAveraging above -- window
    /// size drives buffer sizing baked into init (FrequencyTracker's vDSP
    /// FFT setup, AudioAnalysisPipeline's rollingWindow, WaterfallRenderer's
    /// GPU texture dimensions), none of which have a resize path. Changing
    /// this tears down and rebuilds the pipeline (and, via WaterfallZoneView
    /// reacting to `config` changing, the waterfall renderer), restarting
    /// capture if it was running -- closer to Stop->Start than a simple
    /// property mutation, acceptable since this is an infrequent, deliberate
    /// setting change, not a per-frame concern.
    var fftWindowSize: FFTWindowSize = .default {
        didSet {
            guard fftWindowSize != oldValue else { return }
            applyFFTWindowSizeChange()
        }
    }

    /// Serializes every operation that touches the capture engine or swaps
    /// the analysis pipeline -- capture starts/stops, FFT size switches,
    /// sample-rate adaptation -- so at most one is ever in flight. Two
    /// hard-won reasons, both from field bugs: (1) a pipeline rebuild must
    /// await the old pipeline's stop() before the new one reads the shared
    /// ring buffer (single-consumer invariant -- overlapping FFT switches
    /// once leaked a never-stopped pipeline that corrupted it, freezing
    /// every readout), and (2) engine start/stop make synchronous mach IPC
    /// into coreaudiod that can block for seconds when the daemon is busy
    /// or wedged (user report: "the app freezes when i change the built in
    /// mic to 44.1") -- so they must happen inside these queued operations,
    /// where the main actor merely awaits, never on it directly.
    private var pendingCaptureOperation: Task<Void, Never>?

    private func enqueueCaptureOperation(_ operation: @escaping @MainActor () async -> Void) {
        let previous = pendingCaptureOperation
        pendingCaptureOperation = Task {
            await previous?.value
            await operation()
        }
    }

    /// Bumped by every user-intent stop (Stop button, device disconnect).
    /// Queued capture *starts* snapshot it when enqueued and abort if it
    /// changed by the time they run or across their awaits -- otherwise a
    /// watchdog restart queued just before the tech pressed Stop would
    /// resurrect capture right after they stopped it.
    private var stopGeneration = 0

    private func applyFFTWindowSizeChange() {
        let requestedSize = fftWindowSize
        let generation = stopGeneration
        enqueueCaptureOperation { [weak self] in
            guard let self else { return }
            guard self.fftWindowSize == requestedSize else {
                // Superseded by an even newer selection while this one was
                // queued -- let that one own the final state; nothing here
                // has touched the pipeline yet, so there's nothing to undo.
                return
            }

            let wasRunning = self.isCaptureActive
            let deviceID = self.selectedInputDeviceID
            let oldPipeline = self.pipeline
            self.haltPublishing()
            await self.captureEngine.stop()
            // The old pipeline must have actually stopped reading the
            // single-consumer ring buffer before a new one starts -- see
            // pendingCaptureOperation's doc comment for the corruption
            // this once caused.
            await oldPipeline.stop()

            self.config = requestedSize.config(sampleRate: self.config.sampleRate)
            // A brand-new AudioAnalysisPipeline also means a brand-new
            // internal AnomalyDetector/TimeAveragingBlender, so stale
            // tracking state from the old window size can't leak into the
            // new one. peakTracker's held peaks are deliberately left
            // untouched (Peak is "indefinite hold" per CONTEXT.md; only
            // PEAK RESET should clear it -- window size doesn't invalidate
            // what's still a valid highest-level-seen for a given
            // frequency band).
            self.pipeline = AudioAnalysisPipeline(config: self.config, ringBuffer: self.ringBuffer, weighting: self.weighting, timeAveraging: self.timeAveraging)
            guard wasRunning, self.stopGeneration == generation else { return }
            guard let deviceID = deviceID ?? self.resolveDefaultDeviceID() else { return }
            await self.performStartCapture(deviceID: deviceID, persistChoice: false, generation: generation)
        }
    }

    /// FFT configuration in effect -- the waterfall needs this to map FFT
    /// bins to frequencies (see FrequencyAxis). var, not let (was let until
    /// FFT size became selectable) -- applyFFTWindowSizeChange() below
    /// reassigns it, but external readers (WaterfallZoneView, RTAView, the
    /// hover overlay) only ever read it, so it stays private(set).
    private(set) var config: AnalysisConfig

    private let ringBuffer: AudioRingBuffer
    /// var, not let (was let until FFT size became selectable) --
    /// applyFFTWindowSizeChange() below rebuilds this from scratch, since
    /// FrequencyTracker's vDSP FFT setup and AudioAnalysisPipeline's
    /// rollingWindow are both sized at construction time with no resize
    /// path. ringBuffer/captureEngine stay `let`: ring buffer capacity only
    /// depends on sampleRate, unaffected by window/hop size.
    private var pipeline: AudioAnalysisPipeline
    private let captureEngine: MicrophoneCaptureEngine
    private let deviceEnumerator = AudioDeviceEnumerator(scope: .input)
    private var streamTask: Task<Void, Never>?
    /// Self-healing watchdog (bug fix -- diagnosed via log instrumentation,
    /// user report: waterfall/RTA/Tracked Frequency permanently froze after
    /// rapidly switching FFT window size a few times in a row). Confirmed
    /// root cause via [DIAG] logging: AudioRingBuffer's writeIndex stopped
    /// advancing forever partway through a restart -- MicrophoneCaptureEngine's
    /// freshly-constructed AVAudioEngine (already a fix for an earlier,
    /// related tap-death report) silently stopped delivering tap buffers,
    /// with no error thrown and no further "tap fired" callbacks at all.
    /// This is a known AVAudioEngine robustness gap when a device is
    /// torn down and rebound in quick succession, not something fixable by
    /// getting our own ring-buffer bookkeeping more correct (that part was
    /// already verified sound) -- so instead of trying to prevent every way
    /// AVAudioEngine can wedge itself, this watches for the *symptom*
    /// (no hop delivered in a while, even though capture is supposed to be
    /// running) and transparently restarts capture, the same recovery a
    /// tech would perform by hand via Stop->Start.
    private var watchdogTask: Task<Void, Never>?
    /// Updated on every hop the pipeline actually delivers (receive(_:)),
    /// unconditionally -- including while frozen -- so Freeze (which
    /// intentionally withholds published updates) is never mistaken for a
    /// stall.
    private var lastHopAt: Date?
    private static let stallTimeout: TimeInterval = 3
    /// Consecutive watchdog restarts that have not yet produced a hop --
    /// drives exponential backoff (3s, 6s, 12s, 24s, 48s cap) so a capture
    /// stack that is *staying* broken isn't hammered with a full engine
    /// teardown/rebuild every 3s forever (closed part of CLAUDE.md "Known
    /// gap #2": that thrash rebuilt the mic's voice-isolation aggregate
    /// device every cycle against an already-wedged coreaudiod, plausibly
    /// making the wedge worse). Reset by the next real hop (receive(_:)).
    private var stallRestartCount = 0

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

        // Device enumeration runs unconditionally from init (matching
        // SignalGeneratorEngine's Output Device setup) so the Input Device
        // picker is populated immediately, even though capture itself no
        // longer auto-starts (see `start()` -- the app now launches with
        // measurements off, user presses Start).
        deviceEnumerator.onChange = { [weak self] in self?.refreshAvailableDevices() }
        deviceEnumerator.startObserving()
        refreshAvailableDevices()

    }

    /// See MicrophoneCaptureEngine.onConfigurationChange: the engine stops
    /// itself when the device's IO configuration changes under it (e.g. a
    /// sample-rate change in Audio MIDI Setup) -- restart promptly rather
    /// than waiting out the stall watchdog. Installed lazily from the
    /// first performStartCapture rather than init (Swift 6 warning fix:
    /// escaping a @Sendable closure that captures `self` from inside init
    /// is flagged as a concurrency error-to-be, since `self` isn't fully
    /// initialized until init returns) -- the handler is only meaningful
    /// once capture has started anyway.
    private var configurationChangeHandlerInstalled = false

    private func installConfigurationChangeHandlerIfNeeded() async {
        guard !configurationChangeHandlerInstalled else { return }
        configurationChangeHandlerInstalled = true
        await captureEngine.setConfigurationChangeHandler {
            Task { @MainActor [weak self] in
                self?.handleEngineConfigurationChange()
            }
        }
    }

    /// Restarts capture after the engine invalidated itself (see
    /// MicrophoneCaptureEngine.onConfigurationChange). Restarting re-reads
    /// the hardware rate, so a rate change flows through the usual
    /// sample-rate adaptation. Bounded via stallRestartCount: on a HAL sick
    /// enough that every fresh engine immediately re-invalidates (observed
    /// in the field with third-party audio drivers loaded), unlimited
    /// prompt restarts would thrash the daemon in a tight loop -- after 3
    /// consecutive attempts with no hop delivered, further notifications
    /// are ignored and recovery is left to the watchdog's exponential
    /// backoff. A real hop resets the count (receive(_:)).
    private func handleEngineConfigurationChange() {
        guard isCaptureActive, selectedInputDeviceID != nil else { return }
        guard stallRestartCount < 3 else { return }
        let captureEngine = captureEngine
        Task { @MainActor [weak self] in
            // Only restart if the engine actually stopped itself.
            // AVAudioEngineConfigurationChange also fires for benign graph
            // reconfigurations the engine survives (observed ~100ms after
            // every successful start, engine still delivering buffers) --
            // restarting on those tore capture down three times in a row on
            // every Start press. A genuine device rate change stops the
            // engine, so engineIsRunning is false by the time the
            // notification arrives. If a benign notification races a real
            // stop, the stall watchdog still recovers.
            guard await !captureEngine.engineIsRunning else { return }
            guard let self, self.isCaptureActive, let deviceID = self.selectedInputDeviceID else { return }
            guard self.stallRestartCount < 3 else { return }
            self.stallRestartCount += 1
            diagLog.notice("Engine configuration changed (engine stopped itself), restarting capture at device=\(deviceID, privacy: .public) (attempt \(self.stallRestartCount, privacy: .public))")
            self.startCapture(deviceID: deviceID, persistChoice: false)
        }
    }

    /// Starts capturing and streaming analysis updates. Resolves which
    /// input device to use (AudioDeviceSelector) from the persisted last
    /// explicit choice, falling back to the system default. Safe to call
    /// multiple times; a no-op once already running. The app no longer
    /// calls this automatically at launch (user decision: measurements
    /// start off, so an explicit Start press -- not app open -- is what
    /// triggers the mic permission prompt) -- it's reached via the Stop/
    /// Start button's `resumeCapture()` falling back here on a cold launch.
    func start() {
        guard !isCaptureActive else { return }

        guard let deviceID = resolveDefaultDeviceID() else {
            // No input devices available at all -- stay stopped.
            return
        }
        startCapture(deviceID: deviceID, persistChoice: false)
    }

    /// The persisted-choice-falling-back-to-system-default resolution
    /// start() has always performed, extracted so the FFT-switch rebuild
    /// can reuse it for its cold-start restart case.
    private func resolveDefaultDeviceID() -> String? {
        AudioDeviceSelector.resolve(
            availableDevices: availableInputDevices,
            persistedDeviceID: UserDefaults.standard.string(forKey: Self.persistedDeviceIDDefaultsKey),
            systemDefaultDeviceID: deviceEnumerator.systemDefaultDeviceID()
        )
    }

    /// Explicit device selection from the Input Device picker (or a
    /// reconnect from the disconnected state): always (re)starts capture at
    /// the chosen device and persists it as the new last explicit choice.
    func selectInputDevice(id: String) {
        startCapture(deviceID: id, persistChoice: true)
    }

    func stop() {
        stopGeneration += 1
        haltPublishing()
        isCaptureStalled = false
        connectionState = connectionState.stopping()
        // The engine's own stop makes blocking HAL calls -- queued off the
        // main actor (see pendingCaptureOperation), while the state changes
        // above take effect immediately so the UI reads Stopped at once.
        enqueueCaptureOperation { [weak self] in
            await self?.captureEngine.stop()
        }
    }

    /// Stop/Start as a single toggle (spacebar shortcut, AppShellView) --
    /// same Stop/Start pair the Controls row button already drives, just
    /// reachable without a mouse.
    func toggleCapture() {
        if isCaptureActive {
            stop()
        } else {
            resumeCapture()
        }
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

    /// Enqueues a capture (re)start -- the actual work happens in
    /// performStartCapture inside the serialized operation chain, off the
    /// main actor's critical path (see pendingCaptureOperation). The
    /// stopGeneration snapshot is taken here, at enqueue time: a Stop
    /// pressed between enqueue and run must win.
    private func startCapture(deviceID: String, persistChoice: Bool) {
        let generation = stopGeneration
        enqueueCaptureOperation { [weak self] in
            guard let self, self.stopGeneration == generation else { return }
            await self.performStartCapture(deviceID: deviceID, persistChoice: persistChoice, generation: generation)
        }
    }

    /// Attempts to (re)start capture at `deviceID`. On success, updates
    /// `selectedInputDeviceID`/`connectionState` and persists the choice if
    /// requested. On failure, leaves neither stale -- resets to `.stopped`
    /// rather than reporting a device as selected/running that never
    /// actually started (found by code review on #4). Only ever runs inside
    /// the serialized capture-operation chain; `generation` re-checks after
    /// every await abort cleanly if a Stop landed mid-flight.
    private func performStartCapture(deviceID: String, persistChoice: Bool, generation: Int) async {
        haltPublishing()
        await installConfigurationChangeHandlerIfNeeded()
        await captureEngine.stop()
        guard stopGeneration == generation else { return }

        let coreAudioDeviceID = deviceEnumerator.deviceID(forUID: deviceID)
        let hardwareRate: Double
        do {
            hardwareRate = try await captureEngine.start(deviceID: coreAudioDeviceID)
        } catch {
            // No hardware/permission in this environment (or denied by the
            // user), or the device vanished between resolving it and
            // starting -- readouts stay at their placeholder state.
            if stopGeneration == generation { connectionState = .stopped }
            return
        }
        guard stopGeneration == generation else {
            // Stop landed while the engine was starting -- shut the engine
            // straight back down rather than leaving it capturing into a
            // ring buffer nothing reads.
            await captureEngine.stop()
            return
        }

        if persistChoice {
            UserDefaults.standard.set(deviceID, forKey: Self.persistedDeviceIDDefaultsKey)
        }
        selectedInputDeviceID = deviceID
        selectedInputDeviceFormat = deviceEnumerator.format(forUID: deviceID)
        connectionState = connectionState.selecting(deviceID: deviceID)

        // Sample-rate adaptation (closed the former CLAUDE.md "Known gap"):
        // the engine only knows the hardware's actual input rate once it
        // has started, and AnalysisConfig's 48kHz default is just a nominal
        // guess -- on 44.1kHz hardware every frequency readout would
        // otherwise be ~8.8% sharp (bin index x wrong bin width). On
        // mismatch, rebuild the pipeline at the actual rate before starting
        // the result stream; the engine itself keeps running (it's already
        // capturing at the right rate into the ring buffer), so this is a
        // pipeline-only rebuild, not a capture restart. Runs inline here --
        // the whole method is already serialized and off the UI's critical
        // path, so no separately-chained task is needed.
        if hardwareRate != config.sampleRate {
            let oldPipeline = pipeline
            await oldPipeline.stop()
            config = fftWindowSize.config(sampleRate: hardwareRate)
            // Fresh pipeline also means fresh AnomalyDetector/
            // TimeAveragingBlender state, same as an FFT-size switch; held
            // peaks are deliberately left untouched, same reasoning as
            // there.
            pipeline = AudioAnalysisPipeline(config: config, ringBuffer: ringBuffer, weighting: weighting, timeAveraging: timeAveraging)
            guard stopGeneration == generation else { return }
        }

        beginStreaming()
    }

    /// Starts consuming the pipeline's result stream and arms the stall
    /// watchdog -- the tail of a successful capture start, split out of
    /// startCapture so the sample-rate adaptation path above can defer it
    /// until after its pipeline rebuild.
    private func beginStreaming() {
        let pipeline = pipeline
        streamTask = Task { [weak self] in
            let stream = await pipeline.start()
            for await result in stream {
                guard !Task.isCancelled else { break }
                self?.receive(result)
            }
        }

        lastHopAt = Date()
        watchdogTask?.cancel()
        watchdogTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self, !Task.isCancelled, self.isCaptureActive else { continue }
                // Exponential backoff -- see stallRestartCount's doc comment.
                let timeout = Self.stallTimeout * pow(2, Double(min(self.stallRestartCount, 4)))
                guard let lastHopAt = self.lastHopAt,
                      Date().timeIntervalSince(lastHopAt) > timeout else { continue }
                guard let deviceID = self.selectedInputDeviceID else { continue }
                diagLog.notice("Watchdog: no hop in \(timeout, privacy: .public)s, restarting capture at device=\(deviceID, privacy: .public) (attempt \(self.stallRestartCount + 1, privacy: .public))")
                self.stallRestartCount += 1
                // The first restart attempt is given a chance to cure the
                // stall silently; from the second on, the stall is
                // persistent and the tech should see why nothing updates.
                if self.stallRestartCount >= 2 {
                    self.isCaptureStalled = true
                }
                self.startCapture(deviceID: deviceID, persistChoice: false)
            }
        }
    }

    /// Routes one hop's result through `freezeGate`: published immediately
    /// when not frozen, held silently when frozen (CONTEXT.md "Freeze") --
    /// the pipeline itself never knows or cares whether the display is
    /// frozen.
    private func receive(_ result: AnalysisResult) {
        lastHopAt = Date()
        stallRestartCount = 0
        isCaptureStalled = false
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
        fullScalePower = result.fullScalePower
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
        let bars = RTABinning.bars(magnitudes: result.magnitudes, config: config, barsPerOctave: bandingResolution.rawValue, fullScalePower: result.fullScalePower)
        latestRTABars = bars
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
        selectedInputDeviceFormat = selectedInputDeviceID.flatMap { deviceEnumerator.format(forUID: $0) }
        let availableIDs = Set(availableInputDevices.map(\.id))
        let nextState = connectionState.handlingDeviceListChange(availableDeviceIDs: availableIDs)

        switch (connectionState, nextState) {
        case (.running, .disconnected):
            // A disconnect is a stop from the user's perspective (ADR 0006:
            // never a silent fallback) -- bump stopGeneration so any queued
            // restart against the vanished device aborts.
            stopGeneration += 1
            haltPublishing()
            connectionState = nextState
            enqueueCaptureOperation { [weak self] in
                await self?.captureEngine.stop()
            }
        case (.disconnected, .running(let deviceID)):
            startCapture(deviceID: deviceID, persistChoice: false)
        default:
            connectionState = nextState
        }
    }

    /// Stops consuming/publishing pipeline results (stream + watchdog +
    /// published values). Deliberately does NOT stop the capture engine --
    /// its stop() makes blocking HAL calls, so engine stops always go
    /// through the serialized capture-operation chain instead (see
    /// pendingCaptureOperation; user report of the freeze this caused:
    /// "the app freezes when i change the built in mic to 44.1").
    ///
    /// If the display is frozen (CONTEXT.md "Freeze"), the on-screen
    /// snapshot is left exactly as-is rather than force-cleared to a
    /// placeholder -- Stop (or a disconnect) happening underneath a frozen
    /// display must not itself count as an "on-screen update" (found by
    /// code review: this previously cleared the three published properties
    /// directly, bypassing `freezeGate`, so Stop while frozen silently
    /// blanked what was supposed to be a static snapshot).
    private func haltPublishing() {
        streamTask?.cancel()
        streamTask = nil
        watchdogTask?.cancel()
        watchdogTask = nil
        guard !isFrozen else { return }
        trackedFrequencyHz = nil
        latestMagnitudes = []
        splDb = nil
        trackedFrequencyLevelDb = nil
        anomalyCandidates = []
    }

    /// "2340 Hz"-style formatting for the Measured Data row's hero number,
    /// or an em dash placeholder before capture produces a first result.
    /// Whole Hz, not fractional -- finer than the FFT's own bin resolution
    /// (~12Hz at the default config) would be false precision.
    var formattedFrequency: String {
        guard let hz = trackedFrequencyHz else { return "\u{2014}" }
        return String(format: "%.0f Hz", hz)
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
