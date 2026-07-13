//
//  CaptureConnectionState.swift
//  FreqTrace
//
//  Pure state machine behind the Input Device disconnect behavior (ticket
//  #4, ADR 0006): if the active device disappears mid-use, the pipeline
//  transitions to `.disconnected` (explicit indicator), never silently to a
//  different device. Independent of real Core Audio/AVAudioEngine
//  notifications -- see MicrophoneCaptureEngine for the hardware side.
//
enum CaptureConnectionState: Equatable, Sendable {
    case stopped
    case running(deviceID: String)
    case disconnected(deviceID: String)

    /// Applies a change in the set of currently available device IDs.
    /// `.running` whose device disappears becomes `.disconnected`;
    /// `.disconnected` whose device reappears resumes `.running` (the
    /// passive-reconnect half of the AC -- distinct from `selecting`, which
    /// covers the tech manually picking a device). `.stopped` is unaffected,
    /// since there's no active device to lose or regain.
    func handlingDeviceListChange(availableDeviceIDs: Set<String>) -> CaptureConnectionState {
        switch self {
        case .running(let deviceID) where !availableDeviceIDs.contains(deviceID):
            return .disconnected(deviceID: deviceID)
        case .disconnected(let deviceID) where availableDeviceIDs.contains(deviceID):
            return .running(deviceID: deviceID)
        default:
            return self
        }
    }

    /// A user picking a device (initial selection, switching devices, or
    /// reconnecting from `.disconnected`) always (re)starts capture.
    func selecting(deviceID: String) -> CaptureConnectionState {
        .running(deviceID: deviceID)
    }

    /// The explicit Stop control (CONTEXT.md "Stop") always halts capture,
    /// regardless of the prior state.
    func stopping() -> CaptureConnectionState {
        .stopped
    }
}
