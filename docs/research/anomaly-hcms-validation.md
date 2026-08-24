# Anomaly Detector — Real-Signal Validation on HCMS (ticket #37)

The prototype criteria (#36), tuned **7/7 against the synthetic corpus**, scored
against **real** howling-corrupted audio — the [HCMS dataset](./anomaly-real-signals-and-thresholds.md)
(KU Leuven, CC-BY-4.0): 58 clips of real music/speech driven into closed-loop
feedback, each 20 s at 16 kHz with the howling ramping up at t=8 s at a known
frequency (CSV ground truth). This is the room-substitute the research found.

Reproduce: `scripts/hcms-validate/` (a standalone Swift program — the app is
sandboxed, so this runs the DSP outside the test host). It references raw FFT
power to `FrequencyTracker.fullScalePower` before the dBFS thresholds, the step
#38 must do.

## Headline: the synthetic-tuned criteria detect **0 / 58** real howls

That is the whole result in one line. The criteria that scored 7/7 on synthetics
catch **nothing** on real feedback, and lowering the detectability floor alone
(all the way to −45 dBFS) doesn't change it. **This overturns the "ship #38 as a
strict improvement" handoff** — as tuned, the new detector would be blind to real
feedback.

## Why: the binary harmonic gate over-suppresses real feedback

The cause is specific and it **reverses the Step-1 synthetic conclusion** that
"binary ≈ Sabine given the floor":

- Turning the **harmonic gate off** → **48/58** howls flagged. So the gate is what
  blocks detection.
- But gate-off also → **46/58 false-alarms** on the clean 0–8 s program. So the
  gate is also load-bearing for rejecting music.

On *pure synthetic tones* a howl has no harmonics, so the binary gate never
touched it — hence Step 1 saw them as equivalent. On *real program material* the
howl frequency almost always coincides (within 3%) with some integer-ratio
program peak, so the **binary "any harmonic present → exclude" gate suppresses the
real howl.** This is the exact residual weakness the [threshold research](./anomaly-real-signals-and-thresholds.md)
flagged — now confirmed as the dominant failure on real signals.

## The Sabine margin helps — but the real tradeoff is poor

Replacing the binary gate with a **Sabine-style isolation margin** (exclude a peak
only if a harmonic/subharmonic is within *N* dB of it — implemented as
`PrototypeParams.harmonicMarginDb`) recovers detection, but reveals a genuine
detection-vs-false-alarm tradeoff with **no clean operating point** (floor −45,
rise 3):

| Harmonic rule | Howls flagged | Clean-program false-alarms |
|---|---|---|
| binary gate | **0 / 58** | 0 / 58 |
| gate off | 48 / 58 | 46 / 58 |
| Sabine 6 dB | 37 / 58 | 29 / 58 |
| Sabine 10 dB | 31 / 58 | 26 / 58 |
| Sabine 15 dB | 25 / 58 | 4 / 58 |
| Sabine 20 dB | 22 / 58 | 2 / 58 |
| Sabine 33 dB | 11 / 58 | 0 / 58 |

Best **zero-false-alarm** points found: `floor −35, rise 4, Sabine 15 dB` →
**20/58 (34%)** at 0 false-alarms; or Sabine 33 dB → 11/58 at 0. Catching more
(37/58) costs 29 false-alarms. **Nowhere near the synthetic 7/7.** Real howls also
span a huge level range (peak MSG level **−51.7 to −2.2 dBFS**) — many are quiet
and buried in program, and the −6 dBFS hotness trigger is essentially never
reached.

## What this means for #38

**Do not ship the synthetic-tuned detector.** It detects no real feedback. The
real correction is clear in direction — **switch the harmonic gate from binary to
a Sabine margin** — but even tuned, the best honest real-signal performance is
~34% detection at zero false-alarm, or higher detection with substantial
false-alarms. That's a product decision, not a threshold tweak: is a detector
that catches a third of feedback (quietly, no false alarms) useful, or does the
approach need rethinking (e.g. a coherence/second-mic method, out of v1 scope)?

## Honest caveats on this validation

- **Methodology is a first pass.** 16 kHz config (2048/683 ≈ 43 ms hops); the
  rise-window/hop mapping and the fixed 8 s onset are assumptions; HCMS's howling
  ramps over ~1 s, slower than the synthetic ring-ups the rise gate was tuned to.
  The *absolute* numbers are provisional — a proper retune should sweep the config
  and rise timing too.
- **The false-alarm metric is coarse and conservative.** "Any flag during 0–8 s" =
  a false alarm — but a sustained musical note *is* genuinely feedback-ambiguous
  (the music-vs-feedback hard problem), so some of these are defensible flags, not
  pure errors. Real false-alarm rate is likely *below* the table's numbers.
- **HCMS howling is simulated closed-loop** (real audio + real AIRs driven
  unstable), not literally room-mic-captured — realistic build-up, but a caveat.
- **No room-mode coverage** — HCMS is feedback only (the research found no
  room-mode dataset).
- **Small-in-scope but robust direction.** Even with the caveats, "0/58 as tuned"
  and "binary gate is the blocker" are not close calls — the direction is solid
  even if the exact percentages move.

## Handoff

- **#37 (this ticket) — real signals now in play, and they change the conclusion.**
  The binary→Sabine correction is confirmed necessary; the honest performance
  ceiling is characterised. A full retune (sweep config + rise timing + Sabine
  margin against all 58, with a better false-alarm metric) is the remaining work.
- **#38 — blocked again, on purpose.** Shipping the current criteria would ship a
  detector blind to real feedback. #38 should wait on the retune, or the approach
  should be reconsidered — a call for the maintainer.
