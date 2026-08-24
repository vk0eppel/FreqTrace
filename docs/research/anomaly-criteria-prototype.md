# Anomaly Criteria — Prototype Results (ticket #36)

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
| Hotness level | −6 dBFS | [−12, −1] dBFS | Loose — anywhere between the moderate tone (−14) and the hot cases (−1). |
| Fall-away margin | 8 dB | [2, 20] dB (all tested) | **Unconstrained** by the synthetic corpus — the room decay clears any value. A real steady-driven mode (#37) is what would pin it. |
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

## Binary vs. Sabine harmonic gate — deferred (as expected)

The synthetic corpus is all single tones, so no case exercises harmonic
isolation — binary exclusion and a Sabine-style margin behave identically here.
The prototype keeps the existing **binary** gate; the choice genuinely can't be
made until the real music/program cases (8, 9) exist, i.e. it belongs to **#37**,
exactly as #21 anticipated.

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

## Handoff

- **#37** — score these params against the real-capture tier; confirm the
  floor/rate separation survives real signals, and **pin the intents the
  synthetic corpus left loose**: the fall-away margin (unconstrained here) and
  the hotness level (wide band) need a real steady-driven mode and real hot
  feedback to constrain. Settle the harmonic gate against real music/program.
  Reopen the fluctuation lever only if a real steady-driven mode over-persists.
- **#38** — implement the production detector from the pinned intents here,
  referencing `fullScalePower`.
