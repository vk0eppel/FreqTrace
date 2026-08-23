# Anomaly-Candidate Validation Corpus

**Purpose.** Defines the fixed set of signal cases a trustworthy anomaly-candidate detector must be scored against, how each case is sourced (synthetic vs. real), the pass/fail expectation per case, and the numeric acceptance bar. This is the deliverable of the **"Trustworthy anomaly-candidate detection"** wayfinder map (issue #18), ticket **"Decide the validation corpus for trustworthy detection"** (#20). It hands off to a capture/build task and to the criteria-definition ticket (#21).

It builds directly on the signature characterization in [anomaly-signatures.md](./anomaly-signatures.md) (ticket #19) — read that first for the physics behind each class.

**Scope.** This document decides the *measuring stick*, not the detector. The criteria and thresholds it validates are #21's job; the production detector is downstream of both (see #18 Out of scope).

---

## 1. Guiding principle (the discriminator this corpus is built to prove)

**Flag a narrowband, harmonic-free tone if it *rose into existence* — was ringing up in recent history, whether it is still climbing or has since pinned flat. Ignore anything that was flat from the start.**

History is the separator. Feedback and an excited room mode *arrive* by rising; a steady test tone and a settled room just *are*. This is a deliberate shift from the current detector's "sustained (flat-or-growing)" rule, which flags the flat case and so mis-flags a steady tone (the anchoring bug, #18 / ADR 0001).

Two consequences the corpus is designed to force:

- **Saturated feedback must stay flagged.** Real feedback rings up then pins *flat* at the PA's ceiling once it clips; a big gain margin can make it saturate within a single analysis hop, so it can appear "already flat." A strict "growing right now" rule would go silent exactly when feedback is loudest. The detector therefore needs a short **"was-rising-recently" memory/latch** that holds a flag through the flat phase. (Corpus cases 2, 3.)
- **A room mode is flagged only while building.** It blooms as program excites it (flag), then plateaus / rings down (must clear). Same signal, two phases — cases 4 and 6 are the same source captured in each phase, and are the hardest pair in the corpus (both end flat, but 2 must stay flagged because it rose, 6 must clear because it settled after blooming).

## 2. Sourcing strategy

**Synthetic-first, with real captures as spot-checks.** Every deterministic pass/fail case is a computer-generated signal fed through the existing offline test rig (`FreqTraceTests/AudioAnalysisPipelineTests.swift` — drives the real pipeline actor with synthetic tones, no mic or room needed), because it is exact, repeatable, and can measure flag latency in milliseconds. Each case where real-world mess is load-bearing (real feedback in a real room, a real boomy room mode, real music with its vibrato/beating/harmonics) additionally gets **one representative real capture** as a reality-check that the synthetic thresholds survive contact with the field. Synthetic signals are modeled per the signatures in [anomaly-signatures.md](./anomaly-signatures.md) (correct exponential ring-up, correct modal Q and 200–500 ms decay), not eyeballed.

## 3. The corpus

### Must-flag cases

| # | Case | Source | Pass = | Realism needed |
|---|------|--------|--------|----------------|
| 1 | **Near-threshold ring-up** (slow "singing" feedback) | Synthetic exponential ramp at a defined slow rate + **real** ring-up capture | Flagged **within ~500 ms** of becoming a sustained narrowband peak | Ramp modeled per #19 (exponential lock, dead-steady frequency) |
| 2 | **Ring-up → saturate** (clips flat at the ceiling) | Synthetic ramp-then-limit + **real** capture pushed hot | Flagged through **both** the rising *and* the flat phase — must **not drop when it goes flat** (tests the memory latch) | Correct clip/plateau behavior |
| 3 | **Fast howl** (saturates within ~1 hop — "arrives flat") | Synthetic near-instant onset to flat ceiling | Flagged via the memory even with **no visible rising edge** in the window | Sub-hop onset |
| 4 | **Building room mode** (blooms as program excites it) | Synthetic Q≈20 resonance excited by a burst + **real** boomy-room capture | Flagged during the **build / bloom** phase | Modal Q + 200–500 ms decay per #19 |

### Must-not-flag cases

| # | Case | Source | Pass = | Realism needed |
|---|------|--------|--------|----------------|
| 5 | **Steady sine test tone** (flat from switch-on) — *the anchoring bug* | Synthetic pure sine, constant level | **Zero flags, ever** (structurally excluded — never rose) | Exact |
| 6 | **Settled room mode** (post-bloom, steady/decaying) — *tail of case 4* | Synthetic (later phase of #4) | Zero flags once settled; case-4 flag must **clear** as it settles | Same signal, later phase |
| 7 | **Hand-ramped test tone** (manual level ramp) — *challenge case* | Synthetic slow/crude ramp + optional **real** "riding the fader" capture | **Zero flags** — criteria must tell a crude manual ramp from feedback's exponential lock-and-hold | Slow, crude ramp shape distinct from an exponential lock |
| 8 | **Sustained musical content** — held note / organ drone / synth pad | **Real** recording (synthesis misses vibrato/beating/harmonics) | Zero flags | Real, with natural vibrato/beating and full harmonic series |
| 9 | **Broadband program material** — live music mix + speech | **Real** recording | **Small documented false-flag rate** allowed (not zero) | Real, dense |
| 10 | **Silence / digital zero** (+ a low noise-floor variant) | Synthetic zeros | Zero flags | Exact |

## 4. Acceptance bar

- **Primary, hard bar — zero false negatives on the must-flag set.** Every feedback flavor (1, 2, 3) and the building room mode (4) must be caught. **Missing a real ring is the cardinal sin** and gates everything else.
- **Catchable feedback (1, 2, 4) flagged within ~500 ms** of becoming a sustained narrowband peak — fast enough for a tech to pull it down, matching the detector's ~350 ms sustain evidence window plus confirmation. Saturated/fast feedback (2, 3) flagged via the memory latch (no rising-edge latency requirement, since there may be no visible rising edge).
- **Must-not-flag set — no hard-zero gate.** A **small documented false-flag rate is tolerated permanently**, in exchange for never missing a real anomaly. False positives are the acceptable cost: an over-eager detector is *visible* and tunable, whereas a too-cautious one silently hides what it misses. Reduce false flags by approaching from the permissive side and stop when it is safe and useful in the field, not at a literal zero.
  - In practice the **pure-flat benign cases (5, 10) still land at zero** — the rising-edge principle excludes a flat-from-start signal *structurally*, not by threshold-tuning, so this keeps faith with the original steady-tone bug.
  - The tolerated rate really buys slack on the **hard** must-not-flag cases — the hand-ramped tone (7) and dense real program (9) — which genuinely rise or spike, and where demanding zero would force the criteria dangerously conservative against real feedback.

### Development trajectory

Start **permissive** (accept extra false positives while the criteria are being built) and refine the false-flag rate *down* over iterations — never trade catch-rate for a lower false-flag rate. Come at the acceptance bar from the permissive side.

## 5. Decisions this corpus encodes

| Decision | Ruling |
|---|---|
| Steady room mode | Flag **only while building**, not once settled |
| Saturated / flat-topped feedback | **Must-flag** via a "was-rising-recently" memory latch |
| Sourcing | **Synthetic-first + real spot-checks** (two tiers) |
| Hand-ramped test tone | **Must-not-flag** challenge case (ramp-shape discriminator) |
| Flag latency (catchable ring-up) | **~500 ms** |
| Error priority | **False negatives are the cardinal sin**; approach false-positive reduction from the permissive side |
| Final false-flag bar | **Relaxed** — small documented rate tolerated, no hard-zero gate; catch-rate wins |

## 6. Handoff / what's next on the map (#18)

- **#21 — criteria & thresholds:** must produce a rule that catches all of cases 1–4 (incl. the memory latch for 2/3) while separating case 6 from case 2 (the flat-pair) and case 7 from case 1 (ramp shape). This corpus is its scoring target.
- **Capture task:** record the real spot-check tier — a real feedback ring-up (rideable and pushed-hot), a real boomy-room mode, real sustained music/pad, and real dense program + speech. Synthetic cases are built directly in the offline test rig.
- **Prototype & score (#18 not-yet-specified):** run a candidate criterion against this corpus; graduates now that the cases and bars exist.
