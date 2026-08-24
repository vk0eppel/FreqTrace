# Anomaly Detector: Real Signals & Threshold Cross-Check

**Purpose.** Two desk-research questions, both feeding the trustworthy-detection line of work:

1. **Real recordings / datasets** — the user has no room/PA access, so what *existing public* audio can be run through an offline FFT to validate the detector against real signals (feedback ring-ups, room modes, feedback-suppression corpora)? This is the substance of ticket **#37 (real captures)**, which [anomaly-criteria-prototype.md](./anomaly-criteria-prototype.md) deferred as "not blocking" but required for confirming the synthetic conclusions.
2. **Threshold cross-check** — our detector thresholds were pinned against a *synthetic* corpus (#36). What concrete numbers do published/open-source feedback detectors use, to sanity-check ours — **especially the two UPPER bounds the prototype left unpinned** (hotness ceiling, fall-away margin), which gate the cardinal false-negative error per the prototype's handoff (#38)?

It builds on [anomaly-signatures.md](./anomaly-signatures.md) (the physics + commercial-system survey) and [anomaly-criteria.md](./anomaly-criteria.md) / [anomaly-criteria-prototype.md](./anomaly-criteria-prototype.md) (the four-state criteria and the values we picked). It does **not** re-derive those — it adds the two things that document explicitly said still needed real signals.

**Sourcing convention (same as anomaly-signatures.md):** every substantive claim is cited inline. Exact numbers are quoted from the document/code that owns them. Aggregated/secondary or weakly-supported claims are flagged in place, and collected in the final section.

---

## Part 1 — Real recordings & datasets for offline validation

### Headline

There is **one genuinely strong, high-trust, directly-usable dataset**: the **HCMS** corpus (KU Leuven, CC-BY-4.0), purpose-built for howling detection, annotated, and — crucially — it **contains the ring-up phase**, not just steady howl. Everything else is either incidental (Freesound/sound-effect clips of uncertain provenance) or code-without-audio. Room-mode-specific corpora with excitation-and-decay labelling appear **not to exist publicly** as a packaged dataset — a null result stated plainly below.

### 1.1 HCMS — Howling Corrupted Music and Speech (KU Leuven) — **RECOMMENDED**

The primary contribution of Mounir, Bernardi & van Waterschoot, *"Robust and early howling detection based on a sparsity measure"* (EURASIP J. Audio Speech Music Process. 2025;2025(1):14, open access, [Springer / EURASIP](https://asmp-eurasipjournals.springeropen.com/articles/10.1186/s13636-025-00399-1)) is a **new annotated dataset** described in the paper as "significantly larger and more diverse than existing datasets containing realistic howling artifacts."

- **Where:** KU Leuven Research Data Repository, DOI **[10.48804/EOW7OF](https://rdr.kuleuven.be/dataset.xhtml?persistentId=doi:10.48804/EOW7OF)** (record: [Lirias 3119197](https://lirias.kuleuven.be/3119197)).
- **License:** **CC-BY-4.0** — usable with attribution, no access restrictions, all files public (per the RDR record). This is the best-licensed option found.
- **Contents:** total ~162 files, **153.7 MB**; **WAV** audio + **CSV** data files (RDR record lists 102 audio, 58 data, 2 text). The audio is **28 music + 30 speech excerpts, each 20 s** (music: 7 pieces across genres incl. jazz/opera from 2 databases; speech: male/female in Chinese/English/Dutch/Russian from an audiobook set) ([EURASIP paper](https://asmp-eurasipjournals.springeropen.com/articles/10.1186/s13636-025-00399-1); dataset record).
- **Ring-up is present (the important part):** "Each file is a 20 s excerpt where the howling is simulated to start between the 8th and 9th second… by feeding the music or speech source signal to a closed-loop system with a varying broadband gain. A total of 8 acoustic impulse responses (AIRs) were used for the simulations, hence covering a wide range of howling frequencies." So each file has ~8 s of clean program, then a **genuine closed-loop instability building up** — exactly the ring-into-existence FreqTrace's rise gate targets.
- **Annotated + curated:** the CSVs carry ground-truth (the paper's whole evaluation is a per-STFT-frame howling/no-howling PR-AUC on this set); the final set was pruned by "three experts… to eliminate unsuitable examples."
- **Trust:** **HIGH** — first-party academic dataset from the KU Leuven feedback-control group (van Waterschoot), tied to a peer-reviewed open-access paper, with an explicit annotation and curation procedure.
- **Honest caveat for #37:** the howling is **simulated, not literally room-captured** — but it is *real closed-loop simulation* (real music/speech → real AIRs → a broadband gain driven unstable), so the howling artifact and its exponential build-up are physically realistic, not a synthetic sine pasted on. For our purpose (does the rise gate + −25 dBFS floor fire on a real building ring embedded in real program material?) this is close to ideal, and much stronger than our current all-synthetic corpus. It does **not**, however, give us a *literally-captured* boomy-room mode — see the null result in §1.4.

### 1.2 NINOS²-T reference code (same authors) — code, not audio

[github.com/maganino/Howling-Detection-NINOS2T](https://github.com/maganino/Howling-Detection-NINOS2T) — **MIT-licensed** Python implementing the paper's detector and the six baseline features (PTPR/PAPR/PHPR/PNPR/IPMP/IMSD). It ships **no audio** (it reads the HCMS files locally — `howling_params.py` points at a local `Howling_NINOS/Dataset/Processed` path). Value for us is twofold: (a) it's runnable reference code to reproduce baseline-feature behaviour, and (b) its parameter tables are usable threshold-sweep data (mined in Part 2). Trust: HIGH for provenance (first-party), but you must pair it with the HCMS download to have signals.

### 1.3 Feedback-suppression toolkits (code + some example audio)

- **FACT — Feedback Analysis and Cancellation Toolkit** ([github.com/marc1701/FACT](https://github.com/marc1701/FACT)) — MATLAB. Simulates feedback via a loop-gain model and detects it (PAPR/PHPR/PNPR/PTPR + persistence). **No stated license** (GitHub API reports none → default "all rights reserved"; usable for *reading* thresholds, not for redistributing code/audio). Mined for numbers in Part 2.
- **yiliang2333/Real-time-howling-suppression** (MATLAB/Simulink) and **cirilln/Automatic_Feedback_Suppression** (Pure Data) — real-time NHS implementations; useful as algorithm references, not as datasets.

### 1.4 Room-mode / low-frequency resonance recordings — **NULL RESULT**

No public, packaged, *labelled* dataset of **room modes excited-then-decaying** was found. Room-mode behaviour is documented (RT60/modal-decay measurements, GIK/ASC references already cited in [anomaly-signatures.md](./anomaly-signatures.md) §2), and REW-style measurements produce impulse responses from which modal ring-down is derivable — but that's a measurement *method*, not a downloadable corpus with anomaly labels. **Stated plainly: for the room-mode class, there is no real-signal substitute of the HCMS calibre.** Options if #37 wants to cover it: (a) derive modal ring-down from a public room-impulse-response dataset (e.g. open RIR collections) convolved with a swept/gated excitation — but that's synthesis, only marginally more "real" than what #36 already did; (b) accept the prototype's existing modelled room-mode bloom as the room-mode coverage and treat HCMS as the *feedback*-class real-signal check. This is an honest gap, not an oversight.

### 1.5 Incidental clips (LOW trust — provenance-poor)

Usable only as informal spot-checks, not validation:
- **Freesound** feedback clips, CC-licensed but uncontrolled recording chains, e.g. [chimerical "Mic feedback.wav"](https://freesound.org/people/chimerical/sounds/106271/) (CC-BY-NC), [zerolagtime "Microphone Feedback" pack](https://freesound.org/people/zerolagtime/packs/16645/), [JavierSerrat "Microphone feedback.wav"](https://freesound.org/s/470111/) (SM58 + JamVox monitor).
- **BigSoundBank** [52 free "Larsen" SFX](https://bigsoundbank.com/search?q=larsen) (WAV/MP3), some labelled by pitch (~2.4/2.6/2.9/5.8/10.6 kHz loops). Useful because a few are *pitch-labelled*, but these are sound-effect renderings — most are already-saturated howls with no clean ring-up, and licensing/provenance vary per file. **Trust: LOW** (incidental).

### 1.6 Recommendation for #37

**Pull HCMS ([DOI 10.48804/EOW7OF](https://rdr.kuleuven.be/dataset.xhtml?persistentId=doi:10.48804/EOW7OF)).** It is the one dataset that (a) is high-trust and first-party, (b) is properly licensed (CC-BY-4.0), (c) is annotated with ground truth, and (d) contains the **ring-up** dynamics the detector is built around, embedded in real music/speech (which also exercises the harmonic gate against real program material — the exact thing the prototype deferred to #37). Run its 20 s excerpts through FreqTrace's offline FFT path and score the four-state detector's flag/latency against the CSV ground truth. Treat NINOS²-T as reference code to cross-check baseline-feature values, and FACT as a second implementation to read numbers from. **Do not** rely on Freesound/BigSoundBank for anything but eyeball spot-checks. For the room-mode class, accept the documented gap (§1.4) rather than pass off synthesis as real capture.

---

## Part 2 — Cross-checking our thresholds against real implementations

Our values, restated (harness dBFS-referenced terms, from [anomaly-criteria-prototype.md](./anomaly-criteria-prototype.md)): detectability floor **~−25 dBFS**; rise **~6 dB over ~300 ms**; fall-away/release margin **~8 dB**; hotness/absolute trigger **~−6 dBFS**; persistence — confirm **~2 hops (~85 ms)**, rise window **~300 ms**.

The single most important framing finding up front: **the published field splits into two kinds of threshold, and neither kind pins our two open UPPER bounds.** (a) The academic/open-source detectors (PAPR/PHPR/PNPR/PTPR + persistence) are **relative** ratios — peak-vs-average, peak-vs-harmonic, peak-vs-neighbour — and explicitly **not absolute dBFS levels**, so they cannot pin a hotness *ceiling* or a fall-away *margin* in our sense. (b) The rate-of-rise patent that is closest to our model (US 8,027,486) **deliberately refuses to pin its numbers**, calling them operational-tuning choices. So the external literature *leaves open* exactly the two knobs #36 left open — a substantive, non-obvious result detailed in §2.6.

### 2.1 Sabine FBX — US 5,245,665 (harmonic isolation + persistence)

Exact quotes ([Google Patents](https://patents.google.com/patent/US5245665A/en)):

- **Harmonic isolation:** "the frequency under test is a feedback candidate if it is at least **33 dB greater than its closest harmonics and subharmonics**."
- **Persistence:** a candidate is confirmed if the frequency "occurs in three of these positions, corresponding to the frequency being one of the three largest magnitude frequencies in **three out of five successive frequency spectrums**."
- **Notch width:** "notch filtering of a width from one-fourth to one-thirtieth of an octave, such as **one-tenth of an octave**."
- **FFT/rate:** "a conventional **4096 point FFT** with a resolution of **10.755 Hz**"; the sample stream is "generated **45,000** times [per] second… Nyquist frequency of 22.5 KHz." → frame period ≈ 4096/45000 ≈ **91 ms**, so "3 of 5 spectra" ≈ a **~273 ms confirmation inside a ~455 ms window**.
- **Filter depth:** "N in the range generally from one to forty dB, preferably… one to six dB, and in most cases 3 dB or less" (this is *suppression* depth, not a detection threshold).

Relevance: Sabine's temporal test is **persistence, not rate-of-rise or absolute level** — no hotness/fall-away analogue. Its 33 dB harmonic-isolation margin is the number our harmonic-gate discussion already cross-references (prototype §"Binary vs. Sabine").

### 2.2 Probabilistic ringing detector — US 8,027,486 (the closest model to ours)

This is the patent whose structure most resembles our rise + memory approach, and it is **explicit that its thresholds are unspecified design choices** ([Google Patents](https://patents.google.com/patent/US8027486B1/en)):

- **Rate-of-rise multiple M:** "**M should be selected to be greater than about 1**" — no upper value given.
- **Decay/growth boundaries β₁, β₂, β₃:** all stated as design choices — "The selection of β₁ is a design choice: a larger value will detect more slowly decaying ringing events"; "β₃… should probably be selected **above the noise floor**"; "β₂… should be selected to maximize the detection of weak-ringing events." It supports "**more than one range of detection**, for example for building, strong-ringing and weak-ringing feedback."
- **How to pick them:** "M and β **may be selected by analysis and calculation, but are probably better selected and/or refined through operational testing**."
- **Dwell/persistence:** "the triggering change characteristic such as the gain **will need to be stable for a period of time**… it is important that the gain measurements **dwell** within a range of characteristic feedback"; "a period may be selected for which gain values must dwell before detection… such a period **may be different for different frequencies**." No ms value given.

Relevance: strongly **validates our *structure*** (a rate-of-rise trigger + accumulated persistence + a decay classification that treats "normal room acoustics" separately) but **pins none of our numbers**. Its explicit "refine through operational testing" is, in effect, the field telling us the exact thresholds are corpus/room-tuned — which is exactly why #36 couldn't pin the upper bounds from synthetics and why #37/HCMS is the right next step.

### 2.3 van Waterschoot & Moonen — JAES 2010 spectral-criteria thresholds

*"Comparative evaluation of howling detection criteria…"* (JAES 58(11):923–940, 2010; author's abstract page + example configurations at [KU Leuven ESAT](https://ftp.esat.kuleuven.be/pub/SISTA/vanwaterschoot/abstracts/09-207.html), PDF `09-207.pdf`). Example detector configurations quote concrete thresholds:

- **PHPR (peak-to-harmonic power ratio):** **40, 42, 44 dB** across example configs.
- **PNPR (peak-to-neighbouring power ratio):** **12 dB**.
- **IMSD (interframe magnitude slope deviation):** **0.1, 0.25, 0.5, 1 dB**.
- **FEP** (combined feature-emphasis probability): thresholds **0.9 / 0.95 / 0.99**.

Relevance: PHPR at **40–44 dB** *exceeds* Sabine's 33 dB harmonic margin — i.e. real detectors demand a *harmonic-freeness* even stricter than the 33 dB we cross-reference, which strengthens (not weakens) the case that FreqTrace's harmonic gate is doing load-bearing work. But note all of these are **relative** power ratios; **none is an absolute dBFS level**, so none maps onto our hotness or fall-away.

### 2.4 FACT toolkit — actual code defaults

From the [FACT](https://github.com/marc1701/FACT) README example configurations and defaults:

- **PAPR threshold: "20" dB** (secondary detector, Example 1).
- **Persistence (PMP): "8" frames** (primary detector, Example 1).
- **Loop gain: "−15" dB** (both examples).
- Analysis: **frame 256 samples, 75% overlap, fs 4410 Hz** → hop = 64 samples ≈ **14.5 ms/frame** → **8-frame PMP ≈ 116 ms persistence**; buffer 16 frames; max 8 simultaneous howls.

Relevance: a **relative** peak-to-average of 20 dB (again, not absolute), and a **~116 ms persistence** requirement — directly comparable to our persistence, see §2.5. (License: none stated — read-only use.)

### 2.5 NINOS²-T code — threshold **sweep ranges** used in the paper

`howling_params.py` in [NINOS²-T](https://github.com/maganino/Howling-Detection-NINOS2T) defines the exact threshold grids the EURASIP paper sweeps (i.e. the *plausible operating ranges* the authors considered), which is unusually useful primary evidence of where these numbers live:

- Spectral power-ratio thresholds (PTPR/PAPR/PHPR/PNPR) are swept over dB grids: `th_list2 = [28…64 step 6] dB`, `th_list3 = [32…54 step 2] dB`, `th_list4 = [9, 17…45 step 4] dB`, `th_list5 = [6…21 step 3] dB` — i.e. the harmonic/neighbour features live in a **~6 dB to ~64 dB** relative band, consistent with §2.3.
- Temporal-feature persistence ("states") swept over `[4, 8, 16, 32, 64, 96]` frames at **50 frames/s** (`FRAMES_PER_SEC = 50` → 20 ms/frame) → **80 ms to 1.9 s** persistence windows.
- `SAMPLE_RATE = 16000`, windows up to 4096, and a 5 s `DET_TIME_OFFSET`. Harmonic sets swept over the 2nd / 2nd–3rd / 2nd–4th harmonics; neighbour sets similarly — matching the "closest harmonics/subharmonics" framing.

Relevance: confirms the field treats these as **swept operating ranges refined on a corpus**, not fixed constants — reinforcing US 8,027,486's "refine through operational testing." The **persistence** grid (80 ms–1.9 s) brackets our confirm+rise timing.

### 2.6 Verdict per FreqTrace value

| Our value | External evidence | Agree / contradict / leave-open |
|---|---|---|
| **Detectability floor ~−25 dBFS** | Field motivates a floor in principle — "howling should only be suppressed when it is **sufficiently loud**," howling "eventually has large power compared to speech/audio" (van Waterschoot criteria rationale, [KU Leuven](https://ftp.esat.kuleuven.be/pub/SISTA/vanwaterschoot/abstracts/09-207.html)); US 8,027,486 sets β₃ "**above the noise floor**." But the detectors are *relative*, so **no source pins −25 dBFS as an absolute value.** | **Leave-open (supported in principle, not in number).** Our floor is the load-bearing knob per #36; the external work agrees a floor *should exist* but can't confirm its value. HCMS can pin it empirically. |
| **Rise ~6 dB / ~300 ms (≈20 dB/s)** | US 8,027,486 uses a rate-of-rise multiple **M > ~1** but **gives no numeric value**; buildup is "exponential." No paper pins a dB/s. | **Leave-open, no contradiction.** Structurally endorsed (rate-of-rise is a real, used trigger); the exact 6 dB/300 ms is unconfirmed either way. |
| **Fall-away / release ~8 dB** | US 8,027,486's β₁–β₃ decay-range boundaries are the direct analogue — and are explicitly **"design choices… refined through operational testing,"** no numbers. No other source pins a release margin. | **LEAVE-OPEN — this is the field's open knob too (see note).** |
| **Hotness / absolute trigger ~−6 dBFS** | All spectral detectors are **relative ratios** (PAPR 20 dB, PHPR 40–44 dB, PNPR 12 dB) — **not absolute dBFS**. No source found pins an absolute-level "screaming-hot" ceiling. | **LEAVE-OPEN — no external anchor exists (see note).** |
| **Persistence: confirm ~2 hops (~85 ms); rise window ~300 ms** | Sabine "3 of 5 spectra" ≈ **~273 ms confirm / ~455 ms window** (91 ms frames); FACT PMP **8 frames ≈ 116 ms**; NINOS²-T persistence grid **80 ms–1.9 s**. | **Agree (at the fast end).** Our ~85 ms confirm + ~300 ms rise window sits at the **short/fast** end of the real range — consistent with FACT's 116 ms and the "early detection" goal, faster than Sabine's ~273 ms. Reasonable given our brief is *catch the ring early*; no contradiction, but we are among the more aggressive. |

### Explicit note on the two UPPER bounds (#36's cardinal-error knobs)

The prototype flagged that the **upper** bounds of **hotness** and **fall-away** were unpinned by synthetics, and that they gate the worst error (too-high hotness misses an arrives-flat howl; too-large fall-away over-persists a settled mode). **The external primary sources do not close either bound, and it is worth being precise about *why*:**

- **Hotness ceiling:** no published detector expresses a trigger as an **absolute** signal level at all — they use *relative* peak-to-average/harmonic/neighbour ratios (PAPR/PHPR/PNPR). There is therefore **no external number to borrow** for an absolute −6 dBFS-style ceiling. This is not "we didn't find it"; it's that the mainstream detector design **doesn't use that quantity**. (FreqTrace's hotness trigger exists precisely for the *arrives-flat* case where the relative-rate detectors have no rising edge to work with — a case the literature mostly sidesteps by requiring persistence instead.)
- **Fall-away margin:** the one patent that models decay/release ranges (US 8,027,486, β₁–β₃) **explicitly declines to specify them**, calling them operational-tuning parameters "refined through operational testing." So the field's own answer for our fall-away upper bound is *"tune it on real signals"* — which is exactly #37.

**Conclusion for #38:** the external evidence **confirms our structure** (rate-of-rise trigger + persistence + a separate decay/normal-room classification is the standard shape; harmonic-isolation is real and even stricter than we use) and **agrees at the fast end on persistence**, but it **cannot pin the detectability floor, the rise magnitude, the hotness ceiling, or the fall-away margin** — the first three because the field uses relative not absolute quantities, the fourth because the owning patent deliberately leaves it open. This *reinforces* the prototype's handoff: ship #38 with **conservative defaults** on hotness and fall-away and treat pinning them as **required** follow-up — and the right tool to pin them is now identified: **run HCMS ([10.48804/EOW7OF](https://rdr.kuleuven.be/dataset.xhtml?persistentId=doi:10.48804/EOW7OF)) through the offline path** and sweep the two bounds against its real, annotated ring-ups the same way #36 swept against synthetics.

---

## Sources

Primary / patents & first-party:
- [US 5,245,665 — Sabine (33 dB harmonic isolation, 3-of-5 persistence, 1/10-oct notch, 4096-pt/45 kHz FFT)](https://patents.google.com/patent/US5245665A/en)
- [US 8,027,486 — Probabilistic ringing feedback detector (rate-of-rise M>~1, β₁–β₃ decay ranges as design choices, dwell persistence)](https://patents.google.com/patent/US8027486B1/en)
- [HCMS dataset — KU Leuven RDR, DOI 10.48804/EOW7OF (CC-BY-4.0, WAV+CSV, 153.7 MB, annotated ring-ups)](https://rdr.kuleuven.be/dataset.xhtml?persistentId=doi:10.48804/EOW7OF) · [Lirias record](https://lirias.kuleuven.be/3119197)
- [Mounir, Bernardi & van Waterschoot — "Robust and early howling detection based on a sparsity measure" (EURASIP JASMP 2025, open access; introduces HCMS)](https://asmp-eurasipjournals.springeropen.com/articles/10.1186/s13636-025-00399-1)
- [van Waterschoot & Moonen — "Comparative evaluation of howling detection criteria" (JAES 2010; PHPR 40–44 dB, PNPR 12 dB, IMSD 0.1–1 dB)](https://ftp.esat.kuleuven.be/pub/SISTA/vanwaterschoot/abstracts/09-207.html)
- [NINOS²-T reference code (MIT; threshold sweep grids in `howling_params.py`)](https://github.com/maganino/Howling-Detection-NINOS2T)

Open-source implementations:
- [FACT — Feedback Analysis and Cancellation Toolkit (MATLAB; PAPR 20 dB, PMP 8 frames ≈116 ms, loop gain −15 dB; no stated license)](https://github.com/marc1701/FACT)
- [yiliang2333/Real-time-howling-suppression (MATLAB/Simulink)](https://github.com/yiliang2333/Real-time-howling-suppression) · [cirilln/Automatic_Feedback_Suppression (Pure Data)](https://github.com/cirilln/Automatic_Feedback_Suppression)

Incidental / low-trust (spot-checks only):
- [Freesound "Mic feedback.wav" (chimerical, CC-BY-NC)](https://freesound.org/people/chimerical/sounds/106271/) · [zerolagtime pack](https://freesound.org/people/zerolagtime/packs/16645/) · [JavierSerrat](https://freesound.org/s/470111/)
- [BigSoundBank — 52 "Larsen" SFX (some pitch-labelled)](https://bigsoundbank.com/search?q=larsen)

**Weakly-supported / flagged claims (do not over-trust):**
- HCMS howling is **simulated** (closed-loop-with-AIRs), not literally room-captured — realistic build-up, but not a raw room recording. High-trust as *feedback* real-signal; not a room-mode capture.
- **No public labelled room-mode (excite-then-decay) dataset was found** — §1.4 is a genuine null result, not an incomplete search; room-mode real-signal coverage for #37 has no HCMS-calibre option.
- FACT's exact PAPR=20 dB / PMP=8 defaults are **example-config values** in its README, not necessarily authors' recommended production constants; treat as illustrative.
- van Waterschoot PHPR/PNPR/IMSD figures are **example detector configurations** from the abstract page, representative of the operating range rather than a single canonical threshold.
- The mapping of any of these **relative** ratios onto FreqTrace's **absolute** dBFS thresholds is intentionally *not* made — they measure different quantities; §2.6 treats that as "leave-open," not agreement.
