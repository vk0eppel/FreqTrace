//
//  InputDeviceTests.swift
//  FreqTraceTests
//
//  Exercises the pure decision logic behind Input/Output Device selection
//  (ticket #4 for Input, ticket #14 for Output; CONTEXT.md "Input Device" /
//  "Output Device"): AudioDeviceSelector.resolve picks which device should
//  be active from (available devices, persisted last explicit choice,
//  system default), independent of real Core Audio hardware -- see
//  MicrophoneCaptureEngine.swift for why the hardware glue itself is not
//  unit-tested here. Originally InputDeviceSelectorTests/InputDeviceSelector
//  before ticket #14 generalized the type for reuse by Output Device; kept
//  this file's name since it still reads fine covering the shared
//  DeviceConnectionState machine too.
//

import Testing
@testable import FreqTrace

struct AudioDeviceSelectorTests {

    private let mic = AudioDevice(id: "built-in-mic", name: "MacBook Pro Microphone")
    private let usb = AudioDevice(id: "usb-interface", name: "Scarlett 2i2")

    @Test func firstLaunchWithNoPersistedChoiceUsesSystemDefault() {
        let resolved = AudioDeviceSelector.resolve(
            availableDevices: [mic, usb],
            persistedDeviceID: nil,
            systemDefaultDeviceID: usb.id
        )

        #expect(resolved == usb.id)
    }

    @Test func persistedChoiceStillAvailableWinsOverSystemDefault() {
        let resolved = AudioDeviceSelector.resolve(
            availableDevices: [mic, usb],
            persistedDeviceID: mic.id,
            systemDefaultDeviceID: usb.id
        )

        #expect(resolved == mic.id)
    }

    @Test func persistedChoiceNoLongerAvailableFallsBackToSystemDefault() {
        let resolved = AudioDeviceSelector.resolve(
            availableDevices: [usb],
            persistedDeviceID: mic.id,
            systemDefaultDeviceID: usb.id
        )

        #expect(resolved == usb.id)
    }

    @Test func nothingAvailableResolvesToNil() {
        let resolved = AudioDeviceSelector.resolve(
            availableDevices: [],
            persistedDeviceID: mic.id,
            systemDefaultDeviceID: usb.id
        )

        #expect(resolved == nil)
    }
}

// Exercises the pure connection state machine backing the disconnected
// indicator (ticket #4, ADR 0006): the active device disappearing from the
// available set must transition to `.disconnected`, never silently
// reassign to a different device.
struct DeviceConnectionStateTests {

    @Test func activeDeviceDisappearingTransitionsToDisconnected() {
        let state = DeviceConnectionState.running(deviceID: "usb-interface")

        let next = state.handlingDeviceListChange(availableDeviceIDs: ["built-in-mic"])

        #expect(next == .disconnected(deviceID: "usb-interface"))
    }

    @Test func activeDeviceStillPresentStaysRunning() {
        let state = DeviceConnectionState.running(deviceID: "usb-interface")

        let next = state.handlingDeviceListChange(availableDeviceIDs: ["usb-interface", "built-in-mic"])

        #expect(next == .running(deviceID: "usb-interface"))
    }

    @Test func stoppedIsUnaffectedByDeviceListChanges() {
        let state = DeviceConnectionState.stopped

        let next = state.handlingDeviceListChange(availableDeviceIDs: [])

        #expect(next == .stopped)
    }

    @Test func selectingADeviceAlwaysTransitionsToRunning() {
        let disconnected = DeviceConnectionState.disconnected(deviceID: "usb-interface")

        let next = disconnected.selecting(deviceID: "built-in-mic")

        #expect(next == .running(deviceID: "built-in-mic"))
    }

    @Test func stoppingAlwaysTransitionsToStopped() {
        let running = DeviceConnectionState.running(deviceID: "usb-interface")

        #expect(running.stopping() == .stopped)
    }

