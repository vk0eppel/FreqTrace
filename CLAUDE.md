# FreqTrace

Real-time audio analysis app for live sound environments (spectrograph, frequency tracker, SPL meter, signal generator).

Primary platform is **macOS**; iOS support may come later. The Xcode project is multiplatform (SUPPORTED_PLATFORMS includes macosx/iphoneos/xros) — default to macOS when testing/building unless told otherwise.

## Stack

- SwiftUI + AppKit (for macOS-specific UI/integration as needed), Xcode 16+
- **AVAudioEngine** — audio I/O and signal routing (capture for spectrograph/tracker/SPL, playback for signal generator)
- **Core Audio** — lower-level device/hardware access where AVAudioEngine isn't sufficient
- **Accelerate (vDSP)** — FFT and DSP math for the spectrograph and frequency tracker
- Targets: `FreqTrace` (app), `FreqTraceTests` (unit), `FreqTraceUITests` (UI)
- Scheme: `FreqTrace`

## Build & test

```
xcodebuild -project FreqTrace.xcodeproj -scheme FreqTrace -destination 'platform=macOS' build
xcodebuild -project FreqTrace.xcodeproj -scheme FreqTrace -destination 'platform=macOS' test
```

## Product

Target user: live sound techs at FOH during soundcheck/show — not measurement engineers (that's Smaart's audience). Differentiator is "opens up and just works," not analysis depth. Usable one-handed, mid-show, readable from a distance in dim lighting (dark bg, saturated color map like viridis/magma, large numerics).

### Primary view — spectrogram/waterfall

