//
//  DeviceConnectionState.swift
//  FreqTrace
//
//  Pure state machine behind the Input/Output Device disconnect behavior
//  (ticket #4 for Input, ADR 0006; ticket #14 for Output, same ADR): if the
//  active device disappears mid-use, the pipeline/generator transitions to
//  `.disconnected` (explicit indicator), never silently to a different
//  device. Independent of real Core Audio/AVAudioEngine notifications --
//  see MicrophoneCaptureEngine / SignalGeneratorEngine for the hardware
//  side.
//
//  Originally named CaptureConnectionState (ticket #4) and scoped to the
//  Input Device's capture pipeline. Renamed here (ticket #14) rather than
//  reused under its old name: the Signal Generator's Output Device is a
//  playback/output connection, not a "capture" in any sense, and keeping
//  the old name would read as actively confusing at that call site even
//  though the state machine itself is unchanged and fully covered by the
//  existing tests (see InputDeviceTests.swift).
//
// Pure value type, nonisolated: opts out of the module's default
// @MainActor isolation (Swift 6) -- exercised by nonisolated unit tests.
nonisolated enum DeviceConnectionState: Equatable, Sendable {
    case stopped
    case running(deviceID: String)
    case disconnected(deviceID: String)

    /// Applies a change in the set of currently available device IDs.
    /// `.running` whose device disappears becomes `.disconnected`;
    /// `.disconnected` whose device reappears resumes `.running` (the
    /// passive-reconnect half of the AC -- distinct from `selecting`, which
    /// covers the tech manually picking a device). `.stopped` is unaffected,
    /// since there's no active device to lose or regain.
    func handlingDeviceListChange(availableDeviceIDs: Set<String>) -> DeviceConnectionState {
        switch self {
        case .running(let deviceID) where !availableDeviceIDs.contains(deviceID):
            return .disconnected(deviceID: deviceID)
        case .disconnected(let deviceID) where availableDeviceIDs.contains(deviceID):
            return .running(deviceID: deviceID)
        default:
            return self
        }
    }

    /// The state a device pick lands in *once capture has actually started*
    /// -- switching the live pipeline's device, or reconnecting from
    /// `.disconnected`. Not reached by a pick made while `.stopped` (ticket
    /// #17): that only records the selection and stays `.stopped` -- see
    /// `pickStartsCapture`.
    func selecting(deviceID: String) -> DeviceConnectionState {
        .running(deviceID: deviceID)
    }

    /// Whether picking a device from this state should (re)start capture, or
    /// merely record the selection for the next Start (ticket #17). From
    /// `.stopped`, a pick only selects -- capture stays off until a
    /// deliberate Start, so the mic-permission prompt never appears as a
    /// side effect of a device pick (ADR 0007: measurements start off).
    /// From `.running` (re-point the live pipeline) or `.disconnected`
    /// (mid-show "my mic died, here's the replacement, go"), a pick starts
    /// capture immediately. The always-start behavior predates ADR 0007 --
    /// it was written when the app auto-started capture at launch and a
    /// pick meant "re-point the running pipeline"; that stays true for the
    /// two active states, but no longer for `.stopped`.
    var pickStartsCapture: Bool {
        switch self {
        case .stopped:
            return false
        case .running, .disconnected:
            return true
        }
    }

    /// The explicit Stop control (CONTEXT.md "Stop") -- or, for the Signal
    /// Generator, its On/Off switch turning off -- always halts
    /// capture/playback, regardless of the prior state.
    func stopping() -> DeviceConnectionState {
        .stopped
    }
}
