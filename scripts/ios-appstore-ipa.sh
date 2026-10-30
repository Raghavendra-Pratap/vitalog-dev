#!/usr/bin/env bash
# Build App Store IPA using a manually downloaded App Store provisioning profile.
# Prereqs:
#   1. App ID app.vitalog
#   2. Profile type "App Store Connect" for app.vitalog + Apple Distribution cert
#   3. Profile installed (double-click .mobileprovision) or placed in
#        ~/Library/MobileDevice/Provisioning Profiles/
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$ROOT/app"
OUT="${VITALOG_OUT:-$HOME/Desktop/Vitalog-store}"
TEAM_ID="${APPLE_TEAM_ID:-3L353J3XDD}"
PROFILE_NAME="${IOS_PROFILE_NAME:-}"
PBXPROJ="$APP_DIR/ios/Runner.xcodeproj/project.pbxproj"

mkdir -p "$OUT"
export PATH="/opt/homebrew/bin:$PATH"

# Detect installed App Store profile for app.vitalog
PROFILE_DIR="$HOME/Library/MobileDevice/Provisioning Profiles"
mkdir -p "$PROFILE_DIR"
FOUND=""
for f in "$PROFILE_DIR"/*.mobileprovision; do
  [[ -f "$f" ]] || continue
  dump="$(security cms -D -i "$f" 2>/dev/null || true)"
  echo "$dump" | rg -q "app.vitalog" || continue
  echo "$dump" | rg -qi "ProvisionedDevices" && continue  # skip development profiles
  NAME="$(echo "$dump" | plutil -extract Name raw -o - -- - 2>/dev/null || true)"
  if [[ -z "$NAME" ]]; then
    NAME="$(echo "$dump" | rg -A1 "<key>Name</key>" | rg "<string>" | head -1 | sed 's/.*<string>//;s/<.*//')"
  fi
  FOUND="$NAME"
  echo "Found App Store profile: $NAME ($f)"
  break
done

if [[ -z "$FOUND" && -z "$PROFILE_NAME" ]]; then
  echo "ERROR: No App Store provisioning profile for app.vitalog installed."
  echo "Create one: https://developer.apple.com/account/resources/profiles/list"
  echo "  + → App Store Connect → App ID app.vitalog → Apple Distribution → Download → double-click"
  exit 1
fi
PROFILE_NAME="${PROFILE_NAME:-$FOUND}"

EXPORT_PLIST="$APP_DIR/ios/ExportOptions-AppStore-Manual.plist"
cat > "$EXPORT_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key>
	<string>app-store-connect</string>
	<key>teamID</key>
	<string>${TEAM_ID}</string>
	<key>signingStyle</key>
	<string>manual</string>
	<key>signingCertificate</key>
	<string>Apple Distribution</string>
	<key>provisioningProfiles</key>
	<dict>
		<key>app.vitalog</key>
		<string>${PROFILE_NAME}</string>
	</dict>
	<key>uploadSymbols</key>
	<true/>
</dict>
</plist>
PLIST

# Patch only Runner Release/Profile signing (do not pass profile on xcodebuild CLI —
# that incorrectly applies to Pods/SPM targets).
PBX_BAK="$(mktemp)"
cp "$PBXPROJ" "$PBX_BAK"
restore_pbx() { cp "$PBX_BAK" "$PBXPROJ"; rm -f "$PBX_BAK"; }
trap restore_pbx EXIT

python3 - "$PBXPROJ" "$PROFILE_NAME" "$TEAM_ID" <<'PY'
import pathlib, re, sys
path, profile, team = pathlib.Path(sys.argv[1]), sys.argv[2], sys.argv[3]
text = path.read_text()

def patch_block(block: str) -> str:
    # Only Runner app configs contain PRODUCT_BUNDLE_IDENTIFIER = app.vitalog;
    if "PRODUCT_BUNDLE_IDENTIFIER = app.vitalog;" not in block:
        return block
    if "name = Debug;" in block:
        return block  # leave Debug automatic for local runs
    block = re.sub(r"CODE_SIGN_STYLE = Automatic;", "CODE_SIGN_STYLE = Manual;", block)
    if "CODE_SIGN_IDENTITY" not in block:
        block = block.replace(
            "CODE_SIGN_STYLE = Manual;",
            'CODE_SIGN_STYLE = Manual;\n\t\t\t\tCODE_SIGN_IDENTITY = "Apple Distribution";',
        )
    else:
        block = re.sub(
            r'CODE_SIGN_IDENTITY(?:\[sdk=iphoneos\*\])? = "[^"]*";',
            'CODE_SIGN_IDENTITY = "Apple Distribution";',
            block,
        )
    if "PROVISIONING_PROFILE_SPECIFIER" not in block:
        block = block.replace(
            f"DEVELOPMENT_TEAM = {team};",
            f'DEVELOPMENT_TEAM = {team};\n\t\t\t\tPROVISIONING_PROFILE_SPECIFIER = "{profile}";',
        )
    else:
        block = re.sub(
            r'PROVISIONING_PROFILE_SPECIFIER = "[^"]*";',
            f'PROVISIONING_PROFILE_SPECIFIER = "{profile}";',
            block,
        )
    return block

# Split XCBuildConfiguration blocks roughly
parts = re.split(r"(/\* Begin XCBuildConfiguration section \*/|/\* End XCBuildConfiguration section \*/)", text)
if len(parts) < 3:
    raise SystemExit("Could not find XCBuildConfiguration section")
# parts[0] before, parts[1] begin marker, parts[2] body, parts[3] end marker, parts[4] after
body = parts[2]
configs = re.split(r"(?=\t\t[A-F0-9]{24} /\* (?:Debug|Release|Profile) \*/ = \{)", body)
configs = [patch_block(c) for c in configs]
parts[2] = "".join(configs)
path.write_text("".join(parts))
print(f"Patched Runner Release/Profile → Manual + {profile}")
PY

# Ensure CocoaPods targets do not require provisioning profiles
PODFILE="$APP_DIR/ios/Podfile"
if ! rg -q "CODE_SIGNING_ALLOWED" "$PODFILE"; then
  python3 - "$PODFILE" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
t = p.read_text()
needle = "config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '15.5'"
insert = needle + "\n      config.build_settings['CODE_SIGNING_ALLOWED'] = 'NO'"
if needle in t and "CODE_SIGNING_ALLOWED" not in t:
    p.write_text(t.replace(needle, insert, 1))
    print("Podfile: CODE_SIGNING_ALLOWED=NO for pods")
PY
  (cd "$APP_DIR/ios" && pod install --silent)
fi

cd "$APP_DIR"
echo "==> flutter build ipa (manual App Store profile: $PROFILE_NAME)"
flutter build ipa --release --export-options-plist="$EXPORT_PLIST"

IPA="$(ls -1 "$APP_DIR"/build/ios/ipa/*.ipa 2>/dev/null | head -1 || true)"
if [[ -z "$IPA" ]]; then
  echo "ERROR: IPA not produced"
  exit 1
fi
cp -f "$IPA" "$OUT/"
echo "OK: $OUT/$(basename "$IPA")"
echo "Upload with Transporter (Mac App Store) → App Store Connect → TestFlight."
