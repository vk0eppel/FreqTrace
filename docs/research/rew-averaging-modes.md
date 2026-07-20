# REW (Room EQ Wizard) Averaging Modes — What Each Actually Does

Research note surveying every averaging mode REW offers, its exact DSP operation, and which are
**time-averaging analogues** to a live analyzer's Fast/Slow exponential weighting vs. which are
**static/spatial** averaging that has no live-RTA equivalent. Context: FreqTrace is a live real-time
analyzer whose only current averaging is IEC exponential time weighting (Fast 125 ms / Slow 1 s) on the
live power spectrum; this note is a menu of what REW does that a live tool *could* borrow.

Sources are REW's own Help pages (John Mulcahy's official docs) plus his forum posts. Primary URLs
inline per claim.

**Bottom line:** Only REW's **RTA time-averaging family** (Live/None, numeric N-block, Exponential,
Forever) is analogous to Fast/Slow — those average successive spectra *over time* from one continuous
input. Everything else (sweep pre-averaging, the All-SPL Vector/RMS/dB/phase averages, spatial
averaging) combines *separate captured measurements* and is meaningless for a scrolling live display.
Frequency-domain **smoothing** (1/N-octave, Var, psychoacoustic, ERB) is orthogonal to all of it — it
averages across *frequency within one spectrum*, not across time or measurements, and is the single
most directly transferable idea for a live RTA.

---

## 1. RTA time-averaging (the live-analyzer family)

