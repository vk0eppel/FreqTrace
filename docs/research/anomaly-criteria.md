# Anomaly-Candidate Criteria (v2)

**Purpose.** Defines the criteria and threshold *intents* for a trustworthy anomaly-candidate detector — the replacement for today's "narrowband + harmonically-unrelated + flat-or-growing sustain" rule (`FreqTrace/Analysis/AnomalyDetector.swift`), whose flat-sustain clause mis-flags a steady test tone (the anchoring bug). This is the deliverable of ticket **"Define the criteria that separate an anomaly from benign steady content"** (#21) on the trustworthy-detection map (#18), decided via `/grilling` with the user (a sound engineer).

It builds on [anomaly-signatures.md](./anomaly-signatures.md) (#19 — the physics) and [anomaly-validation-corpus.md](./anomaly-validation-corpus.md) (#20 — the scoring target). **This is a spec, not the shipped detector**: hard decisions below are settled; *intents* are directions for the prototype to pin down against the corpus, "validated, not hand-tuned blind" (#21).

**Convention:** **bold = decided**; *italic = intent, prototype-tuned*.

---

## 1. Guiding principle (from #20)

**Flag a narrowband, harmonic-free tone if it *rose into existence*** — was ringing up in recent history, still climbing *or* since pinned flat. **Ignore anything that was flat from the start.** History is the discriminator: feedback and an excited room mode *arrive* by rising; a steady test tone and a settled room just *are*.

## 2. Pre-gates (unchanged from today)

- **Runs on the raw, unblended spectrum, Fast time-averaging** (ADR 0001) — a building ring must be caught fast, not smoothed away.
- **Narrowband:** peak stands **≥6 dB above its shoulders** (`PeakFinder`, unchanged).
- **Harmonic gate — *prototype decides*** between:
  - the current **binary exclusion** (a peak sitting on another peak's harmonic series is dropped — `HarmonicRelation`), and
  - a **Sabine-style harmonic-isolation margin** (peak must stand a set dB — the patent uses 33 dB — above its *own* harmonics/subharmonics).
  Both are recorded as candidates; the prototype scores them against the real music/program corpus cases (8, 9) to decide whether the binary gate alone holds or the margin is needed. Rationale for not upgrading blind: the new rise gate (§3) already rejects sustained/held music (a pad isn't ringing up), so the margin may be redundant now.

## 3. The temporal rule — a four-state life-cycle

Replaces today's "flat-or-growing sustain." A candidate frequency (a peak passing the pre-gates) moves through:

1. **RISING → flag.** The peak is *climbing* over successive frames — "ringing up." Flag once the climb is convincing, target **~500 ms** to catch it (#20). **No loudness floor** — a gentle near-threshold ring flags while still quiet (honors "never miss a ring").
   - *Rise amount = intent: sensitive (~a few dB gained over the window), refined from the permissive side; prototype sets the exact figure against the corpus.*
   - **Shape-of-climb is ignored for v1 — "climb now, shape later."** A simple sustained climb flags regardless of curve shape. Detecting the *accelerating/exponential* shape (to more actively reject a linear hand-ramp, corpus case 7) is a **documented prototype refinement**, added only if hand-ramps prove to false-flag against the corpus.

2. **Hotness trigger → flag (the no-rise fallback).** A narrowband, harmonic-free tone that appears **screaming-hot** (at the system ceiling) with **no visible rising edge** flags on **loudness alone** — this catches the sub-frame *fast howl* (corpus case 3), which saturates faster than one ~43 ms analysis frame and so shows no climb.
   - *Level threshold = intent: "clipping-hot" / near the system ceiling; prototype sets it.*
   - Still requires the narrowband + harmonic-free pre-gates and a **brief persistence** (not a single-frame spike), so a lone loud transient doesn't trip it.
   - **Why loudness is the only lever here:** with no envelope history, a fast howl is physically indistinguishable from a switched-on test tone except by level (#19 §3). The user's ruling: a screaming tone at the ceiling is almost always feedback; flag it. A sane-level test tone stays under the threshold; a rare loud-test-tone false flag is within the relaxed bar (#20).

3. **HELD → keep flagging.** Stopped climbing but **holding near its peak level** = saturated feedback pinned at the ceiling (#20 "must-flag via memory"). Stays flagged; no timeout.

4. **RELEASING → drop. Fall-away only.** A flag clears **only when the tone falls away / rings down** from its held peak — a settling room mode ringing down, or feedback that's been pulled.
   - *Fall-away margin = intent, prototype-tuned* (how far below the held peak counts as "ringing down").
   - Keeps the existing **3-frame miss tolerance** (`releaseFrameCount`) so a bin-boundary flicker doesn't prematurely drop a track.
   - **Fluctuation-detection** ("does it breathe with the music?" — modes waver, feedback is dead-steady) is the **documented refinement lever**, added if stubborn steady-driven modes prove annoying. Not in v1.

5. **NEVER-ROSE → never flag.** Appeared and sat flat without climbing, and isn't screaming-hot = a steady test tone / silence. **Structurally excluded** (it never entered RISING and doesn't trip the hotness trigger) — this is what fixes the anchoring bug, without threshold-tuning.

## 4. Reporting (unchanged)

Top **3 candidates by severity** (current level in dB), per CONTEXT.md.

## 5. The unavoidable ambiguity, stated plainly

Two corpus pairs cannot be separated cleanly from the mic signal alone; the rulings above pick the never-miss side and lean on the relaxed false-flag bar:

- **Fast howl (case 3) vs. switched-on test tone (case 5):** identical (absent → flat-and-present in one step) except by loudness → resolved by the **hotness trigger** (flag the hot one).
- **Saturated feedback (case 2) vs. perfectly-steady settled room mode (case 6):** both rose then hold dead-flat → resolved by **fall-away-only** (keep both while held; a mode that never falls keeps flagging). This **softens corpus case 6**: a settled mode clears reliably only if it's *decaying*; one held perfectly flat forever may keep flagging (rare, within the relaxed bar; ADR 0001 unifies feedback + resonance anyway).

Both are acceptable under #20's cardinal rule (**false negatives are the worst error**) and relaxed must-not-flag bar. Fluctuation-detection and accelerating-shape detection are the two documented levers to tighten these later, prototype-validated.

## 6. Decisions this spec encodes

| Decision | Ruling |
|---|---|
| Rule shape | **Four-state life-cycle** (Rising → Held → Releasing; Never-Rose = never flag), replacing flat-or-growing sustain |
| Fast howl (no rising edge) | **Hotness trigger** — flag a screaming-hot narrowband/harmonic-free tone on loudness alone |
| Rise trigger shape | **Simple sustained climb — "climb now, shape later"** (accelerating-shape = prototype refinement) |
| Rise amount | *Intent: sensitive, prototype-tuned* |
| Held vs. drop | **Fall-away only** (never-miss); fluctuation-detection = prototype refinement |
| Harmonic gate | *Prototype decides* binary exclusion vs. Sabine dB margin |
| Pre-gates, reporting | **Unchanged** (raw/Fast spectrum, 6 dB narrowband, top-3 by severity) |

## 7. Handoff — what the prototype must do (map #18)

Score this criteria set against the [10-case corpus](./anomaly-validation-corpus.md):

- **Pin the intents:** the rise amount (§3.1), the hotness level (§3.2), the fall-away margin (§3.4).
- **Decide the harmonic gate** (§2) against cases 8, 9.
- **Measure whether the two refinement levers are needed:** accelerating-shape (if case 7 hand-ramps false-flag) and fluctuation-detection (if steady modes over-persist).
- **Confirm the hard gate:** zero false negatives on the must-flag set (cases 1–4), catchable ring-up flagged within ~500 ms.
