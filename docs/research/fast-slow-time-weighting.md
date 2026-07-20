# Fast / Slow Time Weighting — What the Standards Actually Say

Research note for implementing Time Averaging (ticket #7, `TimeAveragingBlender`). Question: are the
canonical "Fast = 125 ms" / "Slow = 1 s" figures **exponential time constants (τ)** or **settling
times**, and is a per-frame EMA with `w = 1 − exp(−Δt/τ)`, `τ = 125 ms / 1 s` standards-correct?

**Bottom line:** 125 ms and 1 s are **exponential time constants (τ)**, not settling times. An EMA on
the **power spectrum** with `w = 1 − exp(−Δt/τ)` and `τ = 0.125 s` (Fast) / `τ = 1 s` (Slow) is
**standards-correct as written** — do **not** rescale to `τ = target/3`. The apparent 3τ/5τ "settling"
figures are consequences of τ, not a redefinition of it.

---

## 1. Are 125 ms / 1 s exponential time constants or settling times?

**Time constants (τ) of a first-order exponential average.** IEC 61672-1 (the current sound-level-meter
standard) defines time weighting as *"an exponential time-averaging of the squared sound pressure"* and
specifies *"Fast (F), with a time constant of 125 ms, and Slow (S), with a time constant of 1 s."* [1]

The weighting is a running exponential integral of the squared pressure with time constant τ:

```
                1   ⌠ t
  p²_weighted = ─── │   p²(ξ) · e^(−(t−ξ)/τ) dξ          τ_F = 0.125 s,  τ_S = 1 s
                τ   ⌡ −∞
```

i.e. the standard RC / first-order low-pass form where a step reaches 1 − e⁻¹ ≈ **63%** in one τ. [1][2]
Instrument makers state it the same way: Larson Davis — Slow *"time constant is 1 second (1000 ms)"*,
Fast *"time constant is 1/8 second (125 ms)"* [3]; NTi Audio — *"the time constants for the 'F'
(t = 125 ms) and the 'S' weighting (t = 1 s), which are defined in the standard."* [2]

The 125 ms / 1 s are **not** settling times. See §2 for why settling takes several τ.

## 2. Step response, decay, and visual settling

For a first-order exponential, a step input rises as `1 − e^(−t/τ)`:

| Fraction of step | time (general) | Fast (τ=0.125 s) | Slow (τ=1 s) |
|---|---|---|---|
| 63% (1 − e⁻¹) | 1τ | 0.125 s | 1 s |
| ~95% (1 − e⁻³) | 3τ | 0.375 s | 3 s |
| ~99% (1 − e⁻⁵) | 5τ | 0.625 s | 5 s |

NTi Audio gives exactly this in practice: after a sudden level increase, *"the 'F' weighted level display
would take approximately 0.6 seconds to reach the new level, while the 'S' weighted level display would
reach the new level only after approx. 5 seconds"* [2] — i.e. their "reach the new level" ≈ **5τ (~99%)**.
This confirms 125 ms / 1 s are τ, not the settle time: if 1 s were the settle time, Slow wouldn't take ~5 s.

**Decay** (source switched off) is exponential in the power domain, giving a *constant dB/s* slope. NTi:
*"the displayed 'F' level decays at a rate of 34.7 dB/s, while the displayed 'S' level decays at a rate of
4.3 dB/s."* [2] These numbers are `10·log₁₀(e)/τ = 4.343/τ` dB/s (4.343/1 = 4.34 ≈ 4.3; 4.343/0.125 =
34.7) — see §3, this is itself proof the averaging is in the squared/power domain.

