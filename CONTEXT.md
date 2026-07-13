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
A frequency/band flagged by the anomaly detector as narrowband, harmonically unrelated to other energy present, and sustained (flat or growing, not decaying) over a rolling window of recent frames. Covers both feedback and room resonance without distinguishing which caused it — v1 does not attempt cause classification.
_Avoid_: Feedback candidate, ringing candidate, resonance candidate (each implies a specific cause; the detector doesn't know the cause in v1)

**Harmonic Relation**:
Two frequency components are harmonically related if one sits at an integer multiple of the other (e.g. ~2x, ~3x). An Anomaly Candidate must lack this relation to other concurrent energy — presence of a harmonic series marks a peak as musical content instead.

**Peak Hold**:
A passive per-band marker showing the max level seen within a rolling/resettable time window, displayed while the live view keeps updating underneath it. Distinct from Freeze — Peak Hold never stops the live display.
_Avoid_: Max-hold (used interchangeably in early notes; Peak Hold is now the canonical term)

**Freeze**:
An explicit, user-triggered pause of an entire view's updates, so the tech can walk away from the screen and study a static snapshot. Distinct from Peak Hold — Freeze stops everything, not just a marker.

**Time Averaging**:
A post-FFT stage that blends level across consecutive frames (Fast/Slow presets) to control how quickly a view's displayed value responds, independent of FFT window size or frequency resolution. Selected per-view, not globally — the Anomaly Candidate detector is fixed to Fast (never user-selectable, since catching a building ring requires fast response); other views may offer Fast/Slow as a user choice.
_Avoid_: Smoothing (ambiguous with Octave Smoothing — always specify which)

**Octave Smoothing**:
A frequency-domain averaging across neighboring FFT bins at a single instant (e.g. 1/3, 1/6, 1/12-oct), reducing bin-to-bin jaggedness in a spectrum display. Distinct from Time Averaging — this smooths across frequency, not across time. Not yet decided whether/how this is exposed in v1.
_Avoid_: Smoothing (ambiguous with Time Averaging — always specify which)
