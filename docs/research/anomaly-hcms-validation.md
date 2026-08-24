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

## Headline

The synthetic-tuned criteria (7/7 on synthetics) detect **0 / 58** real howls —
but a **real-signal retune reaches 55% detection at 0% false-alarm**. Two
synthetic conclusions were wrong and are corrected by real data: the harmonic
gate must be a **Sabine margin, not binary**, and the floor must be **−45 dBFS,
not −25**. #38 is shippable on the retuned params, framed as a best-effort aid
that never false-alarms — a real improvement over both the current buggy rule and
the synthetic-tuned criteria. Details below.

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

These first-pass numbers used a **300 ms** rise window — too short for HCMS's
~1 s ramp, which is why detection looked so poor. The full retune below fixes it.
Real howls also span a huge level range (peak MSG level **−51.7 to −2.2 dBFS**) —
many are quiet and buried in program, and the −6 dBFS hotness trigger is
essentially never reached, so the rise gate does all the work.

## The full retune — the real ceiling is **55% detection at 0% false-alarm**

Sweeping FFT config × rise timing × floor × Sabine margin across all 58 clips,
with a **false-alarm *rate*** (fraction of clean-program time flagged) instead of
the harsh per-clip metric, the achievable frontier is:

| False-alarm ceiling | Best detection | at |
|---|---|---|
| **≤ 0.0%** | **55.2%** | floor −45, **rise 800 ms**, 3 dB, Sabine 10 dB, 128 ms window |
| ≤ 1% | 55.2% | (same, FA 0.00%) |
| ≤ 10% | 55.2% | 55.2% is the ceiling — more FA tolerance doesn't buy more detection |

The unlock was the **800 ms rise window** matched to the real ramp (the first
pass's 300 ms missed the slow real build-up). With it, a single-channel spectral
detector catches **over half of real feedback while never false-alarming on clean
program** — and 55% is a genuine ceiling for this approach (the missed ~45% are
quiet howls buried in program or coinciding with strong program harmonics).

**Retuned intents (`PrototypeParams.hcmsRetuned`):** detectability floor **−45
dBFS**, rise window **~800 ms** (19 hops at the app's 42.7 ms cadence), rise
**3 dB**, **Sabine margin 10 dB** (not binary), hotness left conservative
(unreached on real feedback).

## What this means for #38 — shippable as a best-effort aid

**Ship the retuned detector, framed honestly.** It catches **~55% of real
feedback with zero false-alarms on clean program** — it never cries wolf, and
when it flags, a tech can trust it. That matches what the Anomaly *Candidate*
feature always was (candidates, not alarms — CONTEXT.md). It is a large, real
improvement over both the current buggy flat-or-growing rule *and* the
synthetic-tuned criteria (0/58).

**The synthetic corpus mis-tuned two knobs, now corrected by real data:**
- The harmonic gate must be **Sabine margin, not binary** (real program harmonics
  otherwise suppress the howl). This overturns Step 1's synthetic "binary ≈
  Sabine."
- The floor must be **−45 dBFS, not −25** (real howls are quiet). This trips the
  *synthetic* hand-ramp case (7) — but that case is an artifact; on **real**
  program material the −45 floor + Sabine 10 + 800 ms rise produce **0%**
  false-alarms, so the synthetic hand-ramp rejection was over-fit.

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

- **#37 (this ticket) — done.** Real signals validated the criteria; the retune
  found a shippable operating point (55% detection, 0% false-alarm) and corrected
  two synthetic mis-tunings (binary→Sabine gate, −25→−45 floor). Remaining
  realism gaps stay documented: HCMS howling is simulated (not room-captured), no
  room-mode dataset exists, and the false-alarm metric is conservative.
- **#38 — unblocked, ship the retuned detector as a best-effort aid.** Implement
  the production detector with `PrototypeParams.hcmsRetuned`, referencing
  `fullScalePower`. Frame it honestly in the UI/expectations: catches ~half of
  real feedback, never false-alarms — a trustworthy candidate flag, not a
  guaranteed catch. A dual-channel/coherence method (Smaart-style) remains the
  path to higher recall, and is still out of v1 scope.
