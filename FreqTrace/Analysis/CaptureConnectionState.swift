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

    /// Applies a change in the set of currently available device IDs. Only
    /// `.running` is affected: if its device is no longer present, it
    /// becomes `.disconnected` -- `.stopped` and `.disconnected` are
    /// unaffected since there's no active device to lose.
    func handlingDeviceListChange(availableDeviceIDs: Set<String>) -> CaptureConnectionState {
        guard case .running(let deviceID) = self, !availableDeviceIDs.contains(deviceID) else {
            return self
        }
        return .disconnected(deviceID: deviceID)
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
