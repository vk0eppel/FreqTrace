//
//  PrototypeAnomalyDetector.swift
//  FreqTraceTests
//
//  A THROWAWAY prototype of the reworked anomaly-candidate criteria
//  (docs/research/anomaly-criteria.md, #21) -- the four-state life-cycle
//  (Rising -> Held -> Releasing; Never-Rose = never flag) plus the hotness
//  trigger, replacing today's "flat-or-growing sustain" rule. Ticket #36 on
//  map #18: it exists only to pin the threshold *intents* the spec left
//  open, by scanning it against the #34 synthetic corpus. It is NOT the
//  production detector (that's the downstream #38 handoff); it lives in the
//  test target and is fed magnitude spectra by the same CorpusScorer the
//  baseline uses.
//
//  Levels are read as dBFS via MagnitudeScaling.decibels(power:), which
//  assumes the spectrum is referenced to full-scale = power 1.0 -- true of
//  the corpus harness's synthesized spectra. The production detector (#38)
//  must first divide raw FFT power by FrequencyTracker.fullScalePower to get
//  the same reference (as SPL/RTA already do).
//
//  Convention (CLAUDE.md): pure value types are nonisolated.
//

import Foundation
@testable import FreqTrace

/// The tunable intents the spec deferred to this prototype. Every field is a
/// judgment knob the scan (PrototypeCriteriaTests) sweeps to find a set that
/// clears the corpus.
nonisolated struct PrototypeParams: Sendable {
    /// Minimum level (dBFS) for a peak to be considered an anomaly candidate
    /// at all -- quiet spectral texture below this is ignored.
    var detectFloorDb: Float
    /// How many hops back the rise is measured over (the "was ringing up in
    /// recent history" window).
    var riseWindowHops: Int
    /// Minimum climb (dB) across that window to count as "rising".
    var riseThresholdDb: Float
    /// The accelerating-shape lever: require the climb not to be
    /// decelerating (a straight-line-in-dB exponential ring-up passes; a
    /// concave-down hand-ramp fails). Off = the plain "climb now" rule.
    var requireNonDecelerating: Bool
    /// Slack for the non-decelerating check (dB).
    var shapeToleranceDb: Float
    /// Absolute level (dBFS) at/above which a peak flags on loudness alone,
    /// with no rising edge -- the fast-howl / memory path.
    var hotThresholdDb: Float
    /// Consecutive qualifying hops (rising or hot) before a track latches --
    /// rejects single-hop blips.
    var confirmHops: Int
    /// How far (dB) a latched track may fall below its held peak before it's
    /// released (rings down / settles).
    var fallAwayDb: Float
    /// Missed frames tolerated before a track is dropped (bin-boundary flicker).
    var releaseFrameCount: Int
    /// Whether the harmonic-exclusion gate is applied at all. Only used to
    /// demonstrate the gate is load-bearing (a rising musical note flags with
    /// it off, not on); production keeps it on.
    var harmonicGateEnabled: Bool = true
    /// If set, use a Sabine-style harmonic-isolation *margin* (exclude a peak
    /// only when a harmonic/subharmonic peak is within this many dB of it)
    /// instead of the binary "any harmonic present -> exclude" gate. Needed
    /// on real program material, where the binary gate over-suppresses a howl
    /// that merely coincides with a weak program harmonic (#37 / HCMS
    /// finding). `nil` = binary gate.
    var harmonicMarginDb: Float? = nil

    /// The plain "climb now, shape later" rule -- no accelerating-shape check.
    static let simpleClimb = PrototypeParams(
        detectFloorDb: -45,
        riseWindowHops: 7,
        riseThresholdDb: 6,
        requireNonDecelerating: false,
        shapeToleranceDb: 2,
        hotThresholdDb: -6,
        confirmHops: 2,
        fallAwayDb: 8,
        releaseFrameCount: 3
    )

    /// The pinned set (see PrototypeCriteriaTests / the results doc). The
    /// scan showed the accelerating-shape lever is NOT the right tool -- it
    /// also rejects a genuine room-mode bloom (same concave-down shape as a
    /// hand-ramp). What actually separates the hand-ramp is the
    /// **detectability floor**: the ramp's fast-dB phase is below -25 dBFS,
    /// so only its slow tail is visible, where the rise-rate gate rejects it;
    /// a room-mode bloom crosses -25 dBFS fast and passes. So: plain climb +
    /// a -25 dBFS floor, no shape lever.
    static let tuned = PrototypeParams(
        detectFloorDb: -25,
        riseWindowHops: 7,
        riseThresholdDb: 6,
        requireNonDecelerating: false,
        shapeToleranceDb: 2,
        hotThresholdDb: -6,
        confirmHops: 2,
        fallAwayDb: 8,
        releaseFrameCount: 3
    )

    /// The real-signal-validated set (docs/research/anomaly-hcms-validation.md):
    /// 55% detection at 0% false-alarm on the real HCMS dataset. It supersedes
    /// `.tuned` for #38 -- the real data corrected two synthetic mis-tunings:
    /// the floor drops to -45 dBFS (real howls are quiet) and the harmonic gate
    /// becomes a **Sabine 10 dB margin** (binary over-suppresses a howl that
    /// coincides with a program harmonic). The rise window widens to ~800 ms
    /// (19 hops at the 42.7 ms cadence) to match a real ~1 s ring-up. Note it
    /// trips the *synthetic* hand-ramp case (an artifact), but produces 0%
    /// false-alarms on real program.
    static let hcmsRetuned = PrototypeParams(
        detectFloorDb: -45,
        riseWindowHops: 19,
        riseThresholdDb: 3,
        requireNonDecelerating: false,
        shapeToleranceDb: 2,
        hotThresholdDb: -6,
        confirmHops: 2,
        fallAwayDb: 8,
        releaseFrameCount: 3,
        harmonicMarginDb: 10
    )
}