- Scrolling waterfall, log-frequency axis (20 Hz–20 kHz), color-mapped magnitude. Rendered with **Metal** (see ADR 0004).
- Axis labeled at meaningful bands (100, 200, 500, 1k, 2k, 5k, 10k), not raw FFT bins.
- Default scroll history: ~10–20s, long enough to catch a feedback ring building.
- Scroll direction: new data enters at the **bottom**, scrolls **up** — "now" is the bottom edge, history ages upward off the top.
- **Time axis**: explicit labeled gridlines (e.g. every 5s: -5s, -10s, -15s...), same visual treatment as the frequency axis labels — a tech needs a real time reference to judge how long something's been sustaining, not just eyeballed scroll position.
- **Implementation** (ticket #8): magnitude normalization (power → dB → clamped [0,1]) happens once per frame on the CPU (`MagnitudeScaling`, ~2000 values) before writing into the GPU texture (R32Float, one row per hop, already-normalized) — cheap because it's O(columns), not O(pixels). The log-frequency remap and the color-ramp lookup happen per-*pixel* in the fragment shader (`Waterfall.metal`) instead, since only those two actually need to scale with screen resolution (resampling ~2000 columns to arbitrary screen width, potentially many-to-one at high frequencies where the log axis compresses) — doing that resample on the CPU every frame would be far more expensive than letting the GPU do it once per pixel. Scrolling uses a repeat-addressing sampler on the texture's time axis rather than CPU-side row copying. **Bug fix (post-#8)**: the "skewing toward the loud end" follow-up above turned out to be a real bug, not just an uncalibrated floor/ceiling — `MagnitudeScaling`'s -80dB/0dB range assumes power already on a [0,1]/dBFS scale, but raw vDSP FFT power is nowhere near that (a full-scale tone's raw power is ~10^6-10^7 for a 4096-point window), so almost everything clamped to the ceiling regardless of actual loudness (reported by a user as every RTA bar pegged to max / the waterfall uniformly "too loud"). Fixed by applying the same self-calibration technique already used for SPL (ticket #6): `FrequencyTracker.fullScalePower` (a synthetic full-scale reference tone's power, computed once at init) now travels through `AnalysisResult` to both `WaterfallRenderer.writeRow` and `RTABinning.bars`, which divide raw magnitudes by it before applying `MagnitudeScaling`'s floor/ceiling. `-80dB/0dB` itself was fine as a range once the input is actually referenced to 0dBFS — the bug was the missing reference, not the range.

### Most valuable feature — Tracked Frequency + Anomaly Candidate detection

See [CONTEXT.md](./CONTEXT.md) for precise definitions. Summary:

- **Tracked Frequency**: always-on readout of the highest-energy frequency per the global Weighting (A/C/Z, default A). Big, legible numeric display (e.g. "2.34 kHz"). Not conditioned on anything being wrong.
- **Anomaly Candidate detector** (ticket #5): flags frequencies as narrowband + harmonically-unrelated + sustained (flat-or-growing) over a rolling frame window (see ADR 0001). Unifies feedback and room resonance under one concept for v1 — no cause classification yet. Implementation, none of it spec'd so each threshold is a documented judgment call (`AnomalyDetector.swift`): `PeakFinder` finds narrowband bumps via spectral prominence (≥6dB above the louder of two "shoulder" bins 6 bins away); `HarmonicRelation` excludes peaks within 3% of an integer multiple (2nd-8th harmonic) of another peak in the same frame, either direction, so a musical note's harmonic series is never flagged; a per-bin sustain tracker promotes a peak to a candidate only after 8 consecutive flat-or-growing hops (~350ms), tolerating up to 3 missed frames before dropping the track entirely. Runs on the raw, unweighted spectrum — hardcoded to Fast Time Averaging (no pre-smoothing at all; the sustain window itself governs responsiveness). Reports the top 3 by severity (current level in dB).
- Snap-to-nearest-ISO-band display: **deferred**, not decided yet.

### Secondary but high-value

- **RTA** (ticket #11): separate view, toggled against the waterfall (not simultaneous overlay) — a live single-frame bar rendering, not a scrolling history like the waterfall. Bars are log-frequency-spaced via the same `FrequencyAxis` mapping the waterfall uses, so the two views read consistently; each bar takes the loudest bin in its range (`RTABinning`), normalized via the shared `MagnitudeScaling`. Bar count (48) is a judgment call — CLAUDE.md previously flagged resolution as TBD; 48 was picked as coarse enough to read at a glance yet fine enough to resolve the labeled bands, not derived from a spec. Bars render as a single accent color (not the waterfall's magnitude color ramp) — standard RTA convention, and a live single frame doesn't need history-encoding color. The toggle is a small pill control in the top-right corner of the graph zone (`WaterfallZoneView`), switching `displayMode` without touching capture start/stop, so both views' underlying data keeps flowing regardless of which is shown.
- **Peak** (ticket #12) and **Freeze** are separate, independent controls (see CONTEXT.md) — not to be conflated. Peak is scoped to RTA bars + numeric readouts only, never the waterfall. Implemented as one generic `PeakHoldTracker<Key>` (indefinite running max per key) shared by RTA bars (keyed by bar index), SPL, and a new `trackedFrequencyLevelDb` reading — the level of the currently-tracked bin (`FrequencyTracker.trackedFrequencyLevelDb`), distinct from both the Hz value and from SPL's whole-spectrum sum. One "PEAK RESET" button in the Controls row clears all three together, since the AC calls for one reset action, not per-readout resets.
- **SPL meter** (ticket #6): `raw dBFS + SPL Offset` (manual numeric field, default 0, range -60...60dB, v1 has no real calibration). Uses the global Weighting — summed across the weighted magnitude spectrum (not a single peak, unlike Tracked Frequency), self-calibrated against a synthetic full-scale reference tone computed once at `FrequencyTracker` init so a full-scale signal reads ~0dB regardless of the FFT/window's own scaling convention, rather than a hand-derived/hardcoded constant. See ADR 0003 and `FrequencyTracker.weightedLevelDb`.
- **Signal Generator**: sine tone, pink noise, white noise for v1 (no sweeps). Has its own Output Device selector (Core Audio output enumeration, same shape as Input Device) — no longer limited to the default OS device. Sine frequency control: ISO Band stepping (primary) + free numeric Hz entry (fallback); control disables/hides for pink/white noise since they have no frequency. Level is a numeric dB value box (e.g. "-66dB"), not a slider — direct/precise entry, matching how techs read levels on a console rather than eyeballing a fader position. Has an explicit On/Off switch (not just a passive status indicator) — this is a real, deliberate control, since accidentally leaving a test tone playing during a show is a real live-sound mistake. See CONTEXT.md.
- **Time Averaging** (ticket #7, Tracked Frequency only so far): post-FFT, per-view Fast/Slow preset (not global, not a continuous time-constant for now) — smooths a view's response across consecutive frames, independent of FFT size/frequency resolution. Implemented as `TimeAveragingBlender`, an exponential moving average over the magnitude spectrum with a per-preset new-frame weight (Fast=1.0/no smoothing, Slow=0.15 — a judgment call, not spec'd), applied only to the spectrum Tracked Frequency's argmax reads; `AnalysisResult.magnitudes` (waterfall/RTA) and SPL stay unblended. The Anomaly Candidate detector is hardcoded to Fast (not user-selectable); other views may expose the Fast/Slow choice later. See CONTEXT.md.

### Deferred (explicitly punted, not forgotten)

- Snap-to-nearest-ISO-band display.
- Octave Smoothing (frequency-domain bin averaging, e.g. 1/3-oct) for RTA/spectrum readability — RTA is now built (ticket #11) without it; revisit if the raw per-bin bars prove too noisy in practice.

### Explicitly out of scope for v1

- Transfer function / dual-channel measurement (reference signal, coherence, phase) — Smaart's core differentiator, big scope jump. Not in v1 unless later requested.
- Polyphonic pitch tracking — single Tracked Frequency is what matters for feedback hunting.
- Precise SPL calibration — the SPL Offset field exists for this but stays at 0/manual in v1; real per-device calibration is future work.
- Anomaly Candidate cause classification (feedback vs. room resonance) — unified for v1, may split later (ADR 0001).

## Architecture

- **Pipeline**: Capture → FFT → Tracking → Rendering, one shared pipeline feeding all analysis views (ADR 0002). Capture stage (AVAudioEngine tap) does minimal work on the real-time audio thread, copying into a lock-free ring buffer (`AudioRingBuffer`, single-writer-per-atomic SPSC discipline — see its header comment for a real race that was found and fixed by code review). FFT + tracking run on a background actor (`AudioAnalysisPipeline`). Results are published via `AsyncStream` to a `@MainActor` `@Observable` view model (`TrackedFrequencyViewModel`) — implemented in ticket #3, not yet split into its own ADR.
- **FFT parameters**: 4096-sample window, 50% overlap (2048 hop), target 48kHz — configurable via `AnalysisConfig`, not hardcoded. **Known gap**: `MicrophoneCaptureEngine` reports the actual hardware input sample rate (often 44.1kHz, not 48kHz), but the pipeline doesn't yet reconfigure `AnalysisConfig` to match if it differs from the default — frequency readings could be slightly off on hardware that doesn't run at 48kHz. Worth a follow-up ticket.
- **Weighting**: applied in the power domain (dB/10, not dB/20) since `vDSP_zvmags` returns squared magnitude — a detail worth knowing if the weighting math is ever touched.
- **Rendering**: waterfall uses Metal (ADR 0004).
- **Signal Generator**: fully separate `AVAudioEngine` instance from the capture pipeline (confirms the independence ADR 0002 assumed). Level range is `-96...0` dB, default `-66` dB (not specified anywhere before implementation; recorded here now). Pink noise uses Voss-McCartney (16 rows + white component). Sine frequency stepping (ticket #14) is `ISOBand` (`FreqTrace/SignalGenerator/ISOBand.swift`), a pure type stepping the standard ISO 266 R10 1/3-octave centers (25 Hz–20 kHz, matching graphic EQ fader spacing) up/down/clamped; `SignalGeneratorEngine.sineFrequencyHz` drives it into `SignalGeneratorCore`/`SignalGeneratorRenderState`, preserving oscillator phase across a frequency change so it doesn't click. Output Device (ticket #14) reuses the Input Device machinery rather than duplicating it: `AudioDeviceSelector` (renamed from `InputDeviceSelector` — the resolution logic was never input-specific) and `DeviceConnectionState` (renamed from `CaptureConnectionState`, since applying a "capture" name to the Signal Generator's playback connection read as actively confusing) are both shared, unit-tested once in `FreqTraceTests/InputDeviceTests.swift`. `AudioDeviceEnumerator` gained a `Scope` (`.input`/`.output`) parameter — restoring the generalization an earlier ticket's code review had deliberately cut back to input-only, now that Output Device actually needs it — so the Core Audio property-address boilerplate isn't duplicated into a second type. `DBValueField` was generalized into `NumericValueField` (pluggable `format` closure) so the Hz field reuses the same numeric-entry component as the dB fields (Level, SPL Offset) instead of a near-duplicate.
- Module layout per feature not yet decided.

## Frontend

- **App shape**: regular Mac window app, not a menu bar utility — the waterfall needs real screen space to be readable from a distance.
- **Everything on one screen**: no tabs, no hidden panels, no settings sheets. All controls and readouts are always visible.
- **Three vertical zones**, stacked top to bottom:
  1. Waterfall/RTA (toggled, see product notes) — dominant, takes remaining space. Color map differs per Appearance Mode (see Waterfall Color Maps below). The RTA/waterfall toggle itself lives in the top-right corner of this zone, not in the Controls row.
  2. Measured Data row — Tracked Frequency, Anomaly Candidate (top 2-3, ranked by severity — not a single slot; no trend text; shows nothing when there are zero candidates), SPL. Large/legible, mostly read-only — the one exception is the SPL Offset field (ticket #6), which lives directly under the SPL reading it offsets rather than in the Controls row, since it's scoped to that one readout.
     - **Severity is weighted, not just colored**: rank must register at a glance, mid-show, from a distance — so each row's severity shows through a compound signal (stripe glow/height, frequency-number size, text-color intensity), not a single small color dot. Highest severity is visually loud (glow + largest size); lower ranks recede. The highest-severity row gets a slow pulsing glow (respects `prefers-reduced-motion`).
  3. Controls row — two fixed lines, not a wrapping flat list:
     - **Line 1**: Analysis settings (Weighting, Time Averaging) · View controls (Peak, Freeze, Stop) · Signal Generator (waveform type [sine/pink/white], on/off, level) on the right — Output Device excluded.
     - **Line 2**: Input Device (left) · Appearance Mode (center) · Output Device (right).
- **Appearance Mode** (ticket #10): manual toggle, Dark (default) or high-contrast Light, not tied to system appearance (ADR 0005). Dark for dim/indoor venues, Light for bright outdoor/direct sunlight. `AppearanceSettings` (a small `@Observable`, separate from `AudioPipelineViewModel` since this is UI chrome state, not audio state) holds the current mode; `AppShellView` is the single place that turns it into the injected `Theme` every view reads. The waterfall's Metal color map switches too — `WaterfallColorMap.light`'s stops are duplicated into `Waterfall.metal` (MSL can't call back into Swift) and selected via an `isLightMode` uniform, threaded down through `MetalWaterfallView`/`WaterfallRenderer` the same cross-thread-safe way `pendingMagnitudes` already was.

- **Waterfall Color Maps** — deliberately multi-hue (magma/viridis-family), not the generic single-hue sequential ramp: a spectrogram's ~60-90dB dynamic range needs more perceptual steps than one hue can carry, and multi-hue perceptually-monotonic ramps (magma, viridis, inferno) are the established convention for this exact domain (every real spectrogram tool uses one). Computed via OKLCH (script-derived, not eyeballed — same math as the `dataviz` skill's validator) to confirm monotonic lightness and no adjacent-step collapse:

  **Dark mode** (silence → loudest, lightness increases, on `#0b0d10` surface):
  `#0b0d10` → `#2b1150` → `#7c1c62` → `#c33b3a` → `#e8752b` → `#ffd166`
  (near-black blends into the panel at silence; smallest adjacent ΔL = 0.101, well clear of the 0.06 floor)

  **Light mode** (silence → loudest, lightness *decreases* — inverted from Dark since the surface is light, and the loudest content needs to be the darkest/most saturated to stay legible in direct sunlight; on `#f4f5f6` surface):
  `#f4f5f6` → `#bcd6f2` → `#6f9fe0` → `#39599e` → `#5a2e6b` → `#2a0e33`
  (near-white blends into the panel at silence; loudest stop is near-black violet, 15.9:1 contrast vs. surface; smallest adjacent ΔL = 0.089)

  Both ramps are 6 stops (silence + 5 magnitude steps); actual rendering interpolates between them. Re-verify (`check_ramp.mjs`-style OKLCH computation, not eyeballing) if stops are added/changed.

- **UI Chrome tokens** — checked with WCAG contrast math (not eyeballed). Light mode is a deliberately *higher*-contrast design than Dark, not an inversion — an earlier naive-inverted draft actually measured **worse** than Dark on `accent` (3.0:1), `warn` (3.89:1), and `textFaint` (2.64:1), all below the 4.5:1 body-text floor, which defeats the point of a mode built for direct sunlight. Corrected:

  | Token | Dark | Light |
  |---|---|---|
  | bg | `#0b0d10` | `#f4f5f6` |
  | surface | `#14171b` | `#ffffff` |
  | text | `#e8ecef` | `#14171b` |
  | text-dim | `#8b939c` | `#565d66` |
  | text-faint | `#7a8189` (was `#565d66`, 2.7:1 — fixed to 4.56:1) | `#5c6167` (was `#9aa0a7`, 2.64:1 — fixed to 6.25:1) |
  | accent | `#ffb84d` | `#8f4d00` (was `#c9770a`, 3.0:1 — fixed to 6.5:1) |
  | danger | `#ff5a5a` | `#c62f2f` |
  | warn | `#ffcf5c` | `#6e4e00` (was `#a8790a`, 3.89:1 — fixed to 7.63:1) |
  | border | `#262b31` | `#d7dbdf` |
  | border-soft | `#1e2227` | `#e3e6e9` |
  | surface-raised | `#1b1f24` | `#f7f8f9` |

  `border`/`border-soft`/`surface-raised` were originally scoped as review-only wireframe tokens, but building the real app shell (ticket #2) surfaced that product UI genuinely needs them (panel backgrounds, dividers between zones) — promoted to real product tokens rather than shipping a shell with no visual separation. Annotation colors (used only for design-review callouts in the wireframe) remain review-only and are not implemented in the app.
- **Freeze vs. Stop**: two distinct controls, not one. Freeze pauses the display only (pipeline keeps running; instant catch-up on unfreeze) — for quick glances mid-show. Stop halts the AVAudioEngine capture pipeline itself — for actually being done measuring (breaks, between soundcheck and doors). See CONTEXT.md.
- **Input Device**: picker in the Controls row. Defaults to system default on first launch, remembers last explicit choice after. On disconnect: pipeline enters Stopped state with an explicit disconnected indicator, no silent auto-fallback (ADR 0006).
- **Window**: freely resizable, with an enforced minimum size. No fixed/locked aspect ratio. No special fullscreen/presentation/multi-display handling for v1 — standard macOS window management (native fullscreen, drag to a second monitor) is sufficient.
  - **Minimum size is derived, not arbitrary**: it's whatever's needed for the widest Controls row line to render without wrapping/clipping, at the type scale above. Current estimate from the control set as designed: **~1120 × 570pt** (Controls row Line 1 — Weighting, Time Averaging, Peak/Freeze/Stop, Signal Gen cluster — is the binding constraint on width; graph zone min-height + Measured Data row + two Controls lines + title bar on height). Re-derive this if controls are added/removed, and verify against real SwiftUI layout metrics once built (this is a reasoned estimate from the wireframe, not a measured value).
- **Typography scale**: Tracked Frequency is the deliberate visual hero of the screen (largest element by far), not equal-weighted with SPL/Anomaly Candidates — matches its status as the flagship feature vs. SPL being "simple metering."

  | Role | Size | Weight |
  |---|---|---|
  | Tracked Frequency (hero number) | 64pt | Semibold |
  | SPL | 32pt | Semibold |
  | Anomaly Candidate rows (freq per row) | 20pt | Semibold |
  | Section captions (uppercase, tracked letter-spacing) | 11pt | Semibold |
  | Controls row (buttons, dropdowns, value boxes) | 12pt | Medium |
  | Waterfall axis labels | 10pt | Regular |
  | Data sub-captions (e.g. "Weighting: A") | 11pt | Regular, dimmed |

  Data/numeric roles use `ui-monospace`/SF Mono with tabular figures; UI chrome uses the system sans (San Francisco).
- **Deferred**: overlaying Anomaly Candidate markers directly on the waterfall graph itself (in addition to the Measured Data row) — depends on how the Metal rendering pipeline is structured; revisit later.

## Agent skills

- Issue tracker: [docs/agents/issue-tracker.md](./docs/agents/issue-tracker.md)
- Triage labels: [docs/agents/triage-labels.md](./docs/agents/triage-labels.md)
- Domain docs: [docs/agents/domain.md](./docs/agents/domain.md)
