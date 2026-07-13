//
//  TimeAveragingTests.swift
//  FreqTraceTests
//
//  Exercises TimeAveragingBlender, the pure post-FFT frame-blending seam
//  behind Time Averaging (ticket #7, CONTEXT.md "Time Averaging"): a
//  Fast/Slow preset that changes how quickly Tracked Frequency's magnitude
//  input responds to level changes, independent of FFT window
//  size/frequency resolution (this operates on an already-computed
//  magnitude spectrum, never touching FrequencyTracker's FFT setup).
//

import Testing
@testable import FreqTrace

struct TimeAveragingTests {

    @Test func fastPassesEachFrameThroughUnchanged() {
        var blender = TimeAveragingBlender()
        let first = blender.blend([1, 1, 1], preset: .fast)
        let second = blender.blend([5, 5, 5], preset: .fast)

        #expect(first == [1, 1, 1])
        #expect(second == [5, 5, 5]) // no lag from the first frame at all
    }

    @Test func slowLagsBehindAStepChange() {
        var blender = TimeAveragingBlender()
        _ = blender.blend([1, 1, 1], preset: .slow)
        let afterStep = blender.blend([5, 5, 5], preset: .slow)

        // Should move toward 5 but not reach it in a single frame.
        #expect(afterStep[0] > 1)
        #expect(afterStep[0] < 5)
    }

    @Test func slowGraduallyConvergesTowardASustainedNewLevel() {
        var blender = TimeAveragingBlender()
        _ = blender.blend([0, 0, 0], preset: .slow)
        var previous: Float = 0
        for _ in 0..<20 {
            let result = blender.blend([10, 10, 10], preset: .slow)
            #expect(result[0] >= previous) // monotonically approaches, never overshoots/oscillates
            previous = result[0]
        }
        #expect(previous > 9) // converged close to the sustained level after enough frames
    }

    @Test func firstFrameHasNothingToBlendAgainstSoItPassesThroughRegardlessOfPreset() {
        var blender = TimeAveragingBlender()
        let first = blender.blend([3, 3, 3], preset: .slow)

        #expect(first == [3, 3, 3])
    }
}
