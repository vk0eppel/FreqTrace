//
//  AnomalyDetector.swift
//  FreqTrace
//
//  The Anomaly Candidate detector (ticket #5, ADR 0001, CONTEXT.md
//  "Anomaly Candidate"): flags frequencies as narrowband + harmonically
//  unrelated + sustained over a rolling frame window, without attempting
//  to classify the cause (feedback vs. room resonance) -- ADR 0001
//  deliberately unifies both under one concept for v1. None of the
//  thresholds below are pinned down by the spec; each is a documented
//  judgment call, chosen to behave sensibly against the ACs' synthetic
//  test cases (a sustained pure tone flags, a normal harmonic series
//  doesn't) rather than derived from a formula. Runs on the raw
//  (unweighted) spectrum -- Time Averaging is hardcoded to Fast for this
//  detector (CONTEXT.md "Time Averaging"), i.e. no pre-smoothing at all,
//  since catching a building ring requires the fastest possible response;
//  AnomalyDetector's own sustain window is what "Fast" leaves in charge of
//  responsiveness.
//

import Foundation

/// One narrowband bump in a magnitude spectrum -- not yet judged
/// harmonically-related or sustained, just "louder than its surroundings."
nonisolated struct SpectralPeak: Equatable, Sendable {
    let bin: Int
    let frequencyHz: Double
    let magnitudeDb: Float
}

// This file's types are all nonisolated for the same reason as
// TimeAveraging.swift's: plain value types the AudioAnalysisPipeline
// background actor must call directly, opting out of the module's default
// @MainActor isolation (Swift 6 language-mode error otherwise).
nonisolated enum PeakFinder {
    /// How far above its shoulders (see below) a bin's level must be to
    /// count as narrowband, rather than a broad bump in the spectrum. Not
    /// spec'd -- 6dB comfortably separates a real tone from ordinary
    /// spectral texture in these synthetic tests without demanding an
    /// unrealistically clean signal.
    static let prominenceDb: Float = 6

    /// How many bins away to sample the "shoulder" for the prominence
    /// comparison. Wide enough to sit outside the peak's own main lobe at
    /// this FFT's resolution, narrow enough to still reflect the local
    /// noise floor rather than a distant, unrelated part of the spectrum.
    static let shoulderBinOffset = 6

    static func findPeaks(magnitudes: [Float], config: AnalysisConfig) -> [SpectralPeak] {
        guard magnitudes.count > shoulderBinOffset * 2 else { return [] }
        let binHz = config.sampleRate / Double(config.windowSize)

        var peaks: [SpectralPeak] = []
        for bin in shoulderBinOffset..<(magnitudes.count - shoulderBinOffset) {
            guard magnitudes[bin] >= magnitudes[bin - 1], magnitudes[bin] >= magnitudes[bin + 1] else { continue }

            let centerDb = MagnitudeScaling.decibels(power: magnitudes[bin])
            let leftShoulderDb = MagnitudeScaling.decibels(power: magnitudes[bin - shoulderBinOffset])
            let rightShoulderDb = MagnitudeScaling.decibels(power: magnitudes[bin + shoulderBinOffset])
            let louderShoulderDb = max(leftShoulderDb, rightShoulderDb)

            guard centerDb - louderShoulderDb >= prominenceDb else { continue }
            peaks.append(SpectralPeak(bin: bin, frequencyHz: Double(bin) * binHz, magnitudeDb: centerDb))
        }
        return peaks
    }
}

nonisolated enum HarmonicRelation {
    /// How close a peak's frequency must land to an exact integer multiple
    /// of another peak to count as part of its harmonic series. Not
    /// spec'd -- loose enough to tolerate FFT bin quantization at low
    /// harmonic numbers, tight enough not to accidentally match unrelated
    /// peaks.
    static let toleranceRatio = 0.03

    /// True if `candidate` looks like a harmonic of any `other` peak, or
    /// any `other` peak looks like a harmonic of `candidate` (i.e.
    /// `candidate` is itself a fundamental with a detected harmonic) --
    /// either direction means this is part of a normal harmonic series
    /// (a musical note), not an isolated anomalous tone.
    ///
    /// Recognizes a harmonic at *any* integer multiple, not a fixed low cap
    /// (was 2...8, `maxHarmonic`): a strong tone's higher harmonics (>8th)
    /// were otherwise treated as unrelated and flagged as phantom Anomaly
    /// Candidates -- e.g. a 1250Hz tone with a little chain distortion lit up
    /// its 11th/13th harmonics (13750/16250Hz) as anomalies (user report).
    /// The nearest-integer-ratio test below has no upper bound, so every
    /// harmonic present is excluded. Tradeoff (ADR 0001, judgment call): with
    /// the same 3% tolerance a genuine independent tone that happens to sit
    /// within 3% of an integer multiple of another *present* peak is also
    /// excluded -- rare, since it needs an actual peak at the sub-multiple.
    static func isHarmonicallyRelated(_ candidate: SpectralPeak, to others: [SpectralPeak]) -> Bool {
        for other in others where other.bin != candidate.bin {
            if isHarmonic(candidate.frequencyHz, of: other.frequencyHz) { return true }
            if isHarmonic(other.frequencyHz, of: candidate.frequencyHz) { return true }
        }
        return false
    }

    /// True if `frequency` is within tolerance of an integer multiple (>= 2)
    /// of `fundamental`.
    private static func isHarmonic(_ frequency: Double, of fundamental: Double) -> Bool {
        guard fundamental > 0 else { return false }
        let n = (frequency / fundamental).rounded()
        guard n >= 2 else { return false }
        return isNear(frequency, n * fundamental)
    }

    private static func isNear(_ a: Double, _ b: Double) -> Bool {
        abs(a - b) <= toleranceRatio * b
    }
}

