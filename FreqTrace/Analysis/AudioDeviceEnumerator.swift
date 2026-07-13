//
//  AudioDeviceEnumerator.swift
//  FreqTrace
//
//  Core Audio device listing for the Input/Output Device pickers (ticket
//  #4, CONTEXT.md "Input Device" / "Output Device"). Lists devices that
//  expose the given scope's streams (input or output), reports the system
//  default, and notifies on any change to the device list or default so the
//  UI can react to hardware being plugged/unplugged. Not unit-testable in
//  this environment (no real audio hardware in CI/sandbox) -- see
//  InputDeviceTests.swift for the pure decision logic this feeds.
//

import CoreAudio
import Foundation

enum AudioDeviceScope {
    case input
    case output

    fileprivate var streamsSelector: AudioObjectPropertySelector {
        switch self {
        case .input: kAudioDevicePropertyStreams
        case .output: kAudioDevicePropertyStreams
        }
    }

    fileprivate var streamsScope: AudioObjectPropertyScope {
        switch self {
        case .input: kAudioObjectPropertyScopeInput
        case .output: kAudioObjectPropertyScopeOutput
        }
    }

    fileprivate var defaultDeviceSelector: AudioObjectPropertySelector {
        switch self {
        case .input: kAudioHardwarePropertyDefaultInputDevice
        case .output: kAudioHardwarePropertyDefaultOutputDevice
        }
    }
}

@MainActor
final class AudioDeviceEnumerator {
    private let scope: AudioDeviceScope
    private var listenerBlock: AudioObjectPropertyListenerBlock?

    /// Called whenever the available device list or system default changes.
    var onChange: (() -> Void)?

    init(scope: AudioDeviceScope) {
        self.scope = scope
    }

    deinit {
        // Listener teardown intentionally omitted: this type is owned for
        // the app's lifetime by AudioPipelineViewModel, so there is no
        // point at which a live listener needs removing before process exit.
    }

    /// All devices exposing at least one stream in `scope`.
    func availableDevices() -> [AudioDevice] {
        allDeviceIDs().compactMap { deviceID in
            guard hasStreams(deviceID: deviceID, scope: scope) else { return nil }
            guard let uid = stringProperty(deviceID: deviceID, selector: kAudioDevicePropertyDeviceUID) else { return nil }
            let name = stringProperty(deviceID: deviceID, selector: kAudioObjectPropertyName) ?? uid
            return AudioDevice(id: uid, name: name)
        }
    }

    /// The system default device's UID for `scope`, if any.
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

    private func hasStreams(deviceID: AudioDeviceID, scope: AudioDeviceScope) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: scope.streamsSelector,
            mScope: scope.streamsScope,
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
