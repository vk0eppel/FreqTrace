# FreqTrace

Real-time audio analysis for live sound techs at FOH — spectrogram, frequency tracking, anomaly (feedback/resonance) detection.

## Language

**Tracked Frequency**:
The single frequency currently carrying the most energy, per the active Weighting. Drives the primary numeric readout. Always has a value during signal presence — it is not conditioned on anything being wrong.
_Avoid_: Dominant frequency, peak frequency

**Weighting**:
A single global setting (A/C/Z, user-selectable, defaults to A) applied wherever the app judges "loudest" or measures level — currently the Tracked Frequency and the SPL meter. One setting shared across features, not configured per-feature.
_Avoid_: Weighting curve (fine as a description, but the app concept is the single shared setting)

**SPL Offset**:
A manually-entered number (default 0) added to the raw dBFS level to produce the SPL meter's displayed value. Placeholder for future device mic calibration data — v1 has no real calibration, so the meter is honestly relative/uncalibrated until this is populated with accurate data.
_Avoid_: Calibration (implies an accuracy v1 doesn't have yet)

**Anomaly Candidate**:
A frequency/band flagged by the anomaly detector as narrowband, harmonically unrelated to other energy present, and sustained (flat or growing, not decaying) over a rolling window of recent frames. Covers both feedback and room resonance without distinguishing which caused it — v1 does not attempt cause classification. Multiple Anomaly Candidates can be flagged at once (e.g. two separate rings building simultaneously); the Measured Data row shows the top 2-3, ranked by severity/confidence — not collapsed to a single slot.
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
An explicit, user-triggered halt of the AVAudioEngine capture pipeline itself — audio capture stops, not just the display. Used when the tech is done measuring for a while (between soundcheck and doors, on a break), not for quick glances. Resuming requires re-initializing capture, so it's slower than un-Freezing. Distinct from Freeze.
_Avoid_: Pause (ambiguous with Freeze — always use the specific term)

**Input Device**:
The system audio input source the capture pipeline reads from. Defaults to the system default input on first launch; remembers the tech's last explicit choice thereafter. If the selected device disconnects mid-use, the pipeline enters Stopped state and the UI shows an explicit disconnected indicator — it never silently falls back to a different device, since that could show the tech data from a source they don't realize changed. See ADR 0006.

**Output Device**:
The system audio output the Signal Generator plays through. Same shape and same disconnect behavior as Input Device (own selector, no silent fallback — the generator stops and shows disconnected rather than risk playing a test tone out of an unintended output). See ADR 0006.

**Time Averaging**:
A post-FFT stage that blends level across consecutive frames (Fast/Slow presets) to control how quickly a view's displayed value responds, independent of FFT window size or frequency resolution. Selected per-view, not globally — the Anomaly Candidate detector is fixed to Fast (never user-selectable, since catching a building ring requires fast response); other views may offer Fast/Slow as a user choice.
_Avoid_: Smoothing (ambiguous with Octave Smoothing — always specify which)

**Octave Smoothing**:
A frequency-domain averaging across neighboring FFT bins at a single instant (e.g. 1/3, 1/6, 1/12-oct), reducing bin-to-bin jaggedness in a spectrum display. Distinct from Time Averaging — this smooths across frequency, not across time. Not yet decided whether/how this is exposed in v1.
_Avoid_: Smoothing (ambiguous with Time Averaging — always specify which)

**Measured Data row**:
The screen region directly below the Waterfall/RTA view showing large, glanceable current values: Tracked Frequency, Anomaly Candidate indicator, and SPL. Read-only — no controls live here.

**Controls row**:
The screen region below the Measured Data row holding all adjustable settings, grouped into zones rather than a flat list: Input Device · Analysis settings (Weighting, Time Averaging) · View controls (Peak, Freeze, Stop) · Appearance Mode · Signal Generator (waveform type, on/off, level, Output Device — far right). Deliberately separated from the Measured Data row so measured values are never adjacent to controls that change them. The RTA/waterfall toggle is not here — it lives in the top-right corner of the Waterfall/RTA zone itself, since it's about that view specifically.

**Appearance Mode**:
A manually user-selected display theme — Dark (default, for dim/indoor venues) or a high-contrast/Light mode (for direct sunlight/bright outdoor use). Not linked to the macOS system light/dark setting; the two lighting conditions this app targets don't correlate with a user's general OS preference. See ADR 0005.
