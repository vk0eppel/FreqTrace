//
//  RecentAnomalyTracker.swift
//  FreqTrace
//
//  The RECENT column beside LIVE in the Measured Data row's anomaly block
//  (user request). An Anomaly Candidate is released by AnomalyDetector within
//  ~40-170ms of the tone settling (docs/research/anomaly-criteria.md) -- far
//  too fast for a tech to read mid-show -- so a candidate that goes from live
//  to gone is kept here, dimmed, for later reference: which frequencies the
//  room/rig keeps ringing up.
//
//  This is a pure display-history transform over the live set the detector
//  already emits each hop -- it does NOT change detection (the HCMS-validated
//  AnomalyDetector is untouched). Extracted from AudioPipelineViewModel into a
//  value type in the same spirit as PeakHoldTracker/TimeAveragingBlender: it's
//  the natural test seam for a feature that's otherwise nearly impossible to
//  observe live (it needs a real narrowband tone to ring up and then settle).
//
// Plain value type, nonisolated (like PeakHoldTracker): opts out of the
// module's default @MainActor isolation so its nonisolated unit tests compile
// in Swift 6 language mode.

import Foundation

/// An Anomaly Candidate that was live and has since cleared. Carries the
/// loudest level (`peakDb`, dBFS) it reached while ringing -- not its level on
/// the last hop before it dropped off. `id` (rounded Hz, matching
/// AnomalyCandidate) is the dedup key.
nonisolated struct RecentAnomaly: Identifiable, Equatable, Sendable {
    let frequencyHz: Double
    let peakDb: Float

    var id: Int { Int(frequencyHz.rounded()) }
}

/// Maintains the RECENT list by diffing the live Anomaly Candidate set
/// hop-to-hop. Deduped by frequency: a room resonance that re-rings is one
/// finding, not a new entry -- while live it stays out of RECENT, and it
/// returns to RECENT (front, most-recent-first) only when it clears again.
nonisolated struct RecentAnomalyTracker: Sendable {
    /// How many cleared candidates to keep -- matches the LIVE column's 3-row
    /// cap so the split block never grows taller than its neighbours.
    let maxCount: Int

    private var recent: [RecentAnomaly] = []
    /// The loudest level (dBFS) each currently-live candidate has reached,
    /// keyed by AnomalyCandidate.id, so a released candidate carries its peak.
    private var liveMaxDb: [Int: Float] = [:]

    init(maxCount: Int) {
        self.maxCount = maxCount
    }

    /// Most-recent-first, capped at `maxCount`.
    var candidates: [RecentAnomaly] { recent }

    /// Advances one hop with the detector's current live set.
    mutating func update(live: [AnomalyCandidate]) {
        let liveIDs = Set(live.map(\.id))
        // Currently-live frequencies belong in LIVE, not RECENT; track the
        // running max level each has reached while ringing.
        for candidate in live {
            recent.removeAll { $0.id == candidate.id }
            liveMaxDb[candidate.id] = max(liveMaxDb[candidate.id] ?? candidate.severityDb, candidate.severityDb)
        }
        // Anything tracked as live but absent this hop has been released ->
        // promote to RECENT with its held peak. Louder-first among any
        // released together this hop, for a deterministic order (insert at 0
        // reverses, so iterate ascending by peak).
        let releasedPairs = liveMaxDb.keys
            .filter { !liveIDs.contains($0) }
            .map { (id: $0, peak: liveMaxDb[$0]!) }
            .sorted { $0.peak < $1.peak }
        for pair in releasedPairs {
            liveMaxDb[pair.id] = nil
            recent.removeAll { $0.id == pair.id }
            recent.insert(RecentAnomaly(frequencyHz: Double(pair.id), peakDb: pair.peak), at: 0)
        }
        if recent.count > maxCount {
            recent.removeLast(recent.count - maxCount)
        }
    }

    /// Clears the whole history -- wired to PEAK RESET and Stop.
    mutating func reset() {
        recent = []
        liveMaxDb = [:]
    }
}
