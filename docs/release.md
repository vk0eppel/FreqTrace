# Releasing FreqTrace

Manual, lightweight release process (no CI). First release was **v0.1.0**.
There is no `.github/workflows` automation yet — every step below is by hand.

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
2. **Build Release** into a throwaway derived-data dir (`build/` is gitignored):
   ```
   xcodebuild -project FreqTrace.xcodeproj -scheme FreqTrace \
     -configuration Release -destination 'platform=macOS' \
     -derivedDataPath "$PWD/build/release" build
   ```
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
