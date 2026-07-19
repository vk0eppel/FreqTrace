#!/usr/bin/env bash
#
# Cut a signed FreqTrace release locally. Automates docs/release.md.
#
# A plain Release build already signs with the project's Apple *Development*
# identity + hardened runtime (that's why FreqTrace opens on this machine
# while an ad-hoc/unsigned build would hit Gatekeeper's hard block). This is
# the same process SoundCheck's scripts/release.sh uses, so the two companion
# apps share one release path.
#
# NOT notarized (needs a paid Developer ID), so it still won't open
# friction-free on other people's Macs -- see docs/release.md's signing caveat
# and the release note below.
#
# Usage:  scripts/release.sh v0.3.0 [--publish]
#   without --publish: builds + zips into build/dist, does not touch GitHub
#   with    --publish: also `gh release create`/uploads the signed zip (--target main)
#
set -euo pipefail

TAG="${1:?usage: scripts/release.sh vX.Y.Z [--publish]}"
PUBLISH="${2:-}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/release/Build/Products/Release/FreqTrace.app"
ZIP="$ROOT/build/dist/FreqTrace-$TAG-macos.zip"

echo "==> Building signed Release for $TAG"
rm -rf "$ROOT/build/release"
xcodebuild -project "$ROOT/FreqTrace.xcodeproj" -scheme FreqTrace \
  -configuration Release -destination 'platform=macOS' \
  -derivedDataPath "$ROOT/build/release" build

echo "==> Verifying signature"
codesign --verify --strict --verbose=2 "$APP"

echo "==> Zipping (ditto, preserves the signature) -> $ZIP"
mkdir -p "$ROOT/build/dist"; rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

if [[ "$PUBLISH" == "--publish" ]]; then
  echo "==> Publishing GitHub release $TAG (targets main)"
  NOTE=$'Signed with an Apple Development certificate (not notarized). Opens cleanly on Macs that trust this developer; generally blocked on others.\nOn an unrecognized Mac, first launch: right-click `FreqTrace.app` > **Open** > **Open**.'
  if gh release view "$TAG" >/dev/null 2>&1; then
    gh release upload "$TAG" "$ZIP" --clobber
  else
    gh release create "$TAG" --title "FreqTrace $TAG" --target main \
      --generate-notes --notes "$NOTE" "$ZIP"
  fi
fi

echo "==> Done: $ZIP"