nonisolated struct PrototypeAnomalyDetector {
    let params: PrototypeParams

    private struct Track {
        var bin: Int
        var levelsDb: [Float]     // oldest .. newest, bounded
        var latched = false
        var heldPeakDb: Float
        var qualifyingStreak = 0
        var missed = 0
    }

    private var tracks: [Int: Track] = [:]

    init(params: PrototypeParams) {
        self.params = params
    }

    mutating func process(magnitudes: [Float], config: AnalysisConfig) -> [AnomalyCandidate] {
        let binHz = config.sampleRate / Double(config.windowSize)
        let historyLength = params.riseWindowHops + 1

        // Narrowband + harmonically-unrelated peaks above the candidate floor.
        let peaks = PeakFinder.findPeaks(magnitudes: magnitudes, config: config)
        let candidatePeaks = peaks
            .filter { !params.harmonicGateEnabled || !isExcludedByHarmonic($0, peaks: peaks) }
            .filter { MagnitudeScaling.decibels(power: magnitudes[$0.bin]) >= params.detectFloorDb }

        var matchedKeys = Set<Int>()
        for peak in candidatePeaks {
            let db = MagnitudeScaling.decibels(power: magnitudes[peak.bin])
            if let key = tracks.keys.first(where: { !matchedKeys.contains($0) && abs($0 - peak.bin) <= 1 }) {
                var track = tracks[key]!
                track.levelsDb.append(db)
                if track.levelsDb.count > historyLength { track.levelsDb.removeFirst() }
                track.missed = 0
                track.bin = peak.bin
                tracks[key] = track
                matchedKeys.insert(key)
            } else {
                tracks[peak.bin] = Track(bin: peak.bin, levelsDb: [db], heldPeakDb: db)
                matchedKeys.insert(peak.bin)
            }
        }

        // Age out tracks that didn't appear this hop (fell below the floor or
        // vanished) -- a released ring / settled mode / gone tone.
        for key in tracks.keys where !matchedKeys.contains(key) {
            tracks[key]?.missed += 1
            if let missed = tracks[key]?.missed, missed > params.releaseFrameCount {
                tracks.removeValue(forKey: key)
            }
        }

        // Advance the state machine for every track seen this hop.
        for key in matchedKeys where tracks[key] != nil {
            var track = tracks[key]!
            let current = track.levelsDb.last!
            if track.latched {
                track.heldPeakDb = max(track.heldPeakDb, current)
                if current < track.heldPeakDb - params.fallAwayDb {
                    tracks.removeValue(forKey: key)   // RELEASING: fell away
                    continue
                }
            } else {
                let hot = current >= params.hotThresholdDb
                let rose = isRising(track.levelsDb)
                track.qualifyingStreak = (hot || rose) ? track.qualifyingStreak + 1 : 0
                if track.qualifyingStreak >= params.confirmHops {
                    track.latched = true          // RISING/hot -> flag
                    track.heldPeakDb = current
                }
            }
            tracks[key] = track
        }

        return tracks.values
            .filter(\.latched)
            .map { AnomalyCandidate(frequencyHz: Double($0.bin) * binHz, severityDb: $0.levelsDb.last!) }
            .sorted { $0.severityDb > $1.severityDb }
            .prefix(AnomalyDetector.maxReportedCandidates)
            .map { $0 }
    }

    /// Whether `peak` should be excluded as harmonically related. Binary mode
    /// (`harmonicMarginDb == nil`) defers to `HarmonicRelation` (any harmonic
    /// present → exclude). Margin mode excludes only when a harmonic or
    /// subharmonic peak is within `margin` dB of `peak` (a *strong* harmonic,
    /// i.e. real musical structure) — so an isolated howl that merely
    /// coincides with a weak program harmonic survives.
    private func isExcludedByHarmonic(_ peak: SpectralPeak, peaks: [SpectralPeak]) -> Bool {
        guard let margin = params.harmonicMarginDb else {
            return HarmonicRelation.isHarmonicallyRelated(peak, to: peaks)
        }
        for other in peaks where other.bin != peak.bin {
            guard isIntegerRatio(peak.frequencyHz, other.frequencyHz) else { continue }
            if other.magnitudeDb >= peak.magnitudeDb - margin { return true }
        }
        return false
    }

    /// True if either frequency is within 3% of an integer multiple (≥2) of
    /// the other — the same relation `HarmonicRelation` uses, reimplemented
    /// here because its helper is private.
    private func isIntegerRatio(_ a: Double, _ b: Double) -> Bool {
        func near(_ x: Double, _ y: Double) -> Bool { abs(x - y) <= 0.03 * y }
        func harmonic(_ f: Double, of fund: Double) -> Bool {
            guard fund > 0 else { return false }
            let n = (f / fund).rounded()
            return n >= 2 && near(f, n * fund)
        }
        return harmonic(a, of: b) || harmonic(b, of: a)
    }

    /// True if the track climbed at least `riseThresholdDb` across the rise
    /// window and (with the shape lever on) that climb isn't decelerating.
    private func isRising(_ levelsDb: [Float]) -> Bool {
        guard levelsDb.count >= params.riseWindowHops + 1 else { return false }
        let n = levelsDb.count
        let start = levelsDb[n - 1 - params.riseWindowHops]
        let recent = levelsDb[n - 1]
        guard recent - start >= params.riseThresholdDb else { return false }

        if params.requireNonDecelerating {
            let half = params.riseWindowHops / 2
            guard half >= 1 else { return true }
            let mid = levelsDb[n - 1 - half]
            let earlyGain = mid - start
            let recentGain = recent - mid
            // A straight line in dB (exponential ring-up) has recentGain ≈
            // earlyGain; a concave-down hand-ramp has recentGain < earlyGain.
            if recentGain < earlyGain - params.shapeToleranceDb { return false }
        }
        return true
    }
}

extension PrototypeAnomalyDetector {
    /// A per-hop process closure over a fresh prototype -- the shape the
    /// CorpusScorer expects, mirroring BaselineDetector.makeProcess.
    static func makeProcess(params: PrototypeParams, config: AnalysisConfig) -> (_ magnitudes: [Float]) -> [AnomalyCandidate] {
        var detector = PrototypeAnomalyDetector(params: params)
        return { detector.process(magnitudes: $0, config: config) }
    }
}
