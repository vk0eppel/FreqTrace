#!/bin/bash
# Reproduces the HCMS real-signal validation (ticket #37 /
# docs/research/anomaly-hcms-validation.md).
#
# The FreqTrace app is sandboxed (ENABLE_APP_SANDBOX=YES), so a hosted unit
# test can't read external audio. This compiles the DSP sources + the
# throwaway prototype detector into a standalone (non-sandboxed) binary and
# scores it against a local copy of the HCMS dataset.
#
# 1. Get the data (~37 MB of processed clips + CSVs; not committed):
#      scripts/hcms-validate/fetch.sh          # downloads to ~/hcms-data
#    HCMS: KU Leuven, CC-BY-4.0, DOI 10.48804/EOW7OF (attribution required).
# 2. Run:
#      scripts/hcms-validate/run.sh [data-dir]  # default ~/hcms-data
set -euo pipefail
cd "$(dirname "$0")/../.."
DATA="${1:-$HOME/hcms-data}"
BUILD="$(mktemp -d)"

# The prototype detector @testable-imports FreqTrace; as a single-module
# standalone build there's no separate module, so strip that import.
grep -v "@testable import FreqTrace" FreqTraceTests/PrototypeAnomalyDetector.swift > "$BUILD/PrototypeAnomalyDetector.swift"

swiftc -O -framework Accelerate \
  FreqTrace/Analysis/FrequencyTracker.swift \
  FreqTrace/Analysis/AnalysisConfig.swift \
  FreqTrace/Analysis/FFTWindowSize.swift \
  FreqTrace/Analysis/Weighting.swift \
  FreqTrace/Waterfall/MagnitudeScaling.swift \
  FreqTrace/Analysis/AnomalyDetector.swift \
  "$BUILD/PrototypeAnomalyDetector.swift" \
  scripts/hcms-validate/main.swift \
  -o "$BUILD/hcms_validate"

"$BUILD/hcms_validate" "$DATA"
