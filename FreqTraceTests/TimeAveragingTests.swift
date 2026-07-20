//
//  TimeAveragingTests.swift
//  FreqTraceTests
//
//  Exercises TimeAveragingBlender, the pure post-FFT frame-blending seam
//  behind Time Averaging (ticket #7, CONTEXT.md "Time Averaging"): a
//  Fast/Slow preset that changes how quickly Tracked Frequency's magnitude
//  input responds to level changes. Fast/Slow are real time constants
//  (125 ms / 1 s) derived from the hop duration, so the smoothing is the
//  same wall-clock time at every FFT size -- the property the last test
//  pins down.
//

import Testing
@testable import FreqTrace

struct TimeAveragingTests {

    // Representative hop durations at 48 kHz: hopSize = min(windowSize/2, 2048).
    private let smallHop = 512.0 / 48_000   // 1024-pt FFT (~10.7 ms)
    private let largeHop = 2048.0 / 48_000  // >=4096-pt FFT (~42.7 ms)

    @Test func firstFrameHasNothingToBlendAgainstSoItPassesThroughRegardlessOfPreset() {
        var blender = TimeAveragingBlender()
        let first = blender.blend([3, 3, 3], preset: .slow, hopDuration: largeHop)

        #expect(first == [3, 3, 3])
    }

    @Test func fastAppliesLightSmoothingButRespondsFasterThanSlow() {
        var fast = TimeAveragingBlender()
        var slow = TimeAveragingBlender()
        _ = fast.blend([0, 0, 0], preset: .fast, hopDuration: largeHop)
        _ = slow.blend([0, 0, 0], preset: .slow, hopDuration: largeHop)

        let afterFast = fast.blend([10, 10, 10], preset: .fast, hopDuration: largeHop)[0]
        let afterSlow = slow.blend([10, 10, 10], preset: .slow, hopDuration: largeHop)[0]

        // Fast is no longer a passthrough -- it's a 125 ms time constant, so it
        // still lags a single-frame step...
        #expect(afterFast > 0)
        #expect(afterFast < 10)
        // ...but responds faster than the 1 s Slow constant.
        #expect(afterFast > afterSlow)
    }

    @Test func slowLagsBehindAStepChange() {
        var blender = TimeAveragingBlender()
        _ = blender.blend([1, 1, 1], preset: .slow, hopDuration: largeHop)
        let afterStep = blender.blend([5, 5, 5], preset: .slow, hopDuration: largeHop)

        // Should move toward 5 but not reach it in a single frame.
        #expect(afterStep[0] > 1)
        #expect(afterStep[0] < 5)
    }

    @Test func slowGraduallyConvergesTowardASustainedNewLevel() {
        var blender = TimeAveragingBlender()
        _ = blender.blend([0, 0, 0], preset: .slow, hopDuration: largeHop)
        var previous: Float = 0
        for _ in 0..<200 {
            let result = blender.blend([10, 10, 10], preset: .slow, hopDuration: largeHop)
            #expect(result[0] >= previous) // monotonically approaches, never overshoots/oscillates
            previous = result[0]
        }
        #expect(previous > 9) // converged close to the sustained level after enough time
    }

    /// The point of the time-constant model: the same preset smooths over the
    /// same *wall-clock* time no matter the hop rate (FFT size). Priming both
    /// at 0 then holding a step to 10 for the same elapsed time via a small vs
    /// large hop must land at ~the same value. Goes red on a raw per-frame
    /// weight (which converges far faster at the small hop).
    @Test func smoothingIsTheSameWallClockTimeRegardlessOfHopSize() {
        let elapsedSeconds = 0.5

        func settledValue(hopDuration: Double) -> Float {
            var blender = TimeAveragingBlender()
            _ = blender.blend([0], preset: .slow, hopDuration: hopDuration) // prime baseline
            let hops = Int((elapsedSeconds / hopDuration).rounded())
            var result: [Float] = [0]
            for _ in 0..<hops {
                result = blender.blend([10], preset: .slow, hopDuration: hopDuration)
            }
            return result[0]
        }

        let small = settledValue(hopDuration: smallHop)  // ~47 hops
        let large = settledValue(hopDuration: largeHop)  // ~12 hops

        // Both should sit near 10*(1 - e^-0.5) ≈ 3.93 despite very different
        // hop counts; small rounding of elapsed/hop is the only spread.
        #expect(abs(small - large) < 0.2)
    }
}
