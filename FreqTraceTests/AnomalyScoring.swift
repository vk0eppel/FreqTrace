//
//  AnomalyScoring.swift
//  FreqTraceTests
//
//  The scoring harness for the anomaly-candidate validation corpus (map
//  #18, ticket #34). Turns a case's amplitude envelope into a per-hop
//  magnitude spectrum -- a clean floor with the target bin raised to the
//  envelope's windowed power -- and steps it through the detector
//  synchronously, one hop at a time, so flag latency is an exact hop count.
//  The detector is passed in as a closure so the same harness scores
//  today's AnomalyDetector (the #34 baseline) and, later, the #36 criteria
//  prototype.
//
//  The per-hop power is the mean of the envelope-squared over the window
//  the FFT would see (windowSize samples ending at this hop, zero before
//  the signal starts) -- this models the FFT window's own time integration
//  (a fast ring-up reads smoothed/lagged, exactly as through a real
//  windowed FFT) without the roundoff-peak artifact a synthetic tone
//  through the real FFT would introduce (see AnomalyCorpus.swift).
//
//  Latency is measured from the moment the target first becomes a findable
//  narrowband peak (PeakFinder would return it) -- not from signal start --
//  so it isolates detector latency from how long a ring took to climb into
//  view, matching the corpus spec's "within ~500 ms of becoming a sustained
//  narrowband peak."
//
//  Convention (CLAUDE.md): pure value types are nonisolated.
//

import Foundation
@testable import FreqTrace

/// The outcome of scoring one case against one detector.
nonisolated struct CaseScore: Sendable {
    let number: Int
    let name: String
    let expectation: CorpusExpectation

    /// Was the target frequency flagged in any hop?
    let flaggedTargetEver: Bool
    /// Was the target flagged in the final few hops? (Case 6's "clears once
    /// settled" check.)
    let flaggedTargetAtEnd: Bool
    /// Hop at which the target first became a findable peak, if ever.
    let firstDetectableHop: Int?
    /// Hop at which the target was first flagged, if ever.
    let firstFlagHop: Int?
    /// Detector latency: firstFlag - firstDetectable, in ms. `nil` if never
    /// flagged or never detectable.
    let flagLatencyMs: Double?
    /// Total hops in the run.
    let hopCount: Int

    /// Did the detector meet the case's expectation (incl. mustClearByEnd)?
    let verdict: Bool
    /// Human-readable reason the verdict came out as it did.
    let detail: String
}

/// Builds a per-hop process closure over today's `AnomalyDetector`, owning
/// its mutable state across hops -- the #34 baseline, and the same closure
/// shape the #36 criteria prototype will provide to the same harness.
nonisolated enum BaselineDetector {
    static func makeProcess(config: AnalysisConfig) -> (_ magnitudes: [Float]) -> [AnomalyCandidate] {
        var detector = AnomalyDetector()
        return { detector.process(magnitudes: $0, config: config) }
    }
}

extension CorpusExpectation {
    /// The scorecard's short column label -- kept next to the enum's meaning
    /// so the renderer doesn't re-destructure it.
    var shortLabel: String {
        switch self {
        case .mustNotFlag: "must-not"
        case .mustFlag(let withinMs): withinMs == nil ? "must-flag*" : "must-flag"
        }
    }
}

