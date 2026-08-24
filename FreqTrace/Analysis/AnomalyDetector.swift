//
//  AnomalyDetector.swift
//  FreqTrace
//
//  The Anomaly Candidate detector (ticket #5/#38, ADR 0001, CONTEXT.md
//  "Anomaly Candidate"): flags a narrowband, harmonically-isolated tone that
//  *rose into existence* -- was ringing up in recent history -- without
//  classifying the cause (feedback vs. room resonance; ADR 0001 unifies both
//  for v1). Runs on the raw (unweighted, Fast) spectrum so a genuine
//  low-frequency resonance isn't hidden by A-weighting or smoothed away.
//
//  The rule is a four-state life-cycle (docs/research/anomaly-criteria.md),
//  replacing the original "flat-or-growing sustain" rule, which flagged any
//  steady tone (the anchoring bug -- a signal-generator tone read as an
//  anomaly):
//    RISING    a climbing peak -> flag (the ring-up, no loudness floor)
//    hotness   a screaming-hot peak with no rising edge -> flag on loudness
//    HELD      stopped climbing but holding near its peak -> keep flagging
//    RELEASING falls away from its held peak -> drop (rings down / settles)
//    NEVER-ROSE appeared flat, never climbed, not hot -> never flag
//
//  Every threshold below is *real-signal-validated* against the real HCMS
//  feedback dataset -- ~55% detection at ~0.16% false-alarm
//  (docs/research/anomaly-hcms-validation.md), NOT the synthetic-only values
//  that detected 0/58 real howls. Levels are dBFS: raw FFT power is referenced
//  to `fullScalePower` (as SPL/RTA do) before the absolute thresholds. Two
//  corrections real data forced over the synthetic tuning: the harmonic gate
//  is a Sabine-style *isolation margin* (a binary "any harmonic present ->
//  exclude" gate suppressed real howls coinciding with a program harmonic),
//  and the floor is -45 dBFS (real howls are quiet). Best-effort by design:
//  it catches ~half of real feedback and effectively never false-alarms on
//  clean program -- a trustworthy *candidate* flag, not a guaranteed catch
//  (higher recall needs dual-channel coherence, out of v1 scope).
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

    /// Sabine-style harmonic *isolation margin* (US 5,245,665): true if
    /// `candidate` has a harmonic or subharmonic peak that is *strong* --
    /// within `margin` dB of it -- i.e. real musical structure, not an
    /// isolated tone. Unlike `isHarmonicallyRelated` (binary: any harmonic
    /// present -> exclude), a peak with only a *weak* harmonic (more than
    /// `margin` dB down) is NOT excluded. This is the #38/HCMS correction:
    /// on real program the binary gate suppressed a real howl that merely
    /// coincided with a weaker program harmonic (docs/research/
    /// anomaly-hcms-validation.md). The comparison is on raw magnitudeDb --
    /// a level *difference*, so referencing to full-scale would cancel.
    static func isStronglyRelated(_ candidate: SpectralPeak, to others: [SpectralPeak], withinDb margin: Float) -> Bool {
        for other in others where other.bin != candidate.bin {
            guard isHarmonic(candidate.frequencyHz, of: other.frequencyHz)
                || isHarmonic(other.frequencyHz, of: candidate.frequencyHz) else { continue }
            if other.magnitudeDb >= candidate.magnitudeDb - margin { return true }
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

/// Stateful four-state tracker (see the file header). Value type -- callers
/// (AudioAnalysisPipeline) own the mutable instance across hops. All
/// thresholds are HCMS-validated (docs/research/anomaly-hcms-validation.md).
nonisolated struct AnomalyDetector: Sendable {
    /// Minimum level (dBFS) for a peak to be an anomaly candidate at all --
    /// quiet spectral texture below this is ignored. -45 dBFS: real howls
    /// are quiet (HCMS peak levels span ~-51..-2 dBFS), so a higher floor
    /// silently drops most of them.
    static let detectFloorDb: Float = -45

    /// Minimum climb (dB) across the rise window to count as "ringing up".
    static let riseThresholdDb: Float = 3

    /// The rise window -- "was ringing up in recent history". ~800 ms, matched
    /// to a real feedback ring-up (HCMS howling ramps over ~1 s); the earlier
    /// ~300 ms was too short and missed the slow real build-up. A duration,
    /// converted to frames via the current hop, so it stays constant wall-clock
    /// across FFT sizes.
    static let riseWindowSeconds: Double = 0.8

    /// Consecutive qualifying hops (rising or hot) before a track latches --
    /// rejects a single-hop blip. ~85 ms, also duration-derived.
    static let confirmSeconds: Double = 0.085

    /// Absolute level (dBFS) at/above which a peak flags on loudness alone,
    /// with no rising edge -- the fast-howl / already-saturated path.
    /// Conservative: real feedback rarely reaches it, so the rise gate does
    /// the work; its upper bound is unpinned by the synthetic corpus and left
    /// safe (docs/research/anomaly-criteria-prototype.md).
    static let hotThresholdDb: Float = -6

    /// How far (dB) a latched track may fall below its held peak before it's
    /// released (rings down / settles).
    static let fallAwayDb: Float = 8

    /// Sabine harmonic-isolation margin (dB): exclude a peak only when a
    /// harmonic/subharmonic is within this of it. See `HarmonicRelation.
    /// isStronglyRelated` -- the binary gate over-suppressed real feedback.
    static let harmonicMarginDb: Float = 10

    /// How many consecutive misses a track tolerates before being dropped --
    /// a small allowance for a peak flickering at a bin boundary.
    static let releaseFrameCount = 3

    /// The highest 2-3 candidates are what the Measured Data row shows
    /// (CONTEXT.md), so the detector caps its own output here.
    static let maxReportedCandidates = 3

    static func riseWindowFrames(for config: AnalysisConfig) -> Int {
        frames(riseWindowSeconds, for: config, minimum: 2)
    }
    static func confirmFrames(for config: AnalysisConfig) -> Int {
        frames(confirmSeconds, for: config, minimum: 1)
    }
    private static func frames(_ seconds: Double, for config: AnalysisConfig, minimum: Int) -> Int {
        let hopDurationSeconds = Double(config.hopSize) / config.sampleRate
        return max(minimum, Int((seconds / hopDurationSeconds).rounded()))
    }

    private struct Track {
        var bin: Int
        var levelsDbFS: [Float]      // oldest .. newest, bounded to the rise window
        var latched = false
        var heldPeakDb: Float
        var qualifyingStreak = 0
        var missed = 0
    }

    private var tracks: [Int: Track] = [:]

    init() {}

    /// `fullScalePower` references raw FFT power to full-scale (dBFS) before
    /// the absolute thresholds -- the same reference SPL/RTA use.
    mutating func process(magnitudes: [Float], fullScalePower: Float, config: AnalysisConfig) -> [AnomalyCandidate] {
        let binHz = config.sampleRate / Double(config.windowSize)
        let riseWindow = Self.riseWindowFrames(for: config)
        let confirm = Self.confirmFrames(for: config)
        let historyLength = riseWindow + 1

        func levelDbFS(_ bin: Int) -> Float {
            MagnitudeScaling.decibels(power: fullScalePower > 0 ? magnitudes[bin] / fullScalePower : magnitudes[bin])
        }

        // Narrowband + harmonically-isolated peaks above the candidate floor.
        let peaks = PeakFinder.findPeaks(magnitudes: magnitudes, config: config)
        let candidatePeaks = peaks
            .filter { !HarmonicRelation.isStronglyRelated($0, to: peaks, withinDb: Self.harmonicMarginDb) }
            .filter { levelDbFS($0.bin) >= Self.detectFloorDb }

        // Match to existing tracks or start new ones. The `matchedKeys` guard
        // (found by code review) stops two distinct peaks within 1 bin of the
        // same track from silently colliding.
        var matchedKeys = Set<Int>()
        for peak in candidatePeaks {
            let level = levelDbFS(peak.bin)
            if let key = tracks.keys.first(where: { !matchedKeys.contains($0) && abs($0 - peak.bin) <= 1 }) {
                var track = tracks[key]!
                track.levelsDbFS.append(level)
                if track.levelsDbFS.count > historyLength { track.levelsDbFS.removeFirst() }
                track.missed = 0
                track.bin = peak.bin
                tracks[key] = track
                matchedKeys.insert(key)
            } else {
                tracks[peak.bin] = Track(bin: peak.bin, levelsDbFS: [level], heldPeakDb: level)
                matchedKeys.insert(peak.bin)
            }
        }

        // Age out tracks that didn't appear this hop (fell below the floor or
        // vanished); the release tolerance lets a bin-boundary flicker survive.
        for key in tracks.keys where !matchedKeys.contains(key) {
            tracks[key]?.missed += 1
            if let missed = tracks[key]?.missed, missed > Self.releaseFrameCount {
                tracks.removeValue(forKey: key)
            }
        }

        // Advance the state machine for every track seen this hop.
        for key in matchedKeys where tracks[key] != nil {
            var track = tracks[key]!
            let current = track.levelsDbFS.last!
            if track.latched {
                track.heldPeakDb = max(track.heldPeakDb, current)
                if current < track.heldPeakDb - Self.fallAwayDb {
                    tracks.removeValue(forKey: key)   // RELEASING: fell away
                    continue
                }
            } else {
                let hot = current >= Self.hotThresholdDb
                let rose = Self.isRising(track.levelsDbFS, window: riseWindow)
                track.qualifyingStreak = (hot || rose) ? track.qualifyingStreak + 1 : 0
                if track.qualifyingStreak >= confirm {
                    track.latched = true          // RISING/hot -> flag
                    track.heldPeakDb = current
                }
            }
            tracks[key] = track
        }

        return tracks.values
            .filter(\.latched)
            .map { AnomalyCandidate(frequencyHz: Double($0.bin) * binHz, severityDb: $0.levelsDbFS.last!) }
            .sorted { $0.severityDb > $1.severityDb }
            .prefix(Self.maxReportedCandidates)
            .map { $0 }
    }

    /// True if the track climbed at least `riseThresholdDb` across the rise
    /// window (a plain climb -- "climb now, shape later"; the accelerating-shape
    /// lever was found unnecessary and harmful, docs/research/
    /// anomaly-criteria-prototype.md).
    private static func isRising(_ levelsDbFS: [Float], window: Int) -> Bool {
        guard levelsDbFS.count >= window + 1 else { return false }
        let start = levelsDbFS[levelsDbFS.count - 1 - window]
        let recent = levelsDbFS[levelsDbFS.count - 1]
        return recent - start >= riseThresholdDb
    }
}