**Visual settling:** a Slow-weighted meter takes ~**3 s to ~95%** and ~**5 s to fully settle** after a
level change; Fast settles in ~**0.4–0.6 s**. So yes — **sluggish Slow / jumpy Fast is expected, standard
behavior**, and is the entire point of offering both: Slow for a stable readout of fluctuating material,
Fast for tracking rapid changes (closer to the ear's ~125 ms response) [1][2][3].

## 3. Domain: squared (power / mean-square), not dB

Applied to the **squared sound pressure (mean-square / power / energy domain), before dB conversion.**
IEC 61672-1: time weighting is *"an exponential time-averaging of the **squared** sound pressure"* [1];
the displayed level is then `10·log₁₀(p²_weighted / p₀²)`.

Independent confirmation from the decay rate: exponential decay of mean-square `p² ∝ e^(−t/τ)` gives
`dL/dt = 10·log₁₀(e)·(−1/τ) = −4.343/τ` dB/s. For τ=1 s that's **4.34 dB/s**, matching NTi's 4.3 dB/s [2].
Dewesoft/NTi note the subtlety explicitly: a naive τ=1 s would suggest ~8.7 dB/s, *"but for Sound Pressure
Levels (SPLs) it is only the half (4.34 dB/s) … because SPLs are based on averaged values in the … squared
energy domain and therefore exponential averaging is also applied on squared sound pressure values"* [4].
If averaging were done on amplitude (or on dB) the constant would be `20·log₁₀(e)/τ = 8.69/τ` — which is
**not** what real meters do. This nails the domain: **square first, average, then convert to dB.**

## 4. Impulse vs. Leq / linear integration

- **Impulse (I):** asymmetric exponential — fast 35 ms rise, very slow decay (~2.9 dB/s), for short
  impulses. Was in the now-**superseded** IEC 60651/651; **not part of current IEC 61672-1**, though some
  meters still offer it. [1][2] Not relevant to FreqTrace.
- **Leq / linear time-averaging:** a *linear* (equal-weight) integration of mean-square pressure over a
  fixed window — *"there is no time constant involved"* [5]. Every sample in the window counts equally;
  the result is the true energy average over that interval. Contrast with exponential weighting (F/S),
  which is a *running* average that weights recent input more and older input exponentially less [3][5].
  Leq answers "what was the average energy over this period"; F/S answer "what is the level *now*, smoothed."
  FreqTrace's Fast/Slow presets are the exponential kind, not Leq.

## 5. Recommendation for FreqTrace

`TimeAveragingBlender` is an EMA over the **power/magnitude-squared spectrum** with per-frame new-sample
weight `w`. To be standards-correct:

```
w = 1 − exp(−Δt / τ)      with   τ_Fast = 0.125 s,   τ_Slow = 1.0 s
```

where `Δt` is the hop interval (~43 ms at the default 2048-sample hop / 48 kHz).

- **Use τ = 125 ms and τ = 1 s directly.** They are the exponential time constants the standard defines
  [1][2][3]. **Do not** treat them as ~95% settling times and rescale to `τ = target/3` — that would make
  our Fast ≈ 42 ms and Slow ≈ 333 ms, i.e. **3× too fast / too twitchy** vs. a real IEC 61672-1 meter.
- **Average in the power (mean-square) domain, then convert to dB** — which the pipeline already does
  (blend happens on the magnitude spectrum before dB) [1][4]. Do not EMA the dB values.
- Expect and accept the behavior: Slow takes ~3 s to ~95% / ~5 s to settle, Fast ~0.4–0.6 s [2]. That
  sluggishness is correct, not a bug.
- Sanity check: at τ=1 s the decay slope should read ~4.3 dB/s, at τ=0.125 s ~34.7 dB/s [2][4].

**Caveat on our current constants:** CLAUDE.md records `TimeAveragingBlender` as Fast = 1.0 (no smoothing)
and Slow = 0.15 fixed per-frame weight (a documented judgment call, not derived). `w = 0.15` at Δt≈43 ms
implies `τ = −Δt/ln(1−w) ≈ 43 ms / 0.163 ≈ 265 ms` — **~4× faster than the IEC Slow (1 s)**, and it drifts
with hop size since it's a fixed weight, not derived from Δt/τ. If we want Slow to match the standard,
switch to `w = 1 − exp(−Δt/τ)` with τ = 1 s (and Fast τ = 125 ms rather than w=1/no smoothing). This is a
behavior change worth proposing to the user, not shipping silently.

---

## Sources

1. Wikipedia, *Sound level meter* — IEC 61672-1 time-weighting definition ("exponential time-averaging of
   the squared sound pressure"; F=125 ms, S=1 s; Impulse in superseded IEC 60651; Leq has no time constant).
   https://en.wikipedia.org/wiki/Sound_level_meter
2. NTi Audio, *Fast, Slow, Impulse Time Weighting — What do they mean?* (instrument maker, first-party) —
   τ_F=125 ms / τ_S=1 s "defined in the standard"; ~0.6 s / ~5 s to reach new level; decay 34.7 / 4.3 dB/s;
   Impulse 35 ms rise / 2.9 dB/s decay.
   https://www.nti-audio.com/en/support/know-how/fast-slow-impulse-time-weighting-what-do-they-mean
3. Larson Davis (PCB/HBK), *Sound Measurement Terminology* — Fast = 1/8 s (125 ms), Slow = 1 s time
   constants; exponential vs. linear integration.
   https://www.larsondavis.com/learn/sound-vibe-basics/sound-measurement-terminology
4. Dewesoft, *Exponential Averaging — Fast (F), Slow (S), Impulse (I)* — decay 4.34 dB/s at τ=1 s and the
   squared-domain explanation (why it's half the naive 8.7 dB/s).
   https://support.dewesoft.com/en/support/solutions/articles/14000139949-exponential-averaging-fast-f-slow-s-impulse-i-
5. Wikipedia, *Sound level meter* (Leq / LAeq) — Leq is RMS over a stated interval, "no time constant
   involved"; linear vs. exponential weighting.
   https://en.wikipedia.org/wiki/Sound_level_meter
