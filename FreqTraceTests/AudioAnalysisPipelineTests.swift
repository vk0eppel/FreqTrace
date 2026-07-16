//
//  AudioAnalysisPipelineTests.swift
//  FreqTraceTests
//
//  Integration harness for the pipeline actor itself: a synthetic
//  producer writes a known tone into a real AudioRingBuffer and the test
//  asserts AudioAnalysisPipeline actually delivers hops from it -- no
//  AVAudioEngine/microphone involved. Built while diagnosing "nothing
//  starts, nothing shows" after the hop-size cap (FFTWindowSize.hopSize):
//  the watchdog log showed capture starting but zero hops ever arriving,
//  and this seam separates "pipeline logic broke" from "capture tap broke"
//  deterministically.
//

import Foundation
import Testing
@testable import FreqTrace

struct AudioAnalysisPipelineTests {

    /// One second of a full-scale 1kHz tone, written up front -- enough for
    /// ~23 hops at the default config, so the pipeline should deliver
    /// results immediately if its read/window/FFT plumbing is sound.
    @Test func deliversHopsAtTheDefaultConfig() async throws {
        let config = AnalysisConfig.default
        let ringBuffer = AudioRingBuffer(capacity: Int(config.sampleRate) * 2)
        let samples = FrequencyTracker.sineWave(frequency: 1000, sampleRate: config.sampleRate, count: Int(config.sampleRate))
        samples.withUnsafeBufferPointer { pointer in
            ringBuffer.write(pointer.baseAddress!, count: pointer.count)
        }

        let pipeline = AudioAnalysisPipeline(config: config, ringBuffer: ringBuffer, weighting: .z)
        let stream = await pipeline.start()

        // Race the consumer against a timeout so a wedged pipeline fails
        // the test instead of hanging the suite.
        let received = await withTaskGroup(of: Int.self) { group in
            group.addTask {
                var count = 0
                for await result in stream {
                    #expect(abs(result.trackedFrequencyHz - 1000) <= config.binResolutionHz * 2)
                    count += 1
                    if count >= 5 { break }
                }
                return count
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                return -1
            }
            let winner = await group.next() ?? -1
            group.cancelAll()
            return winner
        }
        await pipeline.stop()

        #expect(received >= 5, "pipeline delivered no hops within the timeout")
    }

    /// Same harness at every selectable FFT size -- the hop cap means the
    /// window/hop relationship now differs per size (50% overlap below
    /// 4096, more overlap above), and all of them must deliver.
    @Test(arguments: FFTWindowSize.allCases)
    func deliversHopsAtEveryWindowSize(_ size: FFTWindowSize) async throws {
        let config = size.config(sampleRate: 48_000)
        let ringBuffer = AudioRingBuffer(capacity: Int(config.sampleRate) * 2)
        let samples = FrequencyTracker.sineWave(frequency: 1000, sampleRate: config.sampleRate, count: Int(config.sampleRate))
        samples.withUnsafeBufferPointer { pointer in
            ringBuffer.write(pointer.baseAddress!, count: pointer.count)
        }

        let pipeline = AudioAnalysisPipeline(config: config, ringBuffer: ringBuffer, weighting: .z)
        let stream = await pipeline.start()

        let received = await withTaskGroup(of: Int.self) { group in
            group.addTask {
                var count = 0
                for await _ in stream {
                    count += 1
                    if count >= 3 { break }
                }
                return count
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                return -1
            }
            let winner = await group.next() ?? -1
            group.cancelAll()
            return winner
        }
        await pipeline.stop()

        #expect(received >= 3, "pipeline delivered no hops within the timeout at window size \(size.rawValue)")
    }
}