nonisolated struct CorpusScorer {
    let config: AnalysisConfig
    /// How many trailing hops count as "the end" for the mustClearByEnd check.
    let endWindowHops: Int
    /// Flat spectral floor (power) the non-target bins sit at, matching the
    /// AnomalyDetectionTests convention -- low enough that a moderate tone
    /// stands far above PeakFinder's 6 dB prominence gate.
    let floorPower: Float
    /// The level (dBFS) at which the target counts as "a findable narrowband
    /// peak" for the latency measurement. `nil` = the #34 default (PeakFinder
    /// on the synthetic spectrum, which fires as soon as the tone clears the
    /// 1e-8 floor -- detectable almost immediately). Setting a realistic
    /// value (e.g. -25 dBFS) makes latency measure real climb-into-view time,
    /// which the ~500 ms bar actually gates -- the upgrade the #34 baseline
    /// doc flagged for #36.
    let detectabilityFloorDb: Float?

    init(config: AnalysisConfig, endWindowHops: Int = 5, floorPower: Float = 1e-8, detectabilityFloorDb: Float? = nil) {
        self.config = config
        self.endWindowHops = endWindowHops
        self.floorPower = floorPower
        self.detectabilityFloorDb = detectabilityFloorDb
    }

    /// A candidate/peak matches the target within a couple bins or 3%,
    /// whichever is wider -- covers FFT bin quantization and sub-bin drift.
    private func matches(_ hz: Double, _ target: Double) -> Bool {
        let tol = max(target * 0.03, 2 * config.binResolutionHz)
        return abs(hz - target) <= tol
    }

    /// The FFT bin the case's target tone lands in.
    private func targetBin(for testCase: CorpusCase) -> Int {
        Int((testCase.targetHz / config.binResolutionHz).rounded())
    }

    /// The magnitude spectrum the FFT would produce at `hop`: a flat floor
    /// with the target bin raised to the envelope's mean power over the
    /// windowSize samples ending at this hop (zero before the signal
    /// starts), i.e. amplitude^2 averaged over the window -- the windowed
    /// power a real FFT integrates.
    func spectrum(for testCase: CorpusCase, hop: Int) -> [Float] {
        let binCount = config.windowSize / 2
        let targetBin = targetBin(for: testCase)
        var magnitudes = [Float](repeating: floorPower, count: binCount)
        guard targetBin > 0, targetBin < binCount else { return magnitudes }

        let windowEnd = (hop + 1) * config.hopSize
        let windowStart = windowEnd - config.windowSize
        var sumSq: Double = 0
        for idx in windowStart..<windowEnd {
            guard idx >= 0 else { continue }
            let t = Double(idx) / config.sampleRate
            guard t < testCase.durationSec else { continue }
            let a = Double(testCase.envelope(t))
            sumSq += a * a
        }
        let power = Float(sumSq / Double(config.windowSize))
        magnitudes[targetBin] = max(power, floorPower)
        return magnitudes
    }

    /// Runs one case through `process` (which owns the detector's mutable
    /// state across hops) and scores it.
    func score(
        _ testCase: CorpusCase,
        process: (_ magnitudes: [Float]) -> [AnomalyCandidate]
    ) -> CaseScore {
        let hopDurationMs = Double(config.hopSize) / config.sampleRate * 1000
        let totalSamples = Int(testCase.durationSec * config.sampleRate)
        let hopCount = max(0, totalSamples / config.hopSize)

        var firstDetectableHop: Int?
        var firstFlagHop: Int?
        var flaggedHops: Set<Int> = []

        for hop in 0..<hopCount {
            let magnitudes = spectrum(for: testCase, hop: hop)

            if firstDetectableHop == nil {
                if let floorDb = detectabilityFloorDb {
                    let bin = targetBin(for: testCase)
                    if bin > 0, bin < magnitudes.count,
                       MagnitudeScaling.decibels(power: magnitudes[bin]) >= floorDb {
                        firstDetectableHop = hop
                    }
                } else {
                    let peaks = PeakFinder.findPeaks(magnitudes: magnitudes, config: config)
                    if peaks.contains(where: { matches($0.frequencyHz, testCase.targetHz) }) {
                        firstDetectableHop = hop
                    }
                }
            }

            let candidates = process(magnitudes)
            if candidates.contains(where: { matches($0.frequencyHz, testCase.targetHz) }) {
                flaggedHops.insert(hop)
                if firstFlagHop == nil { firstFlagHop = hop }
            }
        }

        let flaggedEver = firstFlagHop != nil
        let endThreshold = hopCount - endWindowHops
        let flaggedAtEnd = flaggedHops.contains { $0 >= endThreshold }

        let latencyMs: Double? = {
            guard let flag = firstFlagHop, let detect = firstDetectableHop else { return nil }
            return Double(flag - detect) * hopDurationMs
        }()

        let (verdict, detail) = evaluate(
            testCase,
            flaggedEver: flaggedEver,
            flaggedAtEnd: flaggedAtEnd,
            latencyMs: latencyMs
        )

        return CaseScore(
            number: testCase.number,
            name: testCase.name,
            expectation: testCase.expectation,
            flaggedTargetEver: flaggedEver,
            flaggedTargetAtEnd: flaggedAtEnd,
            firstDetectableHop: firstDetectableHop,
            firstFlagHop: firstFlagHop,
            flagLatencyMs: latencyMs,
            hopCount: hopCount,
            verdict: verdict,
            detail: detail
        )
    }

    private func evaluate(
        _ testCase: CorpusCase,
        flaggedEver: Bool,
        flaggedAtEnd: Bool,
        latencyMs: Double?
    ) -> (Bool, String) {
        switch testCase.expectation {
        case .mustNotFlag:
            return flaggedEver
                ? (false, "flagged, but must-not-flag")
                : (true, "correctly never flagged")

        case let .mustFlag(withinMs):
            guard flaggedEver else {
                return (false, "never flagged, but must-flag")
            }
            if testCase.mustClearByEnd && flaggedAtEnd {
                return (false, "flagged while building (good) but did not clear once settled")
            }
            if let target = withinMs {
                guard let latency = latencyMs else {
                    return (false, "flagged but latency undefined (never became a detectable peak)")
                }
                if latency > target {
                    return (false, String(format: "flagged, but %.0f ms > %.0f ms target", latency, target))
                }
                return (true, String(format: "flagged within %.0f ms", latency))
            }
            return (true, "flagged (no latency target)")
        }
    }

    /// Scores every case against a freshly-constructed detector per case.
    func scoreAll(
        cases: [CorpusCase],
        makeProcess: () -> (_ magnitudes: [Float]) -> [AnomalyCandidate]
    ) -> [CaseScore] {
        cases.map { score($0, process: makeProcess()) }
    }
}

// MARK: Scorecard rendering

nonisolated enum Scorecard {
    /// A fixed-width table for the baseline record (printed by the baseline
    /// test; captured into docs/research/anomaly-corpus-baseline.md).
    static func render(_ scores: [CaseScore]) -> String {
        func pad(_ s: String, _ width: Int) -> String {
            s.count >= width ? s : s + String(repeating: " ", count: width - s.count)
        }

        var lines: [String] = []
        lines.append(pad("case", 5) + pad("expect", 12) + pad("flagged", 9) + pad("latency", 10) + pad("verdict", 9) + "detail")
        lines.append(String(repeating: "-", count: 5 + 12 + 9 + 10 + 9 + 30))
        for s in scores {
            let expect = s.expectation.shortLabel
            let latency = s.flagLatencyMs.map { String(format: "%.0f ms", $0) } ?? "--"
            let verdict = s.verdict ? "PASS" : "FAIL"
            lines.append(
                pad(String(s.number), 5)
                    + pad(expect, 12)
                    + pad(s.flaggedTargetEver ? "yes" : "no", 9)
                    + pad(latency, 10)
                    + pad(verdict, 9)
                    + s.detail
            )
        }
        let passed = scores.filter(\.verdict).count
        lines.append("")
        lines.append("\(passed)/\(scores.count) pass  (* = no latency target: caught via the memory/loudness path)")
        return lines.joined(separator: "\n")
    }
}
