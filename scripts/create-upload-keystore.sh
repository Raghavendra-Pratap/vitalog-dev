#!/usr/bin/env bash
# Creates a Play upload keystore + android/key.properties (gitignored).
# Back up the .jks and passwords offline. Never commit them.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ANDROID="$ROOT/app/android"
KEYSTORE="$ANDROID/upload-keystore.jks"
PROPS="$ANDROID/key.properties"

if [[ -f "$KEYSTORE" ]]; then
  echo "Already exists: $KEYSTORE — refusing to overwrite."
  exit 1
fi

STORE_PASS="$(openssl rand -base64 24 | tr -d '/+=' | head -c 24)"
KEY_PASS="$STORE_PASS"
ALIAS=upload

keytool -genkeypair -v \
  -keystore "$KEYSTORE" \
  -storetype JKS \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias "$ALIAS" \
  -storepass "$STORE_PASS" \
  -keypass "$KEY_PASS" \
  -dname "CN=Vitalog upload, OU=BSOC, O=BSOC, L=India, C=IN"

cat > "$PROPS" << PROP
storePassword=$STORE_PASS
keyPassword=$KEY_PASS
keyAlias=$ALIAS
storeFile=upload-keystore.jks
PROP

chmod 600 "$PROPS" "$KEYSTORE"
echo "Created (gitignored):"
echo "  $KEYSTORE"
echo "  $PROPS"
echo "Back these up in a password manager. Passwords are only in key.properties — not printed here."
