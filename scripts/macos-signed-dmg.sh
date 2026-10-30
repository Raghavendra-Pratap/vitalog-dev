#!/usr/bin/env bash
# Build → Developer ID sign → DMG → notarize → staple.
# Prereqs:
#   1. "Developer ID Application: …" identity in Keychain
#   2. Notary auth via one of:
#        export APPLE_ID=… APPLE_APP_SPECIFIC_PASSWORD=… APPLE_TEAM_ID=3L353J3XDD
#      or export APPLE_API_KEY=… APPLE_API_ISSUER=… APPLE_API_KEY_PATH=~/AuthKey_….p8
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$ROOT/app"
OUT="${VITALOG_OUT:-$HOME/Desktop/Vitalog-store}"
VERSION="$(python3 - <<'PY'
import re
from pathlib import Path
text = Path("/Users/raghavendra_pratap/Developer/bodyline/app/pubspec.yaml").read_text()
m = re.search(r"^version:\s*([^\s+]+)", text, re.M)
print(m.group(1) if m else "0.0.0")
PY
)"
BUILD="$(python3 - <<'PY'
import re
from pathlib import Path
text = Path("/Users/raghavendra_pratap/Developer/bodyline/app/pubspec.yaml").read_text()
m = re.search(r"^version:\s*[^\s+]+\+(\d+)", text, re.M)
print(m.group(1) if m else "0")
PY
)"
APP_NAME="Vitalog"
BUNDLE_ID="app.vitalog"
TEAM_ID="${APPLE_TEAM_ID:-3L353J3XDD}"
IDENTITY="${DEVELOPER_ID_IDENTITY:-}"
if [[ -z "$IDENTITY" ]]; then
  IDENTITY="$(security find-identity -v -p codesigning | awk -F'"' '/Developer ID Application/ {print $2; exit}')"
fi
if [[ -z "$IDENTITY" ]]; then
  echo "ERROR: No 'Developer ID Application' identity in Keychain."
  echo "Create one at https://developer.apple.com/account/resources/certificates/list"
  echo "Upload CSR: $OUT/signing/Vitalog-DeveloperID.certSigningRequest"
  echo "Then double-click the downloaded .cer to install."
  exit 1
fi

mkdir -p "$OUT"
export PATH="/opt/homebrew/bin:$PATH"
cd "$APP_DIR"

echo "==> flutter build macos --release"
flutter build macos --release

APP="$APP_DIR/build/macos/Build/Products/Release/${APP_NAME}.app"
if [[ ! -d "$APP" ]]; then
  echo "ERROR: missing $APP"
  exit 1
fi

ENTITLEMENTS="$APP_DIR/macos/Runner/Release.entitlements"
echo "==> codesign with: $IDENTITY"
# Deep sign frameworks/plugins first, then the app bundle
find "$APP" -type f \( -name "*.dylib" -o -name "*.so" \) -print0 | while IFS= read -r -d '' f; do
  codesign --force --options runtime --timestamp --sign "$IDENTITY" "$f" || true
done
find "$APP/Contents/Frameworks" -name "*.framework" -maxdepth 2 -print0 2>/dev/null | while IFS= read -r -d '' f; do
  codesign --force --options runtime --timestamp --sign "$IDENTITY" --entitlements "$ENTITLEMENTS" "$f" || true
done
codesign --force --deep --options runtime --timestamp \
  --entitlements "$ENTITLEMENTS" \
  --sign "$IDENTITY" \
  "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

DMG="$OUT/${APP_NAME}-${VERSION}+${BUILD}.dmg"
STAGE="$OUT/dmg-stage"
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
echo "==> hdiutil create $DMG"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
rm -rf "$STAGE"

echo "==> notarize"
ZIP="$OUT/${APP_NAME}-${VERSION}+${BUILD}-notarize.zip"
ditto -c -k --keepParent "$APP" "$ZIP"

NOTARY_ARGS=()
if [[ -n "${APPLE_API_KEY:-}" && -n "${APPLE_API_ISSUER:-}" && -n "${APPLE_API_KEY_PATH:-}" ]]; then
  NOTARY_ARGS=(--key "$APPLE_API_KEY_PATH" --key-id "$APPLE_API_KEY" --issuer "$APPLE_API_ISSUER")
elif [[ -n "${APPLE_ID:-}" && -n "${APPLE_APP_SPECIFIC_PASSWORD:-}" ]]; then
  NOTARY_ARGS=(--apple-id "$APPLE_ID" --password "$APPLE_APP_SPECIFIC_PASSWORD" --team-id "$TEAM_ID")
else
  echo "ERROR: Set APPLE_ID + APPLE_APP_SPECIFIC_PASSWORD + APPLE_TEAM_ID"
  echo "   or APPLE_API_KEY + APPLE_API_ISSUER + APPLE_API_KEY_PATH"
  echo "DMG built (unsigned-notary): $DMG"
  echo "Signed app zip for notary: $ZIP"
  exit 2
fi

xcrun notarytool submit "$ZIP" --wait "${NOTARY_ARGS[@]}"
xcrun stapler staple "$APP"
# Rebuild DMG from stapled app
rm -rf "$STAGE"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
rm -rf "$STAGE"
xcrun stapler staple "$DMG" || true

echo "OK: $DMG"
spctl --assess --type open --context context:primary-signature -v "$DMG" || true
