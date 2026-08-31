# Releasing FreqTrace

Lightweight release process (no CI). First release was **v0.1.0**.

**Automated:** `scripts/release.sh vX.Y.Z --publish` runs the whole flow below
(build signed Release → verify signature → `ditto`-zip → create/upload the
GitHub release targeting `main`). Omit `--publish` to build + zip only. It
mirrors SoundCheck's `scripts/release.sh`, so the two companion apps share one
release path. The manual steps below remain the reference for what it does —
and the one thing it doesn't automate: the version bump (step 1).

## ⚠️ Signing caveat (read first)

The Release build is signed with an **Apple Development** certificate and is
**not notarized**, so macOS Gatekeeper **rejects** it (`spctl -a -t exec` →
`rejected`). It runs on the developer's own machine but is generally **blocked
on anyone else's** — a dev-signed app is tied to provisioning, not just warned
about. Release notes must say this plainly; the attached `.app` is for local /
tester use, not general distribution.

**Upgrade path** when real distribution is wanted (future work): build with a
**Developer ID Application** cert → `codesign` with the hardened runtime →
`xcrun notarytool submit` → `xcrun stapler staple`. That's also the natural
point to add a GitHub Actions workflow so build/test/sign/notarize/attach stop
being manual.

## Steps

1. **Bump the version.** `MARKETING_VERSION` in `FreqTrace.xcodeproj/project.pbxproj`
   (six entries — three targets × Debug/Release; keep them in sync). The tag
   convention is `vX.Y.Z` matching this value. Commit the bump.
2. **Build a universal Release** into a throwaway derived-data dir (`build/` is
   gitignored). The `ARCHS`/`ONLY_ACTIVE_ARCH` overrides are load-bearing: a
   concrete `-destination 'platform=macOS'` otherwise builds only the host arch
   (arm64 on the dev machine), which is how v0.1.0–v0.4.1 shipped arm64-only and
   wouldn't launch on Intel Macs. The project's Release config also sets
   `ARCHS = "arm64 x86_64"`, but the concrete destination overrides it, so the
   command line must repeat it:
   ```
   xcodebuild -project FreqTrace.xcodeproj -scheme FreqTrace \
     -configuration Release -destination 'platform=macOS' \
     ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO \
     -derivedDataPath "$PWD/build/release" build
   ```
   Verify it's fat: `lipo -archs build/release/Build/Products/Release/FreqTrace.app/Contents/MacOS/FreqTrace`
   must list both `arm64` and `x86_64` (`release.sh` fails the build if not).
3. **Zip the app with `ditto`** (preserves the code signature — a plain `zip`
   can corrupt it):
   ```
   ditto -c -k --sequesterRsrc --keepParent \
     build/release/Build/Products/Release/FreqTrace.app \
     build/dist/FreqTrace-vX.Y.Z-macos.zip
   ```
4. **Push** `main`, then **create the release** (targets `main`, attaches the zip):
   ```
   gh release create vX.Y.Z --title "FreqTrace vX.Y.Z" \
     --notes-file <notes.md> --target main \
     build/dist/FreqTrace-vX.Y.Z-macos.zip
   ```

## Verify

- `gh release view vX.Y.Z --json tagName,isDraft,assets` → `isDraft: false`, zip attached.
- Confirm the built app reports the right version:
  `/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' <app>/Contents/Info.plist`.
