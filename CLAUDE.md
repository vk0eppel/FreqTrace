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

### Most valuable feature — Tracked Frequency + Anomaly Candidate detection

See [CONTEXT.md](./CONTEXT.md) for precise definitions. Summary:

- **Tracked Frequency**: always-on readout of the highest-energy frequency per the global Weighting (A/C/Z, default A). Big, legible numeric display (e.g. "2.34 kHz"). Not conditioned on anything being wrong.
- **Anomaly Candidate detector**: flags frequencies as narrowband + harmonically-unrelated + sustained (flat-or-growing) over a rolling frame window (see ADR 0001). Unifies feedback and room resonance under one concept for v1 — no cause classification yet.
- Snap-to-nearest-ISO-band display: **deferred**, not decided yet.

### Secondary but high-value

- **RTA**: separate view, toggled against the waterfall (not simultaneous overlay) — resolution TBD.
- **Peak** and **Freeze** are separate, independent controls (see CONTEXT.md) — not to be conflated. Peak is scoped to RTA bars + numeric readouts only, never the waterfall.
- **SPL meter**: `raw dBFS + SPL Offset` (manual numeric field, default 0, v1 has no real calibration). Uses the global Weighting. See ADR 0003.
- **Signal Generator**: sine tone, pink noise, white noise for v1 (no sweeps). Has its own Output Device selector (Core Audio output enumeration, same shape as Input Device) — no longer limited to the default OS device.
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
  1. Waterfall/RTA (toggled, see product notes) — dominant, takes remaining space. Color map differs per Appearance Mode (see below). The RTA/waterfall toggle itself lives in the top-right corner of this zone, not in the Controls row.
  2. Measured Data row — Tracked Frequency, Anomaly Candidate (top 2-3, ranked by severity — not a single slot), SPL. Large/legible, read-only.
  3. Controls row — grouped into zones, not a flat list: **Input Device** (its own zone) · **Analysis settings** (Weighting, Time Averaging) · **View controls** (Peak, Freeze, Stop) · **Appearance Mode** · **Signal Generator** (own zone, far right: waveform type [sine/pink/white], on/off, level, Output Device picker).
- **Appearance Mode**: manual toggle, Dark (default) or high-contrast Light, not tied to system appearance (ADR 0005). Dark for dim/indoor venues, Light for bright outdoor/direct sunlight. Two distinct color maps, one designed per mode (exact palette TBD at implementation/visual-design time).
- **Freeze vs. Stop**: two distinct controls, not one. Freeze pauses the display only (pipeline keeps running; instant catch-up on unfreeze) — for quick glances mid-show. Stop halts the AVAudioEngine capture pipeline itself — for actually being done measuring (breaks, between soundcheck and doors). See CONTEXT.md.
- **Input Device**: picker in the Controls row. Defaults to system default on first launch, remembers last explicit choice after. On disconnect: pipeline enters Stopped state with an explicit disconnected indicator, no silent auto-fallback (ADR 0006).
- **Deferred**: overlaying Anomaly Candidate markers directly on the waterfall graph itself (in addition to the Measured Data row) — depends on how the Metal rendering pipeline is structured; revisit later.
