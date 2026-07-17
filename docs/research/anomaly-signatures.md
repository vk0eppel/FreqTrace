# Anomaly Signatures: Feedback vs. Resonance vs. Test Tone vs. Music

**Purpose.** This document characterizes the observable temporal and spectral signatures that distinguish four signal classes in a live-sound microphone capture — (a) acoustic feedback, (b) room resonance, (c) a steady sine test tone, and (d) sustained musical content — so a real-time FFT detector can tell them apart. It feeds the **"Trustworthy anomaly-candidate detection"** wayfinder map, ticket **"Characterize the signatures of feedback, resonance, test tones, and music."** The immediate downstream decision is whether changing FreqTrace's anomaly rule from "sustained (flat-or-growing)" to **"must be growing / ringing up"** can separate real feedback from a benign steady test tone without introducing new blind spots. The short answer, developed in §4, is **"partly, but not as a sole criterion."**

Sourcing note: every substantive claim is cited inline. Where a number comes from an aggregated/secondary source rather than a document that owns it, it is flagged as approximate or uncharacterized. Patents are quoted from Google Patents / USPTO full text.

---

## 1. Class (a): Building acoustic feedback ring (Larsen effect)

**Mechanism.** Feedback is an unintended *positive* feedback loop: loudspeaker output is picked up by the mic, re-amplified, re-emitted. It sustains at whatever frequency satisfies the Barkhausen condition — loop gain ≥ 1 in magnitude with round-trip phase an integer multiple of 360° ([Wikipedia, *Audio feedback*](https://en.wikipedia.org/wiki/Audio_feedback)). The frequency is *not* arbitrary: it is set by the combined resonances of mic/amp/loudspeaker and, importantly, by **room acoustics / comb filtering** and the mic-loudspeaker geometry ([Wikipedia](https://en.wikipedia.org/wiki/Audio_feedback)). Feedback therefore very often lands *on* a room mode — the two classes are physically coupled, which is the deep reason ADR 0001 unified them for v1.

**Growth / envelope dynamics.** Once loop gain exceeds unity, "noise at that frequency will be amplified… The sound level will increase until the output starts clipping, reducing the loop gain to exactly unity" ([Wikipedia](https://en.wikipedia.org/wiki/Audio_feedback)). The build-up is **exponential**: for open-loop gain G > 1 the envelope follows `fbk(t) = G^(t/τ)`, where τ is one round-trip loop time (search-aggregated model, [Grokipedia *Positive feedback*](https://grokipedia.com/page/Positive_feedback) / [*Audio feedback*](https://grokipedia.com/page/Audio_feedback)). Two parameters set the rate:

- **Loop-gain margin** (how far above unity). Just over unity → slow ring-up (the "singing" a tech can catch and pull down); large margin → near-instant howl. An aggregated estimate puts a +20 dB margin at "20 dB per loop, typically within a few ms" (secondary/uncharacterized — treat the exact ms as an *estimate*, [Grokipedia](https://grokipedia.com/page/Audio_feedback)).
- **Loop delay τ** (round-trip acoustic + processing time). A larger room / longer mic-to-speaker path lengthens τ and slows the exponential.

**Practical timescale — the key uncertainty.** The build-up is a genuine ramp, *not* a step, but its duration spans orders of magnitude. Near the threshold it is clearly observable over hundreds of ms (this is exactly the "feedback ringing up" a tech hears and rides down); with a large gain margin it can saturate in a handful of ms — i.e. faster than a single 8192-point / ~43 ms FFT hop, so it would appear "already saturated" to FreqTrace. **No single source pins a canonical ring-up time in ms**; the honest characterization is *"exponential ramp whose observable duration ranges from a few ms to several seconds depending on gain margin and loop delay."* Detectors are deliberately designed to catch the slow, near-threshold case (see §5).

**Spectral prominence / Q.** Extremely narrow — a pure oscillation at one frequency. Sabine's detector treats it as effectively a single spectral line and notches it with a **1/10-octave** filter (US 5,245,665); dbx notches at **1/80-octave** (dbx AFS). So the emitted tone is narrower than the filters needed to remove it — sub-1/10-octave.

**Harmonic structure.** Essentially a **pure tone**: "acoustic resonating feedback signals are generally not accompanied by harmonics whereas desirable voice and music tones are generally rich in harmonics" ([US 5,245,665](https://patents.google.com/patent/US5245665A/en)). This is the single strongest discriminator against music — but note it does **not** separate feedback from a sine test tone, which is also harmonic-free.

**Onset & frequency stability.** Onset is a spontaneous emergence from noise (no external "note"), then locks to a fixed frequency and holds it dead-steady until suppressed or the gain is pulled — a "solid horizontal line on the spectrograph" ([Rational Acoustics / Smaart](https://support.rationalacoustics.com/support/solutions/articles/150000190431-measurement-101-types-of-measurement)). Zero drift once locked.

---

## 2. Class (b): Room resonance / room modes

**Mechanism.** Standing waves between room boundaries; the first axial mode occurs where the boundary spacing equals a half-wavelength ([GIK Acoustics](https://www.gikacoustics.com/blogs/knowledge-base/what-are-room-modes)). Modes are *excited by program material* — they don't self-oscillate. They "store energy and decay slowly compared to nearby frequencies," producing 'one-note bass' / boominess and frequency-response peaks/dips of 20 dB+ ([GIK Acoustics](https://www.gikacoustics.com/blogs/knowledge-base/what-are-room-modes)).

**Envelope dynamics.** A mode **builds while driven and then rings down** when the drive stops — it does *not* grow without bound. Decay is set by the mode's damping: strong, low-damping (high-Q) axial modes "sustain 200–500 ms longer than adjacent frequencies" ([Acoustic Sciences Corp / AES 1986](https://www.acousticsciences.com/technical-papers/room-acoustics-and-low-frequency-damping/)). So over an 8-hop / ~350 ms window a mode looks **flat-or-decaying while sustaining, or a slow ring-down after excitation stops** — crucially it is *plateaued or falling*, not rising, once at steady state.

**Q / bandwidth.** Narrow, and quantifiable from RT60. Modal bandwidth ≈ 2.2/RT60; the worked example gives RT60 = 0.8 s → 2.7 Hz bandwidth, ~0.07 octaves, **Q ≈ 20** at 28.6 Hz ([search-aggregated modal-Q relationship](https://cecas.clemson.edu/cvel/Reports/CVEL-11-028.pdf); [Q/decay relationship](https://www.rp-photonics.com/q_factor.html)). Q relates to decay directly: "the 3-dB bandwidth is approximately twice the decay rate, and Q is approximately the number of rings in the impulse response" ([CVEL / Clemson](https://cecas.clemson.edu/cvel/Reports/CVEL-11-028.pdf)). So a room mode is narrowband but generally *broader-Q than feedback* — feedback is a true single oscillation, a mode is a damped resonance.

**Harmonic structure.** A single resonance is **inharmonic relative to the program** — it sits at the room's geometric frequency, not on the played note's harmonic series. This is why FreqTrace's "harmonically-unrelated" gate already catches it. But modes cluster (axial/tangential/oblique series) without being integer-harmonic.

**Onset & stability.** Onset is program-gated (blooms when material hits the modal frequency), position is **fixed by room geometry** (does not drift with the music), amplitude waxes/wanes with how much program energy lands in-band. On Smaart's spectrograph, ringing shows as "a bright vertical line that may vary slightly in brightness as the energy decays" — explicitly contrasted with feedback's steady horizontal line ([Rational Acoustics](https://support.rationalacoustics.com/support/solutions/articles/150000190431-measurement-101-types-of-measurement)).

---

## 3. Class (c): Steady sine test tone (the benign false-positive)

**Envelope.** After its onset transient, a signal-generator sine is **dead flat indefinitely** — constant amplitude, no growth, no decay. This is precisely why FreqTrace's current "flat-or-growing sustained" rule mis-flags it: a steady tone *is* the flat case.

**Q / bandwidth.** The narrowest possible — a single frequency. In the FFT it occupies one bin plus window-determined spectral leakage skirts; narrower than feedback in principle (feedback has a finite loop bandwidth; a generator tone is mathematically monochromatic).

**Harmonic structure.** **Pure tone, harmonic-free** — identical in this respect to feedback. A high-quality generator produces essentially no harmonics. *This is the crux of the problem:* on the two features FreqTrace currently uses (narrowband + harmonically-unrelated), a test tone and feedback are indistinguishable. They differ mainly in **envelope history** (see §4) and in *provenance* (a tone is deliberately injected, not self-excited) — the latter unobservable from the mic signal alone.

**Onset & stability.** Onset is a deliberate switch-on (may be an abrupt step or a ramp if the user rides the level); frequency is **rock-stable** by design, drift essentially zero (generator-clock-limited). Indistinguishable from locked feedback on frequency stability alone.

---

## 4. Class (d): Sustained musical content (held notes, drones, pads)

**Envelope.** Held notes and pads have an **attack–sustain shape with natural micro-modulation** — vibrato, tremolo, bow/breath noise, ensemble beating. Even a "steady" organ drone is not mathematically flat; a sung note carries vibrato (typ. ~5–7 Hz pitch modulation) and amplitude shimmer. Over 350 ms a real sustain is *slightly modulated*, not a perfectly flat line.

**Q / bandwidth.** Each partial is fairly narrow, but the note is **not a single peak** — it is a *comb* of partials. Per-partial bandwidth is widened by vibrato/portamento smearing across bins.

**Harmonic structure.** **Rich harmonic series** — the defining feature. "desirable voice and music tones are generally rich in harmonics" ([US 5,245,665](https://patents.google.com/patent/US5245665A/en)); Sabine requires a candidate to exceed its harmonics/subharmonics by ≥ 33 dB before calling it feedback, precisely to reject musical tones. FreqTrace's `HarmonicRelation` gate (exclude peaks within 3% of an integer multiple of another peak) is the same idea.

**Onset & stability.** Note onsets are transient-rich (percussive attack, consonant, bow scrape); pitch may drift/portamento/vibrato; notes *change* as the music moves. A sustained pad holds longer but still evolves. Frequency stability is **lower** than any of (a)/(b)/(c).

---

## 5. Comparison table

| Feature | (a) Feedback | (b) Room resonance | (c) Sine test tone | (d) Sustained music |
|---|---|---|---|---|
| **Envelope / growth over ~350 ms** | **Exponential ring-**up then clip-limited plateau; ramp duration ~few ms → seconds (gain-margin dependent) | Builds while driven, **plateau or slow ring-down** (200–500 ms decay); never unbounded | **Flat** indefinitely after onset | Attack then sustain with **micro-modulation** (vibrato/tremolo/beating) |
| **Bandwidth / Q** | Narrowest in practice; single oscillation, sub-1/10-octave (Sabine notches 1/10-oct, dbx 1/80-oct) | Narrow, **finite Q** (~20 typ., bandwidth ≈ 2.2/RT60) | Single bin + leakage; monochromatic | Per-partial narrow but **multi-peak comb**, vibrato-smeared |
| **Harmonic structure** | **Pure tone, no harmonics** | Single/inharmonic (off the program's series) | **Pure tone, no harmonics** | **Rich harmonic series** (≥33 dB test, US 5,245,665) |
| **Onset** | Spontaneous from noise, no external note | Program-gated bloom | Deliberate switch-on | Transient-rich attack |
| **Frequency stability / drift** | Locks and holds, **zero drift** | Fixed by room geometry, zero drift | **Rock-stable** by design | Drifts (vibrato/portamento); changes with the music |

Note the shaded reality: **(a), (b), (c) all read as narrowband + (a)/(c) as harmonic-free + all three as frequency-stable.** The features that already separate music (harmonic richness, drift) do *not* separate a test tone from feedback. The remaining axis is the envelope column.

---

## 6. Can "must be growing" separate the classes?

**Decision point 1 — does feedback have a characteristic build-up?** Yes. It is a genuine exponential ring-up (`fbk(t)=G^(t/τ)`) governed by loop-gain margin and loop delay τ ([Wikipedia](https://en.wikipedia.org/wiki/Audio_feedback), model per [Grokipedia](https://grokipedia.com/page/Positive_feedback)). A rising envelope is therefore a *real, physical* signature of feedback and a legitimate discriminator against a flat test tone. **This is the good news for the proposed rule.**

**But two failure risks bound how far it can be trusted:**

**Risk A — already-saturated feedback (false negative).** Once the loop clips, gain is driven back to exactly unity and the envelope **goes flat at the ceiling** ([Wikipedia](https://en.wikipedia.org/wiki/Audio_feedback)). A "must be *currently* growing" rule would **stop flagging feedback the instant it saturates** — i.e. exactly when it is loudest and most damaging. With a large gain margin, saturation can occur within a single ~43 ms hop, so the growth phase may never appear across an 8-hop window at all. A pure rate-of-rise gate would miss this entirely.

**Risk B — steady-state resonance and sustained tones that plateau (also missed — but that may be acceptable).** A room mode at steady state, and a sustained pad, are *flat or decaying*, not rising — so "must be growing" would *not* flag them. For the mode this is a **real false negative** (a boomy mode is a legitimate anomaly FreqTrace's spec wants surfaced), for the pad it is a *correct* rejection. So the same rule that correctly drops the test tone also drops steady-state room resonance — undesirable given ADR 0001 unifies feedback + resonance under one "anomaly candidate."

**Decision point 2 — does resonance build then plateau, and would "growing" miss it?** Yes and yes. Modes build while driven and then plateau or ring down over 200–500 ms ([ASC/AES](https://www.acousticsciences.com/technical-papers/room-acoustics-and-low-frequency-damping/)); a strict rising-envelope requirement misses a mode that has reached steady state. This is the strongest argument *against* replacing "flat-or-growing" with "growing-only" wholesale.

**Synthesis.** "Must be growing" is a **useful additional discriminator, not a safe replacement**. It cleanly separates a *steady* test tone from *ringing-up* feedback during the build phase, which is the specific bug in scope. It fails for (A) saturated feedback and (B) steady-state resonance. The commercial field (below) resolves this not with rate-of-rise alone but with **rate-of-rise + persistence + harmonic-isolation + peak-to-broadband** combined — no single one carries the decision. A defensible direction for FreqTrace is a *composite*: keep "sustained," add a "was rising at some point in the track's history" bit (a ring-up *ever* occurred), rather than "is rising right now" — this catches feedback across its build *and* saturated phases while still rejecting a tone that was flat from switch-on. (This is a design hypothesis for the separate criteria ticket, not a conclusion of this research.)

---

## 7. How commercial systems discriminate

Commercial feedback suppressors converge on **multi-criterion detection**, never a single test:

- **Sabine FBX (US 5,245,665)** — the canonical patent. Two criteria combined:
  1. **Harmonic isolation:** "the frequency under test is a feedback candidate if it is at least **33 dB greater than its closest harmonics and subharmonics**" (1st/2nd/3rd/0.5×/1.5×) — because feedback lacks harmonics while music is harmonically rich.
  2. **Persistence:** a candidate is confirmed only if it is "one of the three largest magnitude frequencies in **three out of five successive frequency spectrums**" (~0.27–0.45 s of 4096-pt FFTs). Filters are 1/10-octave. Note: FBX uses **persistence, not rate-of-rise**, as its temporal test. ([US 5,245,665](https://patents.google.com/patent/US5245665A/en))

- **dbx AFS (Advanced Feedback Suppression)** — "Precision Frequency Detection" pinpoints the feedback frequency and drops a **1/80-octave** notch; distinguishes **fixed filters** (set during ring-out) from **live filters** (auto-inserted during the show when feedback begins to occur). Public docs describe *where/how narrow* it filters more than the exact detection math ([Harman/dbx "AFS – How It Works"](https://help.harmanpro.com/Documents/395/AFS%20-%20How%20It%20Works.pdf); [dbx AFS2](https://www.avc-group.com/int/en/product/dbx-afs2-advanced-feedback-suppression-processor)).

- **Probabilistic ringing feedback detector (US 8,027,486)** — the most explicit on **rate-of-rise + probability accumulation**, closest to FreqTrace's question:
  - Measures **the difference between consecutive bin magnitudes**; flags rapid growth when "the present magnitude is more than a multiple **M** of the previously-measured magnitude" (howling-type feedback = fast rise).
  - Classifies **three decay/growth ranges** (β₁–β₂ long-period ringing; β₂–β₃ weak/fast-decay ringing; below β₃ = normal room acoustics, no action) — i.e. it does not treat every sustained peak as feedback.
  - Requires **persistence:** "a sufficiently long succession of difference measurements" before triggering; uses **probability counters** per bin that increment only when gain measurements fall in feedback-characteristic ranges.
  - Explicitly handles program material: "speech magnitude levels will fluctuate" and "speech components may partially cancel a feedback event," creating hold regions where probability does not increment. ([US 8,027,486](https://patents.google.com/patent/US8027486/en))

- **Analyzers (Smaart / Rational Acoustics)** — don't auto-suppress; they *surface* feedback for a human. On the **spectrograph**, feedback = a **solid horizontal line** (constant frequency over time) and a **line peak on the RTA**; **ringing** = a **bright vertical line that fades as energy decays** — the horizontal-vs-decaying distinction is exactly the envelope axis of §5 ([Rational Acoustics, Measurement 101](https://support.rationalacoustics.com/support/solutions/articles/150000190431-measurement-101-types-of-measurement)).

**Field consensus:** the durable discriminators are (1) **harmonic isolation** (feedback/resonance are harmonic-free, music is not), (2) **temporal persistence** over a window, and (3) **rate-of-rise** for the specific "howling/building" case — used *together*, with rate-of-rise treated as evidence for the building phase rather than a mandatory gate.

---

## 8. Implications for FreqTrace's criteria (candidates, not decisions)

- **Rate-of-rise is a valid *additional* feature, not a replacement for "sustained."** It separates a *ringing-up* feedback from a *steady* test tone during the build phase — the exact bug — but a *strict* "growing right now" gate would miss saturated feedback (clipped to a flat ceiling) and steady-state room modes.
- **Consider "was ever rising over the track's history"** (a latched build-phase bit) instead of "is rising in the current hop" — catches feedback across both build and saturated phases while still rejecting a tone that was flat from switch-on. (US 8,027,486's probability-accumulation is the field precedent for a latched/accumulated signal rather than instantaneous slope.)
- **A test tone is provenance-invisible from the mic alone.** On narrowband + harmonic-free + stable it is identical to feedback; envelope history is the only in-signal separator. If FreqTrace ever adds a signal generator that's routed internally, *known-generator-frequency suppression* would be a cheaper, exact fix than inferring it from the spectrum.
- **Peak-to-broadband / harmonic-isolation margin** (Sabine's 33 dB) is a stronger, better-sourced discriminator than FreqTrace currently exploits and cheap to add — quantify how far the peak stands above its own harmonics/subharmonics, not just above shoulder bins.
- **Don't drop steady-state resonance detection.** ADR 0001 unifies feedback + resonance; a growth-only rule silently narrows scope back to feedback-only. If growth becomes required, resonance needs its own path (e.g. persistence + inharmonicity without a rise requirement).
- **Micro-modulation could separate music from tone/feedback:** held musical notes carry vibrato/beating; feedback and generator tones do not. Frequency-stability variance over the window is an untapped, cheap feature (not yet sourced to a detector patent — treat as a FreqTrace hypothesis).
- **Timescale caveat for tuning:** feedback ring-up spans a few ms to seconds; at large gain margins it saturates faster than one 8192-pt hop, so any rate-of-rise threshold must tolerate feedback that *appears* to arrive already-flat. Tune against the near-threshold ("singing") case the detector is actually meant to catch early.

---

## 9. Sources

Primary / patent:
- [US Patent 5,245,665 — Sabine, feedback detection (harmonic isolation + persistence)](https://patents.google.com/patent/US5245665A/en)
- [US Patent 8,027,486 — Probabilistic ringing feedback detector (rate-of-rise + probability)](https://patents.google.com/patent/US8027486/en)
- [Harman/dbx — "Advanced Feedback Suppression (AFS): How It Works"](https://help.harmanpro.com/Documents/395/AFS%20-%20How%20It%20Works.pdf)

Technical / reference:
- [Wikipedia — Audio feedback (Barkhausen condition, exponential growth, frequency selection)](https://en.wikipedia.org/wiki/Audio_feedback)
- [Rational Acoustics / Smaart — Measurement 101 (feedback vs. ringing on the spectrograph)](https://support.rationalacoustics.com/support/solutions/articles/150000190431-measurement-101-types-of-measurement)
- [Acoustic Sciences Corp — Room Acoustics and Low Frequency Damping (AES 1986; modal decay 200–500 ms)](https://www.acousticsciences.com/technical-papers/room-acoustics-and-low-frequency-damping/)
- [GIK Acoustics — What Are Room Modes (energy storage, slow decay, 20 dB+ peaks)](https://www.gikacoustics.com/blogs/knowledge-base/what-are-room-modes)
- [CVEL/Clemson — Q-factor and Resonance in Time and Frequency Domain (Q↔decay↔bandwidth)](https://cecas.clemson.edu/cvel/Reports/CVEL-11-028.pdf)
- [RP Photonics — Q factor (decay-time relationship)](https://www.rp-photonics.com/q_factor.html)
- [dbx AFS2 product/technical page (1/80-octave notch, fixed vs live)](https://www.avc-group.com/int/en/product/dbx-afs2-advanced-feedback-suppression-processor)

Secondary / aggregated (flagged as approximate where cited):
- [Grokipedia — Audio feedback / Positive feedback (exponential-growth model, ring-up rate estimate)](https://grokipedia.com/page/Audio_feedback)

**Weakly-supported / uncharacterized claims (do not over-trust):**
- Exact feedback ring-up time in ms — *no primary source pins a canonical value*; range "few ms → seconds" is inferred from the exponential model plus one aggregated estimate. Treat any single ms figure as an estimate.
- The +20 dB → "within a few ms" figure is search-aggregated (Grokipedia), not from a measurement paper.
- Micro-modulation as a music discriminator is a FreqTrace hypothesis, not sourced to a detection patent.
