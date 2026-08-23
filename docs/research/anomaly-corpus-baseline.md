# Anomaly Detector — Baseline Scorecard (ticket #34)

The synthetic tier of the [validation corpus](./anomaly-validation-corpus.md)
(map #18) scored against **today's** `AnomalyDetector` — the "narrowband +
harmonically-unrelated + flat-or-growing sustain" rule. This is the number the
[criteria rethink](./anomaly-criteria.md) (#21) and its prototype (#36) have to
beat: **fix the two false positives without losing any of the ring cases.**

Regenerate with the `AnomalyBaselineScorecardTests` suite
(`FreqTraceTests/AnomalyCorpusTests.swift`); the verdict assertions there encode
this same result in executable form, so it can't silently drift.

## Result — 5 / 7 pass

```
case  expect      flagged  latency  verdict  detail
 1    must-flag   yes      299 ms   PASS     near-threshold ring-up, flagged within 299 ms
 2    must-flag*  yes      299 ms   PASS     ring-up → saturate, flagged
 3    must-flag*  yes      299 ms   PASS     fast howl (arrives flat), flagged
 4    must-flag   yes      299 ms   PASS     room mode, flagged while building (and clears on decay)
 5    must-not    yes      299 ms   FAIL     steady test tone flagged — THE ANCHORING BUG
 7    must-not    yes      299 ms   FAIL     hand-ramped tone flagged — second false positive
10    must-not    no       —        PASS     silence correctly never flagged
```

`*` = no latency target (the saturated / fast-howl cases may show no rising
edge; the corpus only requires they be flagged at all).

Cases 8 (sustained music) and 9 (dense program) are the real-capture tier
(#35) and aren't in the synthetic scorecard.

## Reading it

- **The two FAILs are the whole reason for the rethink.** Case 5 (a steady
  test tone) and case 7 (a slowly hand-ramped tone) both satisfy today's
  "flat-or-growing sustain" rule, so both get flagged — exactly the
  false-positive behavior #21's criteria are designed to eliminate. Case 5 is
  the originally-reported anchoring bug; case 7 is the same weakness under a
  slow manual ramp.
- **The four must-flag cases all pass**, each flagged ~299 ms after the tone
  becomes a findable peak (7 hops × ~42.7 ms at the default config — the
  detector's ~350 ms sustain window, minus rounding). Case 4 additionally
  *clears* once the mode rings down, matching corpus case 6. The rethink must
  preserve all of this while fixing 5 and 7.
- **The target for #36** is therefore **7 / 7**: reach zero false negatives on
  1–4 *and* stop flagging 5 and 7, with the ring-up latency staying within the
  ~500 ms bar.

## How the scoring works (and a caveat)

Each case is a single tone whose amplitude follows an envelope (steady /
exponential ring-up / saturate / bloom-decay / hand-ramp / silence). The
harness turns each envelope into a per-hop magnitude spectrum — a clean floor
with the target bin raised to the envelope's **windowed power** (amplitude²
averaged over the windowSize samples the FFT would integrate) — and steps it
through the detector one hop at a time. Flag latency is an exact hop count,
measured from the hop the target first becomes a findable peak.

**Caveat — spectra are synthesized directly, not by FFT-ing a synthetic time
signal.** A pure synthetic tone through the real FFT has a floating-point
*roundoff* far-field that `PeakFinder` reads as hundreds of spurious per-bin
peaks, which the harmonic gate then relates to one another so *nothing* is ever
flagged — an artifact of synthetic roundoff (real mic audio has a smooth,
correlated noise floor that doesn't behave this way), unrepresentative of the
detector's real behavior and contradicting the observed bug. The direct-spectrum
seam is the one the existing `AnomalyDetectionTests` already use. Realistic
FFT leakage and a real noise floor are the **real-capture tier's** job
(#35/#37), not the synthetic tier's.

## Known limitations — handoff to #36

Two properties of this baseline harness are fit for #34's job (reproduce the
bug, establish the number to beat) but must be tightened before the harness can
*tune* the criteria in #36:

- **Latency is currently degenerate.** The `1e-8` spectral floor makes every
  non-silent tone a findable peak from hop 0, so `flagLatencyMs` only ever
  measures the detector's fixed sustain-promotion delay — every case reports the
  same 299 ms, and a near-threshold ring-up (1) and a steady tone (5) look
  identical on latency (they differ only on the flag/no-flag verdict, which is
  the point for #34). To make latency measure real *climb-into-view* time — what
  the ~500 ms bar actually gates — #36 should introduce a realistic detectability
  floor so a quiet ring starts *below* visibility and climbs up.
- **Case 3 ("fast howl, arrives flat") can't exercise the memory path yet.** At
  the default 8192/2048 config the FFT window integrates over ~4 hops, so even a
  sub-hop onset is smeared into a multi-hop *rise* — indistinguishable from a
  fast ring-up, and today's detector flags it via the ordinary sustain path.
  That's physically honest (a real 170 ms window can't show an instantaneous
  onset as flat), but it means the "no visible rising edge → caught by the
  memory latch" distinction the case exists to test needs either a smaller
  window or a direct already-saturated injection. #36 owns that, when it builds
  the memory latch the distinction is meant to drive. Today's detector has no
  memory path, so nothing is lost for the baseline.
