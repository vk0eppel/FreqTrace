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

struct AudioDevice: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
}

/// A device's current hardware operating format (user request: "indicate
/// sample rate and bit depth near the input device") -- the nominal sample
/// rate plus the physical stream's bit depth. Bit depth is optional: some
/// devices (aggregates, certain virtual drivers) don't expose a physical
/// format. Pure data + formatting; the Core Audio queries live in
/// AudioDeviceEnumerator.format(forUID:).
struct AudioDeviceFormat: Equatable, Sendable {
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

/// Pure decision logic for which device should be active: given the
/// currently available devices, a persisted last explicit choice, and the
/// system default, decides which device ID to use. Independent of real Core
/// Audio enumeration -- see AudioDeviceEnumerator for the hardware side.
/// Originally named InputDeviceSelector (ticket #4); generalized here
/// (ticket #14) since the logic was never input-specific, only its name --
/// it's now shared by both the Input Device and Output Device pickers.
enum AudioDeviceSelector {
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
