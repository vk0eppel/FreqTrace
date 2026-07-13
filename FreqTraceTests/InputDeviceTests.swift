//
//  InputDeviceTests.swift
//  FreqTraceTests
//
//  Exercises the pure decision logic behind Input Device selection (ticket
//  #4, CONTEXT.md "Input Device"): InputDeviceSelector.resolve picks which
//  device should be active from (available devices, persisted last explicit
//  choice, system default), independent of real Core Audio hardware -- see
//  MicrophoneCaptureEngine.swift for why the hardware glue itself is not
//  unit-tested here.
//

import Testing
@testable import FreqTrace

struct InputDeviceSelectorTests {

    private let mic = AudioDevice(id: "built-in-mic", name: "MacBook Pro Microphone")
    private let usb = AudioDevice(id: "usb-interface", name: "Scarlett 2i2")

    @Test func firstLaunchWithNoPersistedChoiceUsesSystemDefault() {
        let resolved = InputDeviceSelector.resolve(
            availableDevices: [mic, usb],
            persistedDeviceID: nil,
            systemDefaultDeviceID: usb.id
        )

        #expect(resolved == usb.id)
    }

    @Test func persistedChoiceStillAvailableWinsOverSystemDefault() {
        let resolved = InputDeviceSelector.resolve(
            availableDevices: [mic, usb],
            persistedDeviceID: mic.id,
            systemDefaultDeviceID: usb.id
        )

        #expect(resolved == mic.id)
    }

    @Test func persistedChoiceNoLongerAvailableFallsBackToSystemDefault() {
        let resolved = InputDeviceSelector.resolve(
            availableDevices: [usb],
            persistedDeviceID: mic.id,
            systemDefaultDeviceID: usb.id
        )

        #expect(resolved == usb.id)
    }

    @Test func nothingAvailableResolvesToNil() {
        let resolved = InputDeviceSelector.resolve(
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
struct CaptureConnectionStateTests {

    @Test func activeDeviceDisappearingTransitionsToDisconnected() {
        let state = CaptureConnectionState.running(deviceID: "usb-interface")

        let next = state.handlingDeviceListChange(availableDeviceIDs: ["built-in-mic"])

        #expect(next == .disconnected(deviceID: "usb-interface"))
    }

    @Test func activeDeviceStillPresentStaysRunning() {
        let state = CaptureConnectionState.running(deviceID: "usb-interface")

        let next = state.handlingDeviceListChange(availableDeviceIDs: ["usb-interface", "built-in-mic"])

        #expect(next == .running(deviceID: "usb-interface"))
    }

    @Test func stoppedIsUnaffectedByDeviceListChanges() {
        let state = CaptureConnectionState.stopped

        let next = state.handlingDeviceListChange(availableDeviceIDs: [])

        #expect(next == .stopped)
    }

    @Test func selectingADeviceAlwaysTransitionsToRunning() {
        let disconnected = CaptureConnectionState.disconnected(deviceID: "usb-interface")

        let next = disconnected.selecting(deviceID: "built-in-mic")

        #expect(next == .running(deviceID: "built-in-mic"))
    }

    @Test func stoppingAlwaysTransitionsToStopped() {
        let running = CaptureConnectionState.running(deviceID: "usb-interface")

        #expect(running.stopping() == .stopped)
    }
}
