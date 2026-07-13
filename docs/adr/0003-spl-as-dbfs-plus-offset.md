# SPL meter reads dBFS plus a manual offset, not a calibrated reference

v1 has no real SPL calibration (no calibration workflow, no per-device mic sensitivity data), but the longer-term goal is an accurate dBA reading from the built-in microphone. Rather than ship a pure dBFS meter now and restructure later, we're building the display value as `raw dBFS + offset` from the start, where offset is a stored `Double` (default 0) that will eventually be populated by device-specific calibration data.

For v1, the offset gets a bare-bones manual numeric field in the UI — the user can type in a number — rather than either (a) hiding it entirely until real calibration exists, or (b) building a full calibration workflow now. A full workflow would be speculative since the calibration approach (per-device lookup table vs. manual calibration tone + reference meter) isn't decided yet. The meter is honestly relative/uncalibrated until that offset is populated with real data.