    @Test func disconnectedDeviceReappearingTransitionsBackToRunning() {
        // AC: "Reconnecting ... resumes capture" -- distinct from the
        // manual-reselection AC covered by selectingADeviceAlwaysTransitionsToRunning.
        let state = DeviceConnectionState.disconnected(deviceID: "usb-interface")

        let next = state.handlingDeviceListChange(availableDeviceIDs: ["usb-interface"])

        #expect(next == .running(deviceID: "usb-interface"))
    }

    @Test func disconnectedDeviceStillMissingStaysDisconnected() {
        let state = DeviceConnectionState.disconnected(deviceID: "usb-interface")

        let next = state.handlingDeviceListChange(availableDeviceIDs: ["built-in-mic"])

        #expect(next == .disconnected(deviceID: "usb-interface"))
    }

    // ticket #17: picking a device only starts capture from an active state.
    @Test func pickWhileStoppedOnlySelectsAndDoesNotStart() {
        #expect(DeviceConnectionState.stopped.pickStartsCapture == false)
    }

    @Test func pickWhileRunningRestartsCapture() {
        #expect(DeviceConnectionState.running(deviceID: "usb-interface").pickStartsCapture == true)
    }

    @Test func pickWhileDisconnectedResumesCapture() {
        #expect(DeviceConnectionState.disconnected(deviceID: "usb-interface").pickStartsCapture == true)
    }
}

// Exercises the Input Device plate label (ticket #23): the stopped state
// must preview the device a Start would use rather than showing an alarming
// "No Input Device", without silently previewing a fallback when the
// selected device has disconnected.
struct InputDevicePlateLabelTests {
    private let mic = AudioDevice(id: "built-in-mic", name: "MacBook Pro Microphone")
    private let usb = AudioDevice(id: "usb-interface", name: "Scarlett 2i2")

    @Test func runningShowsSelectedDeviceAsActive() {
        let label = InputDevicePlateLabel.resolve(
            isCapturing: true, selectedDeviceID: usb.id,
            resolvedDefaultID: mic.id, availableDevices: [mic, usb]
        )
        #expect(label == .active(name: usb.name))
    }

    @Test func stoppedWithNoSelectionPreviewsResolvedDefault() {
        // Fresh launch: nothing explicitly selected, so the plate previews
        // the device the next Start would capture from (the mic), dimmed --
        // never "No Input Device" while a mic is available.
        let label = InputDevicePlateLabel.resolve(
            isCapturing: false, selectedDeviceID: nil,
            resolvedDefaultID: mic.id, availableDevices: [mic, usb]
        )
        #expect(label == .preview(name: mic.name))
    }

    @Test func stoppedWithSelectionPreviewsSelectedDevice() {
        // Picked-while-stopped (#17) or stopped-after-running: the explicit
        // choice wins over the resolved default.
        let label = InputDevicePlateLabel.resolve(
            isCapturing: false, selectedDeviceID: usb.id,
            resolvedDefaultID: mic.id, availableDevices: [mic, usb]
        )
        #expect(label == .preview(name: usb.name))
    }

    @Test func disconnectedSelectionDoesNotPreviewAFallback() {
        // The selected device has disconnected (still selected, ADR 0006 =
        // no silent fallback). It's not in availableDevices, and because a
        // device *is* selected the resolved-default fallback must not fire --
        // resolve to .none, matching the honest DISCONNECTED reading.
        let label = InputDevicePlateLabel.resolve(
            isCapturing: false, selectedDeviceID: usb.id,
            resolvedDefaultID: mic.id, availableDevices: [mic]
        )
        #expect(label == .unavailable)
    }

    @Test func noDevicesAtAllResolvesToUnavailable() {
        let label = InputDevicePlateLabel.resolve(
            isCapturing: false, selectedDeviceID: nil,
            resolvedDefaultID: nil, availableDevices: []
        )
        #expect(label == .unavailable)
    }
}
