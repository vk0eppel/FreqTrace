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

### Most valuable feature — Tracked Frequency + Anomaly Candidate detection

See [CONTEXT.md](./CONTEXT.md) for precise definitions. Summary:

- **Tracked Frequency**: always-on readout of the highest-energy frequency per the global Weighting (A/C/Z, default A). Big, legible numeric display (e.g. "2.34 kHz"). Not conditioned on anything being wrong.
- **Anomaly Candidate detector**: flags frequencies as narrowband + harmonically-unrelated + sustained (flat-or-growing) over a rolling frame window (see ADR 0001). Unifies feedback and room resonance under one concept for v1 — no cause classification yet.
- Snap-to-nearest-ISO-band display: **deferred**, not decided yet.

### Secondary but high-value

- **RTA**: separate view, toggled against the waterfall (not simultaneous overlay) — resolution TBD.
- **Peak** and **Freeze** are separate, independent controls (see CONTEXT.md) — not to be conflated. Peak is scoped to RTA bars + numeric readouts only, never the waterfall.
- **SPL meter**: `raw dBFS + SPL Offset` (manual numeric field, default 0, v1 has no real calibration). Uses the global Weighting. See ADR 0003.
- **Signal Generator**: sine tone, pink noise, white noise for v1 (no sweeps). Has its own Output Device selector (Core Audio output enumeration, same shape as Input Device) — no longer limited to the default OS device. Sine frequency control: ISO Band stepping (primary) + free numeric Hz entry (fallback); control disables/hides for pink/white noise since they have no frequency. Level is a numeric dB value box (e.g. "-66dB"), not a slider — direct/precise entry, matching how techs read levels on a console rather than eyeballing a fader position. Has an explicit On/Off switch (not just a passive status indicator) — this is a real, deliberate control, since accidentally leaving a test tone playing during a show is a real live-sound mistake. See CONTEXT.md.
- **Time Averaging**: post-FFT, per-view Fast/Slow preset (not global, not a continuous time-constant for now) — smooths a view's response across consecutive frames, independent of FFT size/frequency resolution. The Anomaly Candidate detector is hardcoded to Fast (not user-selectable); other views may expose the Fast/Slow choice. See CONTEXT.md.

### Deferred (explicitly punted, not forgotten)

- Snap-to-nearest-ISO-band display.
- Octave Smoothing (frequency-domain bin averaging, e.g. 1/3-oct) for RTA/spectrum readability — revisit once RTA is actually being built.
- RTA resolution/band count.

### Explicitly out of scope for v1

- Transfer function / dual-channel measurement (reference signal, coherence, phase) — Smaart's core differentiator, big scope jump. Not in v1 unless later requested.
- Polyphonic pitch tracking — single Tracked Frequency is what matters for feedback hunting.
- Precise SPL calibration — the SPL Offset field exists for this but stays at 0/manual in v1; real per-device calibration is future work.
- Anomaly Candidate cause classification (feedback vs. room resonance) — unified for v1, may split later (ADR 0001).

## Architecture

- **Pipeline**: Capture → FFT → Tracking → Rendering, one shared pipeline feeding all analysis views (ADR 0002). Capture stage (AVAudioEngine tap) does minimal work on the real-time audio thread, copying into a lock-free ring buffer. FFT + tracking run on a background actor. Results are published via `AsyncStream` to a `@MainActor` `@Observable` view model (see conversation/ADR context — formalize as ADR if not already captured).
- **FFT parameters**: 4096-sample window, 50% overlap (2048 hop), target 48kHz — configurable, not hardcoded (sample rate/window/hop should be settable later).
- **Rendering**: waterfall uses Metal (ADR 0004).
- Signal Generator is on the output/playback side, independent of the capture pipeline.
- Module layout per feature not yet decided.

## Frontend

- **App shape**: regular Mac window app, not a menu bar utility — the waterfall needs real screen space to be readable from a distance.
- **Everything on one screen**: no tabs, no hidden panels, no settings sheets. All controls and readouts are always visible.
- **Three vertical zones**, stacked top to bottom:
  1. Waterfall/RTA (toggled, see product notes) — dominant, takes remaining space. Color map differs per Appearance Mode (see Waterfall Color Maps below). The RTA/waterfall toggle itself lives in the top-right corner of this zone, not in the Controls row.
  2. Measured Data row — Tracked Frequency, Anomaly Candidate (top 2-3, ranked by severity — not a single slot; no trend text; shows nothing when there are zero candidates), SPL. Large/legible, read-only.
     - **Severity is weighted, not just colored**: rank must register at a glance, mid-show, from a distance — so each row's severity shows through a compound signal (stripe glow/height, frequency-number size, text-color intensity), not a single small color dot. Highest severity is visually loud (glow + largest size); lower ranks recede. The highest-severity row gets a slow pulsing glow (respects `prefers-reduced-motion`).
  3. Controls row — two fixed lines, not a wrapping flat list:
     - **Line 1**: Analysis settings (Weighting, Time Averaging) · View controls (Peak, Freeze, Stop) · Signal Generator (waveform type [sine/pink/white], on/off, level) on the right — Output Device excluded.
     - **Line 2**: Input Device (left) · Appearance Mode (center) · Output Device (right).
- **Appearance Mode**: manual toggle, Dark (default) or high-contrast Light, not tied to system appearance (ADR 0005). Dark for dim/indoor venues, Light for bright outdoor/direct sunlight.

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

  Full token set (borders, surface-raised, annotation colors — review-only, not product UI) lives in the wireframe artifact's `:root`/`:root[data-theme="light"]` blocks.
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
