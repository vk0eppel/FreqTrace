//
//  FreezeGateTests.swift
//  FreqTraceTests
//
//  Exercises the pure buffering logic behind Freeze (ticket #13, CONTEXT.md
//  "Freeze"): while frozen, values are held silently instead of published;
//  unfreezing releases only the most recently held value immediately
//  (instant catch-up), never a queued replay of everything received while
//  frozen. Independent of AudioPipelineViewModel/SwiftUI -- see
//  InputDeviceTests.swift for this project's pure-logic test style.
//

import Testing
@testable import FreqTrace

struct FreezeGateTests {

    @Test func receivingWhileNotFrozenPassesThroughImmediately() {
        var gate = FreezeGate<Int>()

        let published = gate.receive(1)

        #expect(published == 1)
    }

    @Test func receivingWhileFrozenHoldsSilently() {
        var gate = FreezeGate<Int>()
        gate.freeze()

        let published = gate.receive(1)

        #expect(published == nil)
    }

    @Test func unfreezingReleasesMostRecentlyHeldValueImmediately() {
        var gate = FreezeGate<Int>()
        gate.freeze()
        _ = gate.receive(1)
        _ = gate.receive(2)
        _ = gate.receive(3)

        let released = gate.unfreeze()

        #expect(released == 3)
    }

    @Test func unfreezingWithNoValuesReceivedWhileFrozenReleasesNothing() {
        var gate = FreezeGate<Int>()
        gate.freeze()

        let released = gate.unfreeze()

        #expect(released == nil)
    }

    @Test func freezingWhileAlreadyFrozenIsANoOp() {
        var gate = FreezeGate<Int>()
        gate.freeze()
        _ = gate.receive(1)
        gate.freeze()

        let released = gate.unfreeze()

        #expect(released == 1)
    }

    @Test func unfreezingWhileAlreadyUnfrozenIsANoOp() {
        var gate = FreezeGate<Int>()

        let released = gate.unfreeze()

        #expect(released == nil)
    }

    @Test func receivingAfterUnfreezingPassesThroughImmediatelyAgain() {
        var gate = FreezeGate<Int>()
        gate.freeze()
        _ = gate.receive(1)
        _ = gate.unfreeze()

        let published = gate.receive(2)

        #expect(published == 2)
    }
}
