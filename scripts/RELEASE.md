# Release runbook — Tessera v1.0.0

A repeatable path from source → a notarized DMG → GitHub Release → Homebrew cask,
plus the KalshiKit SPM tag. Steps marked **(you)** need your Apple account/machine
and can't be automated from here.

## 0. One-time setup **(you)**

1. **Developer ID Application certificate** — you currently have only an
   "Apple Development" cert. Create the distribution one:
   Xcode ▸ Settings ▸ Accounts ▸ *your team* ▸ Manage Certificates ▸ **+** ▸
   **Developer ID Application**. Confirm:
   ```sh
   security find-identity -v -p codesigning | grep "Developer ID Application"
   ```
2. **Notarization credentials** — create an app-specific password at
   <https://account.apple.com> (Sign-In & Security ▸ App-Specific Passwords), then:
   ```sh
   xcrun notarytool store-credentials tessera-notary \
     --apple-id "you@example.com" --team-id 347LA37C2B --password "abcd-efgh-ijkl-mnop"
   ```
3. **Tools**: `brew install create-dmg xcodegen`.
4. **Register identifiers** on <https://developer.apple.com> under your team so
   automatic signing can mint a Developer ID profile with the App Group:
   - App IDs: `app.tessera.Tessera`, `app.tessera.Tessera.TesseraWidget`
   - App Group: `group.app.tessera` (add the capability to both App IDs)

## 1. Cut the release DMG

```sh
./scripts/release.sh
```

This generates the project, archives Release, exports with Developer ID signing,
verifies the signature + hardened runtime, builds the DMG, **notarizes and staples**
it, and prints the DMG path + its **SHA256**. (Override `TEAM_ID`,
`NOTARY_PROFILE`, or `SIGN_IDENTITY` via env if needed.)

## 2. Publish the GitHub Release **(you)**

```sh
gh release create v1.0.0 Tessera/release-build/Tessera-1.0.0.dmg \
  --title "Tessera v1.0.0" \
  --notes-file docs/RELEASE_NOTES_v1.0.0.md
```

## 3. Tag the SDK (KalshiKit) for SwiftPM

KalshiKit is consumable on its own. Tag it so `from: "1.0.0"` resolves:

```sh
git tag kalshikit-v1.0.0 -m "KalshiKit 1.0.0"
git push origin kalshikit-v1.0.0
```

(If you later split KalshiKit into its own repo, move the tag there. For now the
package path is `KalshiKit/` in this repo.)

## 4. Homebrew cask **(you)**

Update `Casks/tessera.rb` with the new `version`, the `sha256` printed by the
release script, and confirm the release URL. Then either:
- host a personal tap: `IvanKuria/homebrew-tessera` →
  `brew install ivankuria/tessera/tessera`, or
- once there's adoption, PR it to `homebrew/cask`.

## 5. Smoke-test the notarized build

On a clean machine (or a fresh user): download the DMG from the Release, open it,
drag to Applications, launch. It must open **without** the "unidentified developer"
warning (proves notarization + stapling worked). Connect a **demo** Kalshi key and
confirm the key persists across relaunch (the stable Developer ID signature is what
makes the Keychain item readable across launches).

## 6. Launch posts **(you)**

- Kalshi Discord `#dev`, r/macapps, r/algotrading, Product Hunt.
- Lead with the SDK (KalshiKit) for the dev crowd; the app as the showcase.
- Always include the unofficial / not-affiliated / not-financial-advice framing.
