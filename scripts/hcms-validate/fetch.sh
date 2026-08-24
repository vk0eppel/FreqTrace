#!/bin/bash
# Downloads the HCMS processed clips + ground-truth CSVs (~37 MB) into a local
# directory (default ~/hcms-data). Not the full 154 MB dataset — only the
# howling-corrupted clips (music_NNNNN.wav / speech_NNNNN.wav) and their CSVs,
# skipping the source songs and AIRs we don't need.
#
# HCMS: KU Leuven Research Data Repository, DOI 10.48804/EOW7OF, CC-BY-4.0.
# Cite: Mounir, Bernardi & van Waterschoot, "Robust and early howling
# detection based on a sparsity measure", EURASIP JASMP 2025.
set -euo pipefail
DEST="${1:-$HOME/hcms-data}"
mkdir -p "$DEST"
API="https://rdr.kuleuven.be/api"
DOI="doi:10.48804/EOW7OF"

echo "Fetching HCMS file list…"
curl -s "$API/datasets/:persistentId/?persistentId=$DOI" \
| python3 -c "
import sys, json, re
files = json.load(sys.stdin)['data']['latestVersion']['files']
for f in files:
    df = f['dataFile']; n = df['filename']
    if re.match(r'(music|speech)_[0-9]{5}\.(wav|csv)$', n):
        print(df['id'], n)
" | while read id name; do
    if [ ! -f "$DEST/$name" ]; then
        curl -sL "$API/access/datafile/$id" -o "$DEST/$name"
    fi
done
echo "Done. $(ls "$DEST"/*.wav 2>/dev/null | wc -l) clips in $DEST"
