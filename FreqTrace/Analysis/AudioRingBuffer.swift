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
    /// to `count` samples in, overwriting the oldest slots if the reader
    /// hasn't kept up, rather than blocking.
    ///
    /// Single-writer discipline: this is the *only* place `writeIndex` is
    /// written, and it never touches `readIndex` -- an earlier version had
    /// both write() and read() racing to mutate readIndex independently,
    /// which could let a reader's store clobber a writer's overflow-advance
    /// with a stale value, un-dropping data that had already been
    /// physically overwritten. read() now detects and resyncs past an
    /// overwrite itself instead.
    func write(_ samples: UnsafePointer<Float>, count: Int) {
        guard count > 0 else { return }
        let w = writeIndex.load(ordering: .relaxed)
        let writeCount = min(count, capacity)
        let sourceOffset = count - writeCount

        for i in 0..<writeCount {
            storage[(w + i) % capacity] = samples[sourceOffset + i]
        }

        writeIndex.store(w + writeCount, ordering: .releasing)
    }

    /// Called from the consumer (AudioAnalysisPipeline actor). All-or-
    /// nothing: returns `count` if that many samples were available, or `0`
    /// otherwise -- it does NOT return (and consume) a partial amount.
    /// Single-writer discipline: this is the only place `readIndex` is
    /// written.
    ///
    /// Bug fix (root cause of "16384 [the largest FFT size] still
    /// freezes", found via log instrumentation showing writeIndex and
    /// readIndex locked in perfect step forever): this used to return a
    /// partial read (`min(count, available, buffer.count)`) whenever less
    /// than `count` was available, and -- critically -- still advanced
    /// readIndex by that partial amount, discarding it. AudioAnalysisPipeline.
    /// pollLoop's only caller only ever treats `read == config.hopSize`
    /// (an exact match) as success; a partial return was already being
    /// thrown away by the caller, but the samples themselves were also
    /// gone from the buffer, unable to accumulate toward a future full
    /// read. MicrophoneCaptureEngine's tap delivers ~4800 frames per
    /// callback; every hopSize <= that (every FFTWindowSize except the
    /// largest, whose hopSize is 8192) always had enough available in a
    /// single write to satisfy one full read outright, so the partial-read
    /// path was rarely hit in practice. hopSize=8192 needs roughly two tap
    /// deliveries' worth -- but each time pollLoop polled in between, it
    /// would immediately drain and discard whatever partial amount had
    /// trickled in so far, so the two deliveries could never accumulate:
    /// readIndex chased writeIndex forever, never falling behind by a full
    /// hop.
    func read(into buffer: inout [Float], count: Int) -> Int {
        let w = writeIndex.load(ordering: .acquiring)
        var r = readIndex.load(ordering: .relaxed)

        // If the producer has written more than `capacity` samples since our
        // last read, it has lapped us -- the oldest unread slots are already
        // physically overwritten. Resync forward rather than reading stale
        // data. Safe because only this method ever writes readIndex.
        if w - r > capacity {
            r = w - capacity
        }

        let available = max(0, w - r)
        guard count <= buffer.count, available >= count else { return 0 }

        for i in 0..<count {
            buffer[i] = storage[(r + i) % capacity]
        }

        readIndex.store(r + count, ordering: .releasing)
        return count
    }
}
