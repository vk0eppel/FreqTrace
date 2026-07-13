//
//  SignalGeneratorRenderState.swift
//  FreqTrace
//
//  The thread-safety seam between the main-actor UI (which sets waveform
//  and level) and the AVAudioSourceNode render block (which runs on the
//  real-time audio thread and must never block on a UI-thread lock, take
//  the main actor, or allocate). An OSAllocatedUnfairLock-guarded snapshot
//  is written from the UI and read once per render callback; the
//  SignalGeneratorCore itself is only ever touched from the render thread,
//  so it needs no locking of its own.
//
//  Not unit-tested directly (it's a thin AVAudioEngine-facing shim around
//  the pure, tested SignalGeneratorCore) -- see SignalGeneratorCoreTests
//  for the math this wraps, and the ticket #9 report for what still needs
//  manual on-hardware verification.
//

import AVFoundation
import os

final class SignalGeneratorRenderState: @unchecked Sendable {
    private struct Snapshot {
        var waveform: Waveform
        var amplitude: Double
    }

    private var core: SignalGeneratorCore<SystemRandomNumberGenerator>
    private let snapshot: OSAllocatedUnfairLock<Snapshot>

    init(sampleRate: Double) {
        core = SignalGeneratorCore(sampleRate: sampleRate)
        snapshot = OSAllocatedUnfairLock(initialState: Snapshot(waveform: .sine, amplitude: 0))
    }

    /// Called from the main actor whenever the waveform or level changes.
    func update(waveform: Waveform, amplitude: Double) {
        snapshot.withLock { $0 = Snapshot(waveform: waveform, amplitude: amplitude) }
    }

    /// The AVAudioSourceNode render block. Runs on the real-time audio
    /// thread -- must stay lock-free beyond the single fixed-cost snapshot
    /// read below.
    func render(
        isSilence: UnsafeMutablePointer<ObjCBool>,
        timestamp: UnsafePointer<AudioTimeStamp>,
        frameCount: AVAudioFrameCount,
        audioBufferList: UnsafeMutablePointer<AudioBufferList>
    ) -> OSStatus {
        let current = snapshot.withLock { $0 }
        isSilence.pointee = ObjCBool(current.amplitude == 0)

        let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
        for frame in 0..<Int(frameCount) {
            let sample = Float(core.nextSample(waveform: current.waveform, amplitude: current.amplitude))
            for buffer in buffers {
                guard let data = buffer.mData else { continue }
                data.assumingMemoryBound(to: Float.self)[frame] = sample
            }
        }
        return noErr
    }
}
