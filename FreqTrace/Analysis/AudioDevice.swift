//
//  AudioDevice.swift
//  FreqTrace
//
//  Pure data type for the Input/Output Device pickers (ticket #4 for Input,
//  ticket #14 for Output; CONTEXT.md "Input Device" / "Output Device"). `id`
//  is the Core Audio device's UID (a persistent string, stable across
//  reboots), not its AudioDeviceID (which is only valid for the current
//  session) -- the UID is what gets persisted as the "last explicit choice."
//

import Foundation

// Pure value types, nonisolated: opt out of the module's default
// @MainActor isolation (Swift 6) -- exercised by nonisolated unit tests.
nonisolated struct AudioDevice: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
}

/// A device's current hardware operating format (user request: "indicate
/// sample rate and bit depth near the input device") -- the nominal sample
/// rate plus the physical stream's bit depth. Bit depth is optional: some
/// devices (aggregates, certain virtual drivers) don't expose a physical
/// format. Pure data + formatting; the Core Audio queries live in
/// AudioDeviceEnumerator.format(forUID:).
nonisolated struct AudioDeviceFormat: Equatable, Sendable {
    let sampleRate: Double
    let bitDepth: Int?

    /// "44.1kHz · 24-bit" -- whole kHz shown without a decimal ("48kHz"),
    /// fractional rates with one ("44.1kHz"); the bit-depth segment is
    /// omitted entirely when unknown rather than showing a placeholder.
    var displayString: String {
        let kHz = sampleRate / 1000
        let rate = kHz == kHz.rounded()
            ? String(format: "%.0fkHz", kHz)
            : String(format: "%.1fkHz", kHz)
        guard let bitDepth else { return rate }
        return "\(rate) \u{00B7} \(bitDepth)-bit"
    }
}

/// What the Input Device plate should display (ticket #23). The old label
/// showed `No Input Device` whenever nothing was explicitly selected, even
/// though a mic was available and would be used on the next Start -- it read
/// as an error. This distinguishes three states so the plate can preview the
/// device a Start would actually capture from, dimmed, instead of alarming.
///
/// The resolved-default fallback only applies when *nothing* is selected
/// (the fresh-launch stopped state). A disconnected device is still selected
/// (ADR 0006: no silent fallback), so `selectedDeviceID` is non-nil and the
/// fallback never fires -- resolve returns `.none`, matching the honest
/// "device is gone" reading the DISCONNECTED indicator already shows.
nonisolated enum InputDevicePlateLabel: Equatable {
    /// Capture is running from this device.
    case active(name: String)
    /// Stopped, but this is the device the next Start would capture from --
    /// shown dimmed to signal it isn't running yet.
    case preview(name: String)
    /// No input device resolves at all (genuinely none available, or the
    /// selected one has disconnected). Named `unavailable`, not `none`, to
    /// avoid shadowing `Optional.none` at call sites.
    case unavailable

    static func resolve(
        isCapturing: Bool,
        selectedDeviceID: String?,
        resolvedDefaultID: String?,
        availableDevices: [AudioDevice]
    ) -> InputDevicePlateLabel {
        let id = selectedDeviceID ?? resolvedDefaultID
        guard let id, let device = availableDevices.first(where: { $0.id == id }) else {
            return .unavailable
        }
        return isCapturing ? .active(name: device.name) : .preview(name: device.name)
    }
}

/// Pure decision logic for which device should be active: given the
/// currently available devices, a persisted last explicit choice, and the
/// system default, decides which device ID to use. Independent of real Core
/// Audio enumeration -- see AudioDeviceEnumerator for the hardware side.
/// Originally named InputDeviceSelector (ticket #4); generalized here
/// (ticket #14) since the logic was never input-specific, only its name --
/// it's now shared by both the Input Device and Output Device pickers.
nonisolated enum AudioDeviceSelector {
    static func resolve(
        availableDevices: [AudioDevice],
        persistedDeviceID: String?,
        systemDefaultDeviceID: String?
    ) -> String? {
        if let persistedDeviceID, availableDevices.contains(where: { $0.id == persistedDeviceID }) {
            return persistedDeviceID
        }
        if let systemDefaultDeviceID, availableDevices.contains(where: { $0.id == systemDefaultDeviceID }) {
            return systemDefaultDeviceID
        }
        return availableDevices.first?.id
    }
}
