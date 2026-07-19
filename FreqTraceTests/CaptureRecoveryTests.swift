//
//  CaptureRecoveryTests.swift
//  FreqTraceTests
//
//  Locks down the preemptive capture-recovery logic (the fix for the
//  "capture doesn't start / hangs for a really long time" report): when a
//  synchronous coreaudiod call inside AVAudioEngine.start() wedges for
//  seconds, AudioPipelineViewModel must ABANDON that engine and rebuild a
//  fresh one rather than wait on a call that ignores cancellation.
//
//  The raw HAL blocking is hardware-only and stays untested; the orchestration
//  around it (deadline -> abandon -> rebuild -> retry) is driven here with a
//  fake CaptureEngine, no mic needed. This is the "correct seam" the diagnosis
//  plan called for -- without it, recovery blocking behind a wedged start
//  (the original bug) is untestable.
//

import Testing
import CoreAudio
import Synchronization
@testable import FreqTrace

/// Scriptable stand-in for MicrophoneCaptureEngine. `deactivate()` (the
/// abandonment signal) is recorded via an atomic so the test can assert the
/// wedged engine was actually gated off.
final class FakeCaptureEngine: CaptureEngine, @unchecked Sendable {
    enum Behavior: Sendable {
        /// Returns the given sample rate immediately (healthy start).
        case succeed(Double)
        /// Blocks well past the test deadline -- stands in for a wedged
        /// synchronous coreaudiod call (never returns before it's abandoned).
        case wedge
        /// Throws immediately -- a genuinely unstartable device.
        case fail
    }

    let behavior: Behavior
    let wasDeactivated = Atomic<Bool>(false)
    private let startCount = Atomic<Int>(0)
    var startCalls: Int { startCount.load(ordering: .relaxed) }

    init(_ behavior: Behavior) { self.behavior = behavior }

    struct FakeStartError: Error {}

    @discardableResult
    func start(deviceID: AudioDeviceID?) async throws -> Double {
        startCount.add(1, ordering: .relaxed)
        switch behavior {
        case .succeed(let rate):
            return rate
        case .fail:
            throw FakeStartError()
        case .wedge:
            // Far longer than any test deadline; the view model abandons us
            // before this returns. (A real wedge is synchronous/un-cancellable;
            // a sleep is a faithful enough "doesn't return in time" for the
            // recovery orchestration under test.)
            try? await Task.sleep(for: .seconds(30))
            return 48_000
        }
    }

    func stop() async {}
    var engineIsRunning: Bool { false }
    func setConfigurationChangeHandler(_ handler: @escaping @Sendable () -> Void) async {}
    nonisolated func deactivate() { wasDeactivated.store(true, ordering: .relaxed) }
}

@MainActor
struct CaptureRecoveryTests {

    /// A start whose first engine wedges is abandoned at the deadline and
    /// retried on a fresh engine, which succeeds -- the whole point: recovery
    /// does not block on the un-cancellable wedged call.
    @Test func wedgedStartIsAbandonedAndRebuilt() async throws {
        let wedged = FakeCaptureEngine(.wedge)
        let healthy = FakeCaptureEngine(.succeed(44_100))
        let engines: [any CaptureEngine] = [wedged, healthy]
        let next = Atomic<Int>(0)

        let vm = AudioPipelineViewModel(startDeadline: .milliseconds(80)) { _ in
            let i = next.load(ordering: .relaxed)
            next.add(1, ordering: .relaxed)
            return engines[i]
        }

        let rate = try await vm.startEngineWithRecovery(coreAudioDeviceID: nil, generation: 0)

        #expect(rate == 44_100)
        #expect(wedged.wasDeactivated.load(ordering: .relaxed) == true)
        #expect(healthy.wasDeactivated.load(ordering: .relaxed) == false)
    }

    /// A healthy start returns immediately, on the first engine, with no
    /// rebuild and no deactivation.
    @Test func healthyStartDoesNotRebuild() async throws {
        let healthy = FakeCaptureEngine(.succeed(48_000))
        let vm = AudioPipelineViewModel(startDeadline: .seconds(5)) { _ in healthy }

        let rate = try await vm.startEngineWithRecovery(coreAudioDeviceID: nil, generation: 0)

        #expect(rate == 48_000)
        #expect(healthy.startCalls == 1)
        #expect(healthy.wasDeactivated.load(ordering: .relaxed) == false)
    }

    /// If every rebuild wedges, recovery gives up (throws) rather than looping
    /// forever -- bounded by maxStartAttempts.
    @Test func persistentWedgeGivesUp() async throws {
        let vm = AudioPipelineViewModel(startDeadline: .milliseconds(40)) { _ in
            FakeCaptureEngine(.wedge)
        }

        await #expect(throws: (any Error).self) {
            try await vm.startEngineWithRecovery(coreAudioDeviceID: nil, generation: 0)
        }
    }
}
