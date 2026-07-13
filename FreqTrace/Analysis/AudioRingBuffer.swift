//
//  AudioRingBuffer.swift
//  FreqTrace
//
//  The seam between the real-time audio thread (MicrophoneCaptureEngine's
//  tap callback, which may only do minimal, non-blocking, non-allocating
//  work) and the background actor that runs FFT/tracking (see CLAUDE.md
//  "Architecture" / ADR 0002). Single-producer/single-consumer: the audio
//  thread calls write(), the AudioAnalysisPipeline actor calls read().
//  Lock-free via the stdlib Synchronization module's Atomic type -- no
//  locks, no allocation, no Objective-C runtime calls on the real-time path.
//
//  If the reader falls behind (consumer slower than producer), write()
//  simply drops the oldest unread samples rather than blocking the audio
//  thread -- blocking or growing here would risk an audio glitch, which is
//  worse than a momentary gap in the analysis.
//

import Synchronization

// This module defaults new types to @MainActor isolation
// (SWIFT_DEFAULT_ACTOR_ISOLATION), but write() must run synchronously on the
// real-time audio thread, not hop to the main actor -- so this type opts out
// explicitly.
nonisolated final class AudioRingBuffer: @unchecked Sendable {
    private let capacity: Int
    private let storage: UnsafeMutablePointer<Float>
    private let writeIndex = Atomic<Int>(0)
    private let readIndex = Atomic<Int>(0)

    init(capacity: Int) {
        precondition(capacity > 0, "AudioRingBuffer capacity must be positive")
        self.capacity = capacity
        storage = .allocate(capacity: capacity)
        storage.initialize(repeating: 0, count: capacity)
    }

    deinit {
        storage.deallocate()
    }

    /// Real-time-safe: called from the AVAudioEngine tap callback. Copies up
    /// to `count` samples in; if the buffer is full (reader hasn't kept up),
    /// the oldest unread samples are dropped to make room rather than
    /// blocking.
    func write(_ samples: UnsafePointer<Float>, count: Int) {
        guard count > 0 else { return }
        let w = writeIndex.load(ordering: .relaxed)
        var r = readIndex.load(ordering: .acquiring)

        let writeCount = min(count, capacity)
        let sourceOffset = count - writeCount

        // Make room by advancing the read cursor past whatever this write
        // would otherwise overwrite. This only matters when the consumer
        // has fallen behind; the consumer's own read() still uses acquire
        // ordering, so it never sees torn data -- worst case it reads a
        // shorter run than it expected.
        let used = w - r
        let overflow = used + writeCount - capacity
        if overflow > 0 {
            r += overflow
        }

        for i in 0..<writeCount {
            storage[(w + i) % capacity] = samples[sourceOffset + i]
        }

        readIndex.store(r, ordering: .relaxed)
        writeIndex.store(w + writeCount, ordering: .releasing)
    }

    /// Called from the consumer (AudioAnalysisPipeline actor). Returns the
    /// number of samples actually read, which may be less than `count` if
    /// not enough data has been written yet.
    func read(into buffer: inout [Float], count: Int) -> Int {
        let w = writeIndex.load(ordering: .acquiring)
        let r = readIndex.load(ordering: .relaxed)

        let available = max(0, w - r)
        let readCount = min(count, available, buffer.count)
        guard readCount > 0 else { return 0 }

        for i in 0..<readCount {
            buffer[i] = storage[(r + i) % capacity]
        }

        readIndex.store(r + readCount, ordering: .releasing)
        return readCount
    }
}
