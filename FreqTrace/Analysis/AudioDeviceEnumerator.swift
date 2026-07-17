//
//  AudioDeviceEnumerator.swift
//  FreqTrace
//
//  Core Audio device listing for the Input and Output Device pickers
//  (ticket #4 for Input, CONTEXT.md "Input Device"; ticket #14 for Output,
//  CONTEXT.md "Output Device"). Lists devices that expose a stream in the
//  requested direction, reports the matching system default, and notifies
//  on any change to the device list or default so the UI can react to
//  hardware being plugged/unplugged. Not unit-testable in this environment
//  (no real audio hardware in CI/sandbox) -- see InputDeviceTests.swift for
//  the pure decision logic this feeds.
//
//  Originally input-only (an earlier ticket generalized it, then a code
//  review deliberately cut that back to input-only as premature
//  generalization ahead of Output Device actually being needed). Ticket
//  #14 is that point: `Scope` selects input vs. output, and the shared
//  Core Audio boilerplate (property-address construction, ID/string
//  lookups, change observation) lives once here rather than being
//  duplicated into a second output-only type.
//

import CoreAudio
import Foundation

@MainActor
final class AudioDeviceEnumerator {
    /// Which stream direction this enumerator lists/observes -- Input
    /// Device and Output Device each get their own instance.
    enum Scope {
        case input
        case output

        var streamPropertyScope: AudioObjectPropertyScope {
            switch self {
            case .input: kAudioObjectPropertyScopeInput
            case .output: kAudioObjectPropertyScopeOutput
            }
        }

        var defaultDeviceSelector: AudioObjectPropertySelector {
            switch self {
            case .input: kAudioHardwarePropertyDefaultInputDevice
            case .output: kAudioHardwarePropertyDefaultOutputDevice
            }
        }
    }

    private let scope: Scope
    private var listenerBlock: AudioObjectPropertyListenerBlock?

    /// Called whenever the available device list or system default changes.
    var onChange: (() -> Void)?

    init(scope: Scope) {
        self.scope = scope
    }

    deinit {
        // Listener teardown intentionally omitted: this type is owned for
        // the app's lifetime by AudioPipelineViewModel/SignalGeneratorEngine,
        // so there is no point at which a live listener needs removing
        // before process exit.
    }

    /// All devices exposing at least one stream in this enumerator's scope.
    func availableDevices() -> [AudioDevice] {
        allDeviceIDs().compactMap { deviceID in
            guard hasStreams(deviceID: deviceID) else { return nil }
            guard let uid = stringProperty(deviceID: deviceID, selector: kAudioDevicePropertyDeviceUID) else { return nil }
            let name = stringProperty(deviceID: deviceID, selector: kAudioObjectPropertyName) ?? uid
            return AudioDevice(id: uid, name: name)
        }
    }

    /// The system default device's UID for this scope, if any.
    func systemDefaultDeviceID() -> String? {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: scope.defaultDeviceSelector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID)
        guard status == noErr, deviceID != 0 else { return nil }
        return stringProperty(deviceID: deviceID, selector: kAudioDevicePropertyDeviceUID)
    }

    /// Translates a device UID (as persisted/selected in the UI) back to
    /// the Core Audio AudioDeviceID needed to route AVAudioEngine at it.
    func deviceID(forUID uid: String) -> AudioDeviceID? {
        var cfUID = uid as CFString
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioValueTranslation>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDeviceForUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = withUnsafeMutablePointer(to: &cfUID) { uidPointer -> OSStatus in
            withUnsafeMutablePointer(to: &deviceID) { deviceIDPointer -> OSStatus in
                var translation = AudioValueTranslation(
                    mInputData: UnsafeMutableRawPointer(uidPointer),
                    mInputDataSize: UInt32(MemoryLayout<CFString>.size),
                    mOutputData: UnsafeMutableRawPointer(deviceIDPointer),
                    mOutputDataSize: UInt32(MemoryLayout<AudioDeviceID>.size)
                )
                return AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &translation)
            }
        }
        guard status == noErr, deviceID != 0 else { return nil }
        return deviceID
    }

    /// Starts observing device list / default-device changes. `onChange`
    /// fires (on the main queue) for either.
    func startObserving() {
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.onChange?()
        }
        listenerBlock = block

        for selector in [kAudioHardwarePropertyDevices, scope.defaultDeviceSelector] {
            var address = AudioObjectPropertyAddress(
                mSelector: selector,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main, block)
        }
    }

    /// The device's current hardware operating format (user request:
    /// "indicate sample rate and bit depth near the input device"): its
    /// nominal sample rate, plus the bit depth of its first stream's
    /// *physical* format in this enumerator's scope (the wire format the
    /// hardware actually runs, e.g. 24-bit integer -- not the HAL's
    /// Float32 client-side representation, which would always read
    /// "32-bit" regardless of the converter or interface underneath).
    func format(forUID uid: String) -> AudioDeviceFormat? {
        guard let deviceID = deviceID(forUID: uid) else { return nil }

        var rateAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var sampleRate = 0.0
        var rateSize = UInt32(MemoryLayout<Double>.size)
        guard AudioObjectGetPropertyData(deviceID, &rateAddress, 0, nil, &rateSize, &sampleRate) == noErr,
              sampleRate > 0 else { return nil }

        return AudioDeviceFormat(sampleRate: sampleRate, bitDepth: physicalBitDepth(deviceID: deviceID))
    }

    private func physicalBitDepth(deviceID: AudioDeviceID) -> Int? {
        var streamsAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: scope.streamPropertyScope,
            mElement: kAudioObjectPropertyElementMain
        )
        var streamsSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &streamsAddress, 0, nil, &streamsSize) == noErr,
              streamsSize >= UInt32(MemoryLayout<AudioStreamID>.size) else { return nil }
        var streamIDs = [AudioStreamID](repeating: 0, count: Int(streamsSize) / MemoryLayout<AudioStreamID>.size)
        guard AudioObjectGetPropertyData(deviceID, &streamsAddress, 0, nil, &streamsSize, &streamIDs) == noErr,
              let firstStream = streamIDs.first else { return nil }

        var formatAddress = AudioObjectPropertyAddress(
            mSelector: kAudioStreamPropertyPhysicalFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var format = AudioStreamBasicDescription()
        var formatSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        guard AudioObjectGetPropertyData(firstStream, &formatAddress, 0, nil, &formatSize, &format) == noErr,
              format.mBitsPerChannel > 0 else { return nil }
        return Int(format.mBitsPerChannel)
    }

    private func allDeviceIDs() -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else {
            return []
        }
        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceIDs) == noErr else {
            return []
        }
        return deviceIDs
    }

    private func hasStreams(deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: scope.streamPropertyScope,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size) == noErr else { return false }
        return size > 0
    }

    private func stringProperty(deviceID: AudioDeviceID, selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<CFString?>.size)
        var value: CFString?
        let status = withUnsafeMutablePointer(to: &value) { pointer -> OSStatus in
            AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, pointer)
        }
        guard status == noErr else { return nil }
        return value as String?
    }
}