/// One promoted Anomaly Candidate -- narrowband, harmonically unrelated,
/// and sustained for long enough. `id` is the frequency itself (rounded to
/// the nearest Hz), stable enough across a track's lifetime for SwiftUI
/// list diffing.
nonisolated struct AnomalyCandidate: Identifiable, Equatable, Sendable {
    let frequencyHz: Double
    let severityDb: Float

    var id: Int { Int(frequencyHz.rounded()) }
}

/// Stateful rolling-window sustain tracker (ADR 0001's "sustained ...
/// over a rolling frame window"). Value type -- callers (AudioAnalysisPipeline)
/// own the mutable instance across hops.
nonisolated struct AnomalyDetector: Sendable {
    /// ~350ms sustain window (ADR 0001), long enough to reject a single
    /// transient hit while still catching a feedback ring building
    /// quickly. Expressed as a duration and converted to frames via the
    /// current config's hop duration, not a raw hardcoded frame count --
    /// it used to be `static let sustainFrameCount = 8`, correct only
    /// because it assumed the hop duration in effect when it was written
    /// (2048 samples @ 48kHz ≈ 43ms); AnalysisConfig.default later
    /// widening its hopSize would have silently doubled this detector's
    /// real-world sustain window to ~700ms as an unrelated side effect.
    static let sustainDurationSeconds: Double = 0.35

    static func sustainFrameCount(for config: AnalysisConfig) -> Int {
        let hopDurationSeconds = Double(config.hopSize) / config.sampleRate
        return max(1, Int((sustainDurationSeconds / hopDurationSeconds).rounded()))
    }

    /// How many consecutive misses a track tolerates before being dropped
    /// entirely, rather than reset on the very first missed frame -- a
    /// small allowance for a peak flickering at a bin boundary.
    static let releaseFrameCount = 3

    /// How much a peak's level may dip between frames and still count as
    /// "flat" rather than declining (ADR 0001: "flat-or-growing").
    static let flatToleranceDb: Float = 1

    /// The highest 2-3 candidates are what the Measured Data row shows
    /// (CONTEXT.md), so the detector itself caps its output here rather
    /// than every caller re-deriving the same slice.
    static let maxReportedCandidates = 3

    private struct Track {
        var bin: Int
        var consecutiveFrames: Int
        var missedFrames: Int = 0
        var lastMagnitudeDb: Float
    }

    private var tracks: [Int: Track] = [:]

    init() {}

    mutating func process(magnitudes: [Float], config: AnalysisConfig) -> [AnomalyCandidate] {
        let peaks = PeakFinder.findPeaks(magnitudes: magnitudes, config: config)
        let candidatePeaks = peaks.filter { !HarmonicRelation.isHarmonicallyRelated($0, to: peaks) }

        // Found by code review: matching against `tracks.keys.first(where:)`
        // without excluding keys already claimed this frame let two
        // distinct simultaneous peaks within 1 bin of the same track
        // silently collide -- the second peak overwrote the first's
        // update instead of starting its own track.
        var matchedKeys = Set<Int>()
        for peak in candidatePeaks {
            if let key = tracks.keys.first(where: { !matchedKeys.contains($0) && abs($0 - peak.bin) <= 1 }) {
                var track = tracks[key]!
                let isFlatOrGrowing = peak.magnitudeDb >= track.lastMagnitudeDb - Self.flatToleranceDb
                track.consecutiveFrames = isFlatOrGrowing ? track.consecutiveFrames + 1 : 0
                track.lastMagnitudeDb = peak.magnitudeDb
                track.missedFrames = 0
                track.bin = peak.bin
                tracks[key] = track
                matchedKeys.insert(key)
            } else {
                tracks[peak.bin] = Track(bin: peak.bin, consecutiveFrames: 1, lastMagnitudeDb: peak.magnitudeDb)
                matchedKeys.insert(peak.bin)
            }
        }

        // Found by code review: unconditionally zeroing consecutiveFrames
        // on every miss defeated releaseFrameCount's entire purpose -- an
        // already-promoted candidate would flicker out of the reported
        // list on a single missed frame (e.g. right at a bin boundary) and
        // have to re-accumulate all sustainFrameCount frames from scratch.
        // Sustain progress is now only lost once the track is actually
        // dropped past the release tolerance.
        for key in tracks.keys where !matchedKeys.contains(key) {
            tracks[key]?.missedFrames += 1
            if let missed = tracks[key]?.missedFrames, missed > Self.releaseFrameCount {
                tracks.removeValue(forKey: key)
            }
        }

        let binHz = config.sampleRate / Double(config.windowSize)
        let sustainFrameCount = Self.sustainFrameCount(for: config)
        let candidates = tracks.values
            .filter { $0.consecutiveFrames >= sustainFrameCount }
            .map { AnomalyCandidate(frequencyHz: Double($0.bin) * binHz, severityDb: $0.lastMagnitudeDb) }
            .sorted { $0.severityDb > $1.severityDb }

        return Array(candidates.prefix(Self.maxReportedCandidates))
    }
}