Source: [RTA / Spectrum help](https://www.roomeqwizard.com/help/help_en-GB/html/spectrum.html). REW's RTA
runs a continuous FFT on live input and its "Averages" selector sets how successive FFT blocks are
combined over time. This is the only REW family that is a true live time-average.

| Mode | What it does |
|---|---|
| **Live / None** | *"The plot can be set to show the live input as it is analysed or to show the result of averaging"* — i.e. no averaging, each block replaces the last. Analogue of Fast=1.0 / no smoothing. |
| **Numeric N averages** (1, 2, 4, 8, …) | *"Selecting a number for averages results in that many measurements being averaged to produce the result, with the oldest measurement being removed from the average as each new measurement is added."* A **sliding rectangular (boxcar) window** of the last N blocks — a **forgetting, linear** average. Converges quickly, then tracks changes with a fixed N-block lag. |
| **Exponential** (several modes) | *"There are several Exponential averaging modes, which give greater weighting to more recent inputs. The figure shown in the selection box is the proportion of the old value which is retained when a new measurement is added, the higher the figure the more heavily averaged the display becomes."* This is a **running exponential average (EMA)**: `new = α·old + (1−α)·block`, where the selectable figure **is** the retained proportion α (larger α = heavier averaging). The weight is set **directly as α**, not as a time constant — REW does not expose a seconds-based τ here; the effective time constant is `α`'s equivalent tied to the FFT block rate. This is the direct conceptual match to FreqTrace's Fast/Slow EMA, except FreqTrace derives α from a physical τ and Δt whereas REW lets the user pick α. |
| **Forever** | *"There is also a Forever averaging mode which averages all measurements with equal weight since the last averaging reset."* A **cumulative (infinite, non-forgetting) linear** average — every block ever seen weighted equally; noise floor keeps improving as √N. **Stop at:** *"In Forever averaging the Stop at option allows the RTA to be stopped when a configured number of averages is reached."* |

**Forward "N averages" vs. "Forever":** N-averages **forgets** (sliding window of the last N blocks,
stays responsive to change), Forever **never forgets** (equal-weight accumulation since reset, keeps
sharpening but stops tracking a changing signal). Both are *linear/equal-weight*; only Exponential is
recency-weighted.

**Peak / Max hold is separate, not an averaging mode.** Same page:
*"The Peak Hold and Peak Decay controls set how long, in seconds, a peak value is held and how quickly,
in dB per second, the peak values decay. If Peak Hold is set to 0 the peak values are not held at all.
If Peak Decay is set to 0 the peak trace does not decay."* It's an overlaid max-hold trace on top of
whatever averaging is active — analogous to FreqTrace's existing Peak Hold, not a time-average.

**Coherent averaging (RTA option, distortion-oriented, not a magnitude time-average):**
*"If it is selected the FFT data is phase aligned according to the phase of the fundamental before
averaging … if the harmonic levels are varying coherent averaging will converge to their average level
whilst magnitude averaging will converge to their rms level."* Complex/phase-aligned averaging to pull
periodic signals out of noise — niche, only relevant when you have a coherent reference.

### 2. What domain does the RTA average in?
REW's RTA describes its default as **"magnitude averaging"** (contrasted above with coherent/complex
averaging), and the contrast note — magnitude averaging *"will converge to their rms level"* — confirms
the numeric/exponential/Forever modes operate on **magnitude in a mean-square / RMS sense** (energy
domain), not complex. This matches FreqTrace's choice to average the **power spectrum**, and matches
REW's explicit RMS-across-measurements math in §4.
Source: [spectrum.html](https://www.roomeqwizard.com/help/help_en-GB/html/spectrum.html).

---

## 3. Measurement (sweep) averaging — synchronous pre-averaging

Not a live mode: this averages **repeated sweeps of the *same* stimulus** into one measurement, purely
for noise reduction. From
[Making Measurements](https://www.roomeqwizard.com/help/help_en-GB/html/makingmeasurements.html):
*"If Repetitions is more than 1 REW uses synchronous pre-averaging, capturing the selected number of
sweeps per measurement and averaging the results to reduce the effects of noise and interference"*, and
*"The pre-averaging can improve S/N by almost 3 dB for each doubling of the number of sweeps."*
Repetitions are powers of two (1, 2, 4, 8, 16). Because the sweeps are time-synchronous and identical,
this is **coherent (time-domain) averaging** of the captured responses — the room response reinforces,
uncorrelated noise cancels (√N ⇒ ~3 dB/doubling). **No live-RTA analogue** (there is no repeatable
stimulus to sync to in live sound).

---

## 4. Multiple-measurement / spatial averaging (All SPL graph)

Not live: these combine **several already-captured, saved measurements** into one trace, chiefly for
room-EQ spatial averaging across mic positions. Source:
[All SPL Graph help](https://www.roomeqwizard.com/help/help_en-GB/html/graph_allspl.html).

| Button | Operation | Domain | Use |
|---|---|---|---|
| **Vector average** | *"averages the currently selected traces taking into account both magnitude and phase"* | **Complex** (phase-aware, coherent) | Same-position, or time+level-aligned measurements. Can produce phase-cancellation dips — *not* what the ear hears across a room. |
| **RMS average** | *"converts the dB values to linear magnitudes, those magnitudes are then squared, summed and divided by the number of measurements, the square root of the result is taken, then the value is converted back to dB. Phase is not taken into account, measurements are treated as incoherent."* Same as the **"Average the responses"** button. | **Power / mean-square** (incoherent) | Spatial averaging across positions (after **Align SPL**). The standard room-EQ choice. |
| **RMS + phase avg.** / **dB + phase avg.** | *"produce an RMS or dB average of the magnitudes and use vector average for the phases"* | Hybrid: magnitude in power(RMS)/dB, phase vector-averaged | Multiple measurements of a source when you need phase (e.g. rePhase) without vector-average magnitude dips. |
| **Magnitude (dB) average** | Arithmetic mean of the dB (log-magnitude) values | **Log-magnitude** | Simple visual mean; differs from RMS because it averages in dB not energy. |

Supporting alignment tools (not averages themselves): **Align SPL** — *"adjusts all the currently
selected SPL measurements so that they have the same average SPL over a selected span"* (removes
level differences from differing source distances); **Cross corr align** — *"time aligns the currently
selected measurements by cross correlation of their windowed impulse responses"* prior to vector
averaging.

Key distinction (Mulcahy, [AVNirvana](https://www.avnirvana.com/threads/difference-between-rms-average-and-vector-average.12957/)):
**vector = coherent/complex** (preserves phase, simulates direct sound, causes cancellation dips);
**RMS = incoherent/energy** (ignores phase, matches what you'd measure/hear averaged over a region;
equivalent to the Moving-Mic-Measurement result). **No live-RTA analogue** — these average across
*space/positions*, not time.

---

## 5. Smoothing (frequency-domain — orthogonal to all time averaging)

Distinct axis: smoothing averages **across frequency within a single spectrum**, not across time or
measurements. Source: [Graph menu / smoothing help](https://www.roomeqwizard.com/help/help_en-GB/html/graph.html).

- **Fractional-octave (1/48 … 1/1):** Gaussian-kernel smoothing of the chosen fractional-octave
  bandwidth. Implementation: *"multiple forward and backward passes of first order IIR filters to
  implement a Gaussian smoothing kernel of the chosen fractional octave bandwidth"* (Alvarez-Mazorra
  IIR approximation for log-spaced data).
- **Var (variable) smoothing:** *"1/48 octave below 100 Hz, 1/3 octave above 10 kHz and varies between
  1/48 and 1/3 octave from 100 Hz to 10 kHz, reaching 1/6 octave at 1 kHz."* Recommended for responses
  to be EQ'd (fine detail in the bass, broad up top).
- **Psychoacoustic smoothing:** *"1/3 octave below 100 Hz, 1/6 octave above 1 kHz and varies from 1/3 to
  1/6 octave between 100 Hz and 1 kHz. It also applies more weighting to peaks by using a cubic mean
  (cube root of the average of the cubed values)"* — closer to perceived response.
- **ERB smoothing:** variable bandwidth matching the ear's Equivalent Rectangular Bandwidth
  (`107.77·f + 24.673` Hz, f in kHz) — ~1 octave at 50 Hz down to ~1/6 octave up high; heaviest at LF.

For FreqTrace this is the **most directly borrowable** idea and it's a different feature from time
averaging: it doesn't slow the display, it just averages neighbouring bins. (FreqTrace's RTA
octave-banding is already a crude cousin — collapsing bins into fractional-octave bands.)

---

## 6. Bottom-line table — mode → DSP operation, and live relevance

| REW mode | Domain | Forgetting vs cumulative | Axis (time / freq / space) | Live-RTA analogue? |
|---|---|---|---|---|
| RTA Live/None | — | — | time (none) | Yes — Fast/no-smoothing |
| RTA Numeric N averages | power/RMS magnitude | **forgetting** (sliding N-block boxcar) | time | **Yes** — a boxcar time-average FreqTrace lacks |
| RTA Exponential | power/RMS magnitude | forgetting (EMA, user picks α) | time | **Yes — direct match** to Fast/Slow EMA (α-set vs τ-set) |
| RTA Forever | power/RMS magnitude | **cumulative** (equal weight) | time | Partial — useful for a "capture average since reset" but not a live tracking mode |
| RTA Coherent avg | complex (phase-aligned) | forgetting/cumulative | time | No (needs coherent reference; distortion use) |
| RTA Peak/Max hold | max, not an average | held + decay | time | Yes — FreqTrace already has this |
| Sweep pre-averaging (Repetitions) | coherent time-domain | cumulative over N sweeps | time (same stimulus) | No — needs repeatable stimulus |
| Vector average (All SPL) | complex | cumulative over measurements | space/measurements | No |
| RMS average (All SPL) | power/energy | cumulative over measurements | space/measurements | No |
| RMS+phase / dB+phase | hybrid mag+vector phase | cumulative over measurements | space/measurements | No |
| dB (magnitude) average | log-magnitude | cumulative over measurements | space/measurements | No |
| Smoothing (1/N, Var, Psy, ERB) | magnitude, across frequency | n/a | **frequency** | **Yes — orthogonal, directly borrowable** |

### Takeaways for FreqTrace
1. **Numeric N-block boxcar** and **Forever/accumulate-since-reset** are the two RTA *time* averages
   FreqTrace doesn't yet have — both cheap on top of the existing power-spectrum path, and both are
   genuine live analogues (boxcar = fixed-latency stable average; Forever = "hold and integrate this
   scene"). REW's Exponential is essentially what FreqTrace's Fast/Slow already is.
2. **Fractional-octave / Var / psychoacoustic / ERB smoothing** is a *separate* axis (frequency, not
   time) and is the highest-value addition — it improves RTA legibility without adding time lag, and
   REW's Var/psychoacoustic curves are proven, well-documented recipes to copy.
3. Everything under §3–§4 (sweep pre-averaging, Vector/RMS/phase/spatial averages) presumes *stored,
   repeatable or multi-position measurements* and has **no place in a live scrolling analyzer** — do
   not port them.

---

### Sources
- REW RTA / Spectrum help: https://www.roomeqwizard.com/help/help_en-GB/html/spectrum.html
- REW All SPL Graph help (Vector/RMS/phase/magnitude averaging, Align SPL, Cross corr align): https://www.roomeqwizard.com/help/help_en-GB/html/graph_allspl.html
- REW Making Measurements help (Repetitions / synchronous pre-averaging): https://www.roomeqwizard.com/help/help_en-GB/html/makingmeasurements.html
- REW Graph menu / smoothing help (fractional-octave, Var, psychoacoustic, ERB, IIR Gaussian implementation): https://www.roomeqwizard.com/help/help_en-GB/html/graph.html
- John Mulcahy / community clarification, RMS vs vector average: https://www.avnirvana.com/threads/difference-between-rms-average-and-vector-average.12957/
