# Anomaly Criteria — Prototype Results (ticket #36)

> **Retired (#38).** The throwaway prototype + synthetic-corpus harness this doc
> describes (`PrototypeAnomalyDetector`, `AnomalyCorpus`, `AnomalyScoring`, and
> their tests) were removed once the criteria shipped into the production
> `AnomalyDetector`. This doc stays as the historical record of how the criteria
> were derived; the shipped detector is covered by `AnomalyDetectionTests` and
> validated on real signals by `scripts/hcms-validate/`. The real-signal retune
> ([anomaly-hcms-validation.md](./anomaly-hcms-validation.md)) later corrected two
> of the conclusions below (binary→Sabine gate, −25→−45 floor).


The [reworked criteria](./anomaly-criteria.md) (#21) prototyped and scored against
the [synthetic corpus](./anomaly-validation-corpus.md), to pin the threshold
*intents* the spec deferred — "validated, not hand-tuned blind."

- Prototype: `FreqTraceTests/PrototypeAnomalyDetector.swift` (throwaway, test target).
- Scoring: `PrototypeCriteriaTests.swift`, on the #34 harness (`CorpusScorer`).
- **Result: 7 / 7, up from the baseline's [5 / 7](./anomaly-corpus-baseline.md)** —
  fixing exactly the two false positives (steady tone #5, hand-ramp #7) while
  keeping every ring case.

## Scorecard — params `.tuned`

```
case  expect      flagged  latency  verdict  detail
 1    must-flag   yes      341 ms   PASS     near-threshold ring-up, within the ~500 ms bar
 2    must-flag*  yes      341 ms   PASS     ring-up → saturate (rise, then hot/held)
 3    must-flag*  yes       85 ms   PASS     fast howl, flagged on loudness
 4    must-flag   yes      341 ms   PASS     room mode, flagged while building — and clears on decay
 5    must-not    no        —       PASS     steady tone never flags  ← anchoring bug fixed
 7    must-not    no        —       PASS     hand-ramp never flags     ← 2nd false positive fixed
10    must-not    no        —       PASS     silence never flags
```

Latency is measured from the target crossing **−25 dBFS** (the realistic
"findable peak" floor the #34 baseline doc asked #36 to introduce), so it now
reflects real climb-into-view time rather than the fixed sustain delay.

## Pinned intents — with the passing bounds each was swept over

Each threshold was swept independently (holding the others at the chosen value)
and the corpus re-scored, so these are *measured passing ranges*, not blind
single picks (`detectabilityFloorIsTheTightlyConstrainedKnob`,
`riseThresholdPassingBand`, `hotThresholdIsLooselyBounded`,
`fallAwayIsUnconstrainedBySyntheticCorpus`). The honest headline: **only the
detectability floor is tightly pinned by the synthetic corpus; the rest are
loosely bounded or unconstrained and need the real-capture tier (#37) to pin
properly.**

| Intent | Chosen | 7/7 holds over | How constrained |
|---|---|---|---|
| **Detectability floor** | **−25 dBFS** | **[−30, −22] dBFS** | **Tight — the load-bearing knob.** Below it the hand-ramp false-flags; above it a ring case is missed. |
| Rise amount | 6 dB / window | [4, 7] dB | Moderate. Below → over-fires; above → misses. |
| Hotness level | −6 dBFS | **> −8 dBFS** (lower bound) | Lower-bounded (Step 1): a loud steady −8 dBFS tone pins it above −8. The soft −1 upper rests on the saturated case, which can't isolate the memory path (caveats) — a real *arrives-flat* howl (#35) is what would pin the top. |
| Fall-away margin | 8 dB | **> ~7 dB** (lower bound only) | Lower-bounded (Step 1) by an *assumed* ~7 dB transient dip — a larger real fader pull could exceed 8 dB and wrongly release, and holding too long over-persists a settled mode, so the real dip magnitude and the upper bound both need real captures (#35). |
| Rise window | 7 hops (~300 ms) | — | Fixed (not swept); the ~500 ms bar and detector cadence set it. |
| Confirm | 2 hops | — | Anti-blip; fixed. |
| Accelerating-shape lever | **off** | — | Not needed — and harmful (see below). |

## The key finding — the floor, not the shape lever, rejects the hand-ramp

The spec expected the hand-ramp (7) to be the hard case, with the
**accelerating-shape lever** ("feedback ring-up is exponential / straight-line in
dB; a hand-ramp is concave-down") as the tool to reject it. The scan found the
opposite:

- **The accelerating-shape lever is the wrong tool.** With the lever on, the
  exponential feedback ring-ups (1, 2) still pass — they're straight lines in dB
  (`shapeLeverStillPassesExponentialRingUps`) — but a **room-mode bloom (4)** is
  *concave-down* in dB, so requiring a non-decelerating climb rejects the room
  mode too, a **false negative on a must-flag case**. Turning the lever on drops
  the score to 6/7 (case 4 fails: `accelerationShapeLeverBreaksTheRoomModeBloom`).
  **Modeling caveat:** this conclusion assumes a room-mode bloom really is
  concave-down. That's physically defensible (a driven resonance fills toward
  steady state as ~`1 − e^(−t/τ)`), but the synthetic case models it as a
  *linear* amplitude ramp — also concave-down in dB, but not the exact shape.
  Either way the lever rejects it; #37's real boomy-room capture is what
  confirms a genuine bloom's shape.
- **The detectability floor is what separates them.** A hand-ramp's *fast-dB*
  phase is down near silence (climbing from nothing); its slow tail is all
  that's visible above −25 dBFS, where the 6 dB / 300 ms rise gate rejects it. A
  room-mode bloom crosses −25 dBFS *fast* and passes. With the floor at −45 dBFS
  the ramp's fast phase is visible and it false-flags (6/7); at −25 dBFS it
  clears (7/7). Tests: `simpleClimbAtALowFloorStillFalseFlagsTheHandRamp`,
  `tunedCriteriaClearTheWholeCorpus`.

So the pinned rule is the **plain "climb now" gate plus a sensible candidate
floor** — no shape detection.

## Refinement levers — neither is needed (on the synthetic corpus)

The #21 spec named two optional levers. The scan says **hold both**:

- **Accelerating-shape detection** — *not needed, and actively harmful* (rejects
  the room-mode bloom, above). This matches the user's "climb now, shape later":
  ship the plain climb; the synthetic corpus gives no reason to add shape, and a
  clear reason not to.
- **Fluctuation-detection** ("does it breathe with the music?") — *not needed*
  here: the fall-away margin already clears the settling room mode (case 4 →
  `flaggedAtEnd == false`), so no separate breathing detector is required to
  drop it. It remains the documented lever for the harder real-world case (a
  steady-driven mode that never rings down), which the synthetic tier doesn't
  contain — revisit against real captures (#37).

## Binary vs. Sabine harmonic gate — decided (Step 1): keep binary

Originally deferred (the core corpus is all single tones). Step 1 added a
harmonically-rich case — a **musical crescendo** (a rising fundamental at 500 Hz
plus a 1/1.5/2 kHz harmonic series, `AnomalyCorpus.musicNoteCrescendo`). Two
separate things are worth keeping distinct:

- **What the case proves: the gate is load-bearing.** With the gate *off* the
  rising fundamental trips the rise trigger and the note false-flags; with the
  binary gate *on* it's correctly excluded (`harmonicGateIsLoadBearingForAMusicalCrescendo`,
  `tunedRejectsTheMusicNote`). The case does **not**, by itself, distinguish
  binary from Sabine — both pass the crescendo identically.
- **What the *arithmetic* argues (not the case): binary ≈ Sabine *under this
  floor*.** Sabine differs from binary only where a harmonic is a detectable peak
  yet more than the margin (33 dB) below its fundamental. A harmonic that clears
  the −25 dBFS candidate floor sits within 25 dB of a **≤ 0 dBFS** fundamental —
  inside a 33 dB margin — so both gates exclude the same thing. **This holds only
  while the premise does**, and it is conditional, not unconditional:
  - **fundamental > 0 dBFS** (production references raw power to `fullScalePower`,
    so a hot howl *can* read above 0 dBFS): e.g. a +10 dBFS fundamental with a
    34 dB-down harmonic lands at −24 dBFS — detectable *and* beyond the margin, so
    **binary and Sabine diverge** and Sabine is the more robust choice.
  - a **lower detectability floor** (< −33 dBFS) or a **smaller margin** likewise
    open a divergence gap.
- **Decision: keep binary *for now*** — it's simpler and provably equivalent in
  the ≤ 0 dBFS regime the synthetic cases live in. Revisit against real hot
  feedback (#35): if real fundamentals read above the reference, switch to the
  Sabine margin.
- **Residual weakness (both gates):** a feedback tone with a *detectable* harmonic
  (distorting chain) is suppressed by *either* gate. Feedback is normally a pure
  tone (research §1), so it's an edge case — but it's exactly what real hot
  feedback (#35) would expose.

## Caveats — what #37 must still confirm

- **The hand-ramp/room-mode separation rests on modeled levels and timescales.**
  It works because the modeled hand-ramp tops out at a moderate level (its fast
  phase stays below −25 dBFS) while the room mode blooms fast above it. Real
  captures could shift these; the −25 dBFS floor and the rate gate must be
  re-checked against #35's real hand-ramp and boomy-room recordings.
- **Case 3 still can't isolate the memory path.** As the baseline doc noted, at
  the 8192/2048 config the window smears any onset over ~4 hops, so the fast
  howl reads as a fast rise and is caught by the rise gate, not distinctly by
  the hotness/memory path. The hotness trigger *is* implemented and exercised by
  the saturated case, but a truly "arrives-flat" howl needs a smaller window or a
  direct injection to test in isolation.
- **Numbers are dBFS on synthetic spectra.** The production detector (#38) must
  reference raw FFT power to `FrequencyTracker.fullScalePower` before applying
  these dB thresholds (as SPL/RTA already do); the prototype works in the
  harness's already-normalized units.

## Step 1 (room-free extension) — what it pinned

Since a real room is unavailable, the room-free part of #37 was done here by
extending the synthetic tier (`AnomalyStepOneTests`, cases 8/12/13):

- **Harmonic gate decided** — keep binary (above).
- **Hotness lower-bounded** — a loud steady −8 dBFS tone must not hot-flag, pinning
  the threshold above −8 (`loudSteadyTonePinsTheHotnessLowerBound`).
- **Fall-away lower-bounded** — feedback must survive a ~7 dB transient dip, pinning
  the margin above ~7 (`transientDipPinsTheFallAwayLowerBound`).

## Handoff

- **#35 (real captures) — deferred, not blocking.** What still genuinely needs a
  room: confirm the −25 dBFS floor + rate gate separate a *real* hand-ramp from a
  *real* boomy-room bloom; pin the *upper* bounds Step 1 left open (fall-away vs.
  a real steady-driven mode; the residual harmonic edge case with real hot
  feedback); and a real noise-floor realism check. These are confirmations, not
  open decisions.
- **#38 — a *first* detector can ship, with eyes open.** What's pinned is the
  structure (four-state + hotness), the false-positive-gating knobs (detectability
  floor, rise amount, harmonic gate), and the *lower* bounds of hotness and
  fall-away. What's **not** pinned is the *upper* bounds of hotness and fall-away —
  and those gate the cardinal error (too-high hotness misses an arrives-flat howl;
  too-large fall-away over-persists a settled mode). So #38 should ship with
  **conservative defaults** on those two (the tuned −6 dBFS / 8 dB sit just inside
  their known-good lower bounds) and treat real-capture tightening as required
  follow-up, not optional polish. It still strictly improves on the current buggy
  flat-or-growing rule (which false-flags any steady tone), so shipping is a net
  win — but "fully validated" it is not.
