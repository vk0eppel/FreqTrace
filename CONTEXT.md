# FreqTrace

Real-time audio analysis for live sound techs at FOH — spectrogram, frequency tracking, anomaly (feedback/resonance) detection.

## Language

**Tracked Frequency**:
The single frequency currently carrying the most energy, per the active Weighting. Drives the primary numeric readout. Always has a value during signal presence — it is not conditioned on anything being wrong.
_Avoid_: Dominant frequency, peak frequency

**Weighting**:
A single global setting (A/C/Z, user-selectable, defaults to A) applied wherever the app judges "loudest" or measures level — the Tracked Frequency, the SPL meter, and the waterfall/RTA spectrum display. One setting shared across features, not configured per-feature. Explicitly NOT applied to the Anomaly Candidate detector's own analysis (ADR 0001) — a genuine low-frequency resonance must not be hidden by A-weighting's roll-off just because it wouldn't read loud to a human ear.
_Avoid_: Weighting curve (fine as a description, but the app concept is the single shared setting)

**SPL Offset**:
A manually-entered number (default 0) added to the raw dBFS level to produce the SPL meter's displayed value. Placeholder for future device mic calibration data — v1 has no real calibration, so the meter is honestly relative/uncalibrated until this is populated with accurate data.
_Avoid_: Calibration (implies an accuracy v1 doesn't have yet)

**Anomaly Candidate**:
A frequency/band flagged by the anomaly detector as narrowband, harmonically unrelated to other energy present, and sustained (flat or growing, not decaying) over a rolling window of recent frames. Covers both feedback and room resonance without distinguishing which caused it — v1 does not attempt cause classification. Multiple Anomaly Candidates can be flagged at once (e.g. two separate rings building simultaneously); the Measured Data row shows the top 2-3, ranked by severity/confidence — not collapsed to a single slot. Each row shows frequency + severity only (a colored dot) — no trend/state text (e.g. "rising", "sustained") for v1; that was a wireframe flourish, not a real decision. This is tied to the unified-candidate scope in ADR 0001 — if detection later distinguishes types/causes (or otherwise produces a meaningful trend signal), revisit whether trend text belongs in the row. When there are zero Anomaly Candidates, the row shows nothing — no placeholder/empty-state message.
_Avoid_: Feedback candidate, ringing candidate, resonance candidate (each implies a specific cause; the detector doesn't know the cause in v1)

**Harmonic Relation**:
Two frequency components are harmonically related if one sits at an integer multiple of the other (e.g. ~2x, ~3x). An Anomaly Candidate must lack this relation to other concurrent energy — presence of a harmonic series marks a peak as musical content instead.

**Peak**:
A passive marker showing the highest level seen since the last manual reset, displayed while the live view keeps updating underneath/around it — classic level-meter behavior (indefinite hold, not a rolling/auto-expiring window). Applies only to the RTA bars and the numeric readouts (SPL, Tracked Frequency level) — never appears on the waterfall, since that's already a time-history display and a "held peak" adds nothing there. Distinct from Freeze — Peak never stops the live display, it just adds a marker on top of it.
_Avoid_: Peak Hold, Max-hold (implies the display itself is held, and "Hold" is already used by Freeze/Stop's pause semantics — reusing it here caused confusion); Peak Track (collides with Tracked Frequency, an unrelated concept)

**Freeze**:
An explicit, user-triggered pause of an entire view's updates, so the tech can walk away from the screen and study a static snapshot. The capture/FFT/tracking pipeline keeps running underneath — unfreezing shows the tech is instantly caught up to live. Distinct from Peak — Freeze stops everything on screen, not just a marker. Distinct from Stop — Freeze never touches the pipeline itself.
_Avoid_: Pause (ambiguous with Stop — always use the specific term)

**Stop**:
An explicit, user-triggered halt of the AVAudioEngine capture pipeline itself — audio capture stops, not just the display. Used when the tech is done measuring for a while (between soundcheck and doors, on a break), not for quick glances. Resuming requires re-initializing capture, so it's slower than un-Freezing. Distinct from Freeze. The app now launches already in this Stopped state — capture no longer auto-starts on open, so the button reads "Start" until the tech presses it (see ADR 0007).
_Avoid_: Pause (ambiguous with Freeze — always use the specific term)

**Input Device**:
The system audio input source the capture pipeline reads from. Defaults to the system default input on first launch; remembers the tech's last explicit choice thereafter. If the selected device disconnects mid-use, the pipeline enters Stopped state and the UI shows an explicit disconnected indicator — it never silently falls back to a different device, since that could show the tech data from a source they don't realize changed. See ADR 0006.

**ISO Band**:
One of the standard ISO 1/3-octave center frequencies (25, 31.5, 40, 50 Hz... matching graphic EQ fader spacing). Used by the Signal Generator's frequency control as the primary step increment (step buttons jump to the next/previous ISO Band) alongside free numeric Hz entry as a fallback for an exact custom value. Distinct from the still-deferred idea of snapping a *measured* reading (Tracked Frequency/Anomaly Candidate) to the nearest ISO Band for display — that's about rounding a measurement, this is about generating a tone at an exact standard frequency.

**Signal Generator Level**:
A numeric dB value box (e.g. "-66dB"), directly editable — not a slider. Techs read/set levels as numbers on a console, not by eyeballing a fader's visual position, so the control matches that mental model.

**Signal Generator On/Off**:
An explicit switch controlling whether the Signal Generator is actively emitting audio — deliberately a real toggle, not a passive status dot, since leaving a test tone running unnoticed is a real mistake in a live show. Distinct from Stop: this only affects the Signal Generator's own output, not the capture/analysis pipeline. The Signal Generator is fully independent of Freeze and Stop — it can keep running while the display is Frozen or the capture pipeline is Stopped, since it's on the output/playback side (see ADR 0002) and has no dependency on capture being active.

**Output Device**:
The system audio output the Signal Generator plays through. Same shape and same disconnect behavior as Input Device (own selector, no silent fallback — the generator stops and shows disconnected rather than risk playing a test tone out of an unintended output). See ADR 0006.

**Time Averaging**:
A post-FFT stage that blends level across consecutive frames (Fast/Slow presets) to control how quickly a view's displayed value responds, independent of FFT window size or frequency resolution. Meant to be selected per-view eventually; the single control implemented so far (ticket #7's Controls row toggle) currently drives Tracked Frequency, the waterfall, and the RTA together, not yet split per-view. The Anomaly Candidate detector is fixed to Fast regardless (never user-selectable, since catching a building ring requires fast response) and reads the raw, unblended spectrum directly.
_Avoid_: Smoothing (ambiguous with Octave Smoothing — always specify which)

**Octave Smoothing**:
A frequency-domain averaging across neighboring FFT bins at a single instant (e.g. 1/3, 1/6, 1/12-oct), reducing bin-to-bin jaggedness in a spectrum display. Distinct from Time Averaging — this smooths across frequency, not across time. Not yet decided whether/how this is exposed in v1.
_Avoid_: Smoothing (ambiguous with Time Averaging — always specify which)

**Measured Data row**:
The screen region directly below the Waterfall/RTA view showing large, glanceable current values: Tracked Frequency, Anomaly Candidate indicator, and SPL. Read-only — no controls live here.

**Controls row**:
The screen region below the Measured Data row holding all adjustable settings, arranged as two fixed lines (not a wrapping flat list): Line 1 is Analysis settings (Weighting, Time Averaging), View controls (Peak, Freeze, Stop), and Signal Generator (waveform type, on/off, level — right-aligned, Output Device excluded). Line 2 is Input Device (left), Appearance Mode (center), Output Device (right). Deliberately separated from the Measured Data row so measured values are never adjacent to controls that change them. The RTA/waterfall toggle is not here — it lives in the top-right corner of the Waterfall/RTA zone itself, since it's about that view specifically.

**Appearance Mode**:
A manually user-selected display theme — Dark (default, for dim/indoor venues) or a high-contrast/Light mode (for direct sunlight/bright outdoor use). Not linked to the macOS system light/dark setting; the two lighting conditions this app targets don't correlate with a user's general OS preference. See ADR 0005.
