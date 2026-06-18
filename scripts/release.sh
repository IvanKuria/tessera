#!/usr/bin/env bash
#
# Tessera release pipeline — build → sign (Developer ID) → .dmg → notarize → staple.
#
# Produces a notarized, Gatekeeper-friendly DMG ready for a GitHub Release and the
# Homebrew cask. Run from the repo root: `./scripts/release.sh`.
#
# PREREQUISITES (one-time, on your machine):
#   1. A "Developer ID Application" certificate installed in your login keychain.
#      Xcode ▸ Settings ▸ Accounts ▸ <team> ▸ Manage Certificates ▸ + ▸
#      "Developer ID Application".  Verify with: security find-identity -v -p codesigning
#   2. A notarytool credential profile saved in the keychain:
#        xcrun notarytool store-credentials tessera-notary \
#          --apple-id "you@example.com" --team-id 6YNA9C4HJ6 \
#          --password "<app-specific-password>"
#      (App-specific password: https://account.apple.com ▸ Sign-In & Security.)
#   3. create-dmg installed:  brew install create-dmg
#   4. The App ID `app.tessera.Tessera` (+ the widget) and the App Group
#      `group.app.tessera` registered under your team on developer.apple.com, so
#      automatic signing can mint a Developer ID provisioning profile.
#
# Override defaults via env: TEAM_ID, NOTARY_PROFILE, SIGN_IDENTITY.
set -euo pipefail

# --- Config ------------------------------------------------------------------
TEAM_ID="${TEAM_ID:-6YNA9C4HJ6}"
NOTARY_PROFILE="${NOTARY_PROFILE:-tessera-notary}"
SCHEME="Tessera"
APP_NAME="Tessera"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT/Tessera"
BUILD="$APP_DIR/release-build"
ARCHIVE="$BUILD/$APP_NAME.xcarchive"
EXPORT_DIR="$BUILD/export"
APP_PATH="$EXPORT_DIR/$APP_NAME.app"

bold() { printf '\033[1m%s\033[0m\n' "$*"; }
fail() { printf '\033[31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

# --- Preflight ---------------------------------------------------------------
bold "▸ Preflight checks"
command -v xcodegen >/dev/null || fail "xcodegen not found (brew install xcodegen)"
command -v create-dmg >/dev/null || fail "create-dmg not found (brew install create-dmg)"

SIGN_IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning \
  | grep "Developer ID Application" | head -1 | sed -E 's/.*"(.*)"/\1/')}"
[ -n "$SIGN_IDENTITY" ] || fail "No 'Developer ID Application' certificate found. See PREREQUISITES."
echo "  signing identity: $SIGN_IDENTITY"

xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1 \
  || fail "notarytool profile '$NOTARY_PROFILE' not found. See PREREQUISITES step 2."
echo "  notarytool profile: $NOTARY_PROFILE  ✓"

# --- Build & archive ---------------------------------------------------------
bold "▸ Generating project + archiving Release"
( cd "$APP_DIR" && xcodegen generate >/dev/null )
rm -rf "$BUILD"; mkdir -p "$BUILD"

xcodebuild -project "$APP_DIR/$APP_NAME.xcodeproj" \
  -scheme "$SCHEME" -configuration Release \
  -archivePath "$ARCHIVE" \
  -destination 'generic/platform=macOS' \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  CODE_SIGN_STYLE=Automatic \
  archive | grep -iE "error:|ARCHIVE SUCCEEDED|warning: .*sign" || true
[ -d "$ARCHIVE" ] || fail "archive failed — see xcodebuild output above"

# --- Export with Developer ID -----------------------------------------------
bold "▸ Exporting (developer-id)"
cat > "$BUILD/export-options.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>developer-id</string>
  <key>teamID</key><string>$TEAM_ID</string>
  <key>signingStyle</key><string>automatic</string>
</dict></plist>
PLIST

xcodebuild -exportArchive -archivePath "$ARCHIVE" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist "$BUILD/export-options.plist" \
  | grep -iE "error:|EXPORT SUCCEEDED" || true
[ -d "$APP_PATH" ] || fail "export failed — no $APP_PATH"

# --- Verify signature + hardened runtime ------------------------------------
bold "▸ Verifying signature"
codesign --verify --deep --strict --verbose=2 "$APP_PATH" || fail "codesign verify failed"
codesign -dvv "$APP_PATH" 2>&1 | grep -q "flags=.*runtime" || fail "hardened runtime not enabled"
echo "  signature + hardened runtime  ✓"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist")"
DMG="$BUILD/$APP_NAME-$VERSION.dmg"

# --- Build DMG ---------------------------------------------------------------
bold "▸ Building DMG ($APP_NAME-$VERSION.dmg)"
rm -f "$DMG"
create-dmg \
  --volname "$APP_NAME $VERSION" \
  --window-size 540 380 \
  --icon-size 100 \
  --icon "$APP_NAME.app" 140 190 \
  --app-drop-link 400 190 \
  --no-internet-enable \
  "$DMG" "$APP_PATH" || fail "create-dmg failed"

# --- Notarize + staple -------------------------------------------------------
bold "▸ Notarizing (this can take a few minutes)"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait \
  || fail "notarization failed — inspect with: xcrun notarytool log <id> --keychain-profile $NOTARY_PROFILE"

bold "▸ Stapling"
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG" || fail "staple validation failed"
spctl --assess --type open --context context:primary-signature -v "$DMG" 2>&1 | grep -q accepted \
  && echo "  Gatekeeper: accepted  ✓" || echo "  (spctl assessment inconclusive — verify manually)"

SHA="$(shasum -a 256 "$DMG" | awk '{print $1}')"
bold "✅ Done"
echo "  DMG:    $DMG"
echo "  SHA256: $SHA   ← put this in Casks/tessera.rb (sha256) and the release notes"
echo
echo "Next:"
echo "  1. gh release create v$VERSION \"$DMG\" --title \"Tessera v$VERSION\" --notes-file docs/RELEASE_NOTES_v$VERSION.md"
echo "  2. Update Casks/tessera.rb: version $VERSION, sha256 $SHA, the release URL."
echo "  3. Tag the SDK:  git tag kalshikit-v$VERSION && git push origin kalshikit-v$VERSION"
