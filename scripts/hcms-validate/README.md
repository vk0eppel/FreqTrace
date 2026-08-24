# HCMS real-signal validation

Scores the throwaway anomaly-detection prototype (`FreqTraceTests/PrototypeAnomalyDetector.swift`)
against **real** howling-corrupted audio, to check the synthetic-tuned criteria
(#36) against real feedback. Findings + interpretation:
[`docs/research/anomaly-hcms-validation.md`](../../docs/research/anomaly-hcms-validation.md).

## Why a standalone script (not a unit test)

The app has `ENABLE_APP_SANDBOX=YES`, so a hosted `xctest` can't read external
audio files. This compiles the pure DSP sources + the prototype into a
standalone, non-sandboxed binary via `swiftc` and runs the analysis offline. It
is a one-off validation, not a regression test.

## Usage

```sh
scripts/hcms-validate/fetch.sh          # ~37 MB → ~/hcms-data (not committed)
scripts/hcms-validate/run.sh            # compile + score
```

## Dataset

**HCMS — Howling Corrupted Music and Speech**, KU Leuven, **CC-BY-4.0**,
DOI [10.48804/EOW7OF](https://rdr.kuleuven.be/dataset.xhtml?persistentId=doi:10.48804/EOW7OF).
58 processed clips (28 music + 30 speech), 20 s @ 16 kHz, howling ramping up at
t=8 s; per-clip CSV gives the howling (MSG) frequency. The audio is **not
committed** (licensing + size) — `fetch.sh` pulls it locally.

Cite: Mounir, Bernardi & van Waterschoot, *"Robust and early howling detection
based on a sparsity measure"*, EURASIP J. Audio Speech Music Process. 2025.
