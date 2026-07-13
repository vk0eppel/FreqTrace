//
//  AudioDeviceEnumerator.swift
//  FreqTrace
//
//  Core Audio device listing for the Input Device picker (ticket #4,
//  CONTEXT.md "Input Device"). Lists devices that expose an input stream,
//  reports the system default input, and notifies on any change to the
//  device list or default so the UI can react to hardware being
//  plugged/unplugged. Not unit-testable in this environment (no real audio
//  hardware in CI/sandbox) -- see InputDeviceTests.swift for the pure
//  decision logic this feeds.
//
//  Input-only for now: Output Device (CONTEXT.md "Output Device") has "the
//  same shape" per CONTEXT.md, but belongs to its own ticket (#14) -- no
//  point generalizing this before that ticket needs it.
//

import CoreAudio
import Foundation

@MainActor
final class AudioDeviceEnumerator {
    private var listenerBlock: AudioObjectPropertyListenerBlock?

    /// Called whenever the available device list or system default changes.
    var onChange: (() -> Void)?

    deinit {
        // Listener teardown intentionally omitted: this type is owned for
        // the app's lifetime by AudioPipelineViewModel, so there is no
        // point at which a live listener needs removing before process exit.
    }

    /// All devices exposing at least one input stream.
    func availableDevices() -> [AudioDevice] {
        allDeviceIDs().compactMap { deviceID in
            guard hasInputStreams(deviceID: deviceID) else { return nil }
            guard let uid = stringProperty(deviceID: deviceID, selector: kAudioDevicePropertyDeviceUID) else { return nil }
            let name = stringProperty(deviceID: deviceID, selector: kAudioObjectPropertyName) ?? uid
            return AudioDevice(id: uid, name: name)
        }
    }

    /// The system default input device's UID, if any.
    func systemDefaultDeviceID() -> String? {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
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

        for selector in [kAudioHardwarePropertyDevices, kAudioHardwarePropertyDefaultInputDevice] {
            var address = AudioObjectPropertyAddress(
                mSelector: selector,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main, block)
        }
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

    private func hasInputStreams(deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioObjectPropertyScopeInput,
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
