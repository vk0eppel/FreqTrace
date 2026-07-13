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
}
