#!/usr/bin/env bash
# Package an already-built app into a signed+notarized DMG, or an unsigned zip.
# Signing runs only when every secret listed in docs/RELEASING.md is set.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/dist/Token Usage Monitor.app"
PLIST="$APP/Contents/Info.plist"

if [[ ! -d "$APP" ]]; then
  echo "Missing $APP — run scripts/package-app.sh first." >&2
  exit 1
fi

VERSION="${GITHUB_REF_NAME:-}"
VERSION="${VERSION#v}"
if [[ -z "$VERSION" ]]; then
  VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")"
fi

plist_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")"
if [[ -n "${GITHUB_REF_NAME:-}" && "$plist_version" != "$VERSION" ]]; then
  echo "Tag $VERSION does not match Info.plist $plist_version" >&2
  exit 1
fi

write_output() {
  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    printf '%s\n' "$1" >> "$GITHUB_OUTPUT"
  fi
}

signing_ready=1
for name in \
  APPLE_CERTIFICATE_BASE64 \
  APPLE_CERTIFICATE_PASSWORD \
  APPLE_SIGNING_IDENTITY \
  APPLE_TEAM_ID \
  APPLE_ID \
  APPLE_APP_SPECIFIC_PASSWORD
do
  if [[ -z "${!name:-}" ]]; then
    signing_ready=0
  fi
done

if [[ "$signing_ready" -ne 1 ]]; then
  ZIP="$ROOT/dist/TokenUsageMonitor-${VERSION}-unsigned.zip"
  rm -f "$ZIP"
  ditto -c -k --keepParent "$APP" "$ZIP"
  echo "Signing secrets missing. Uploaded path will be the unsigned zip."
  write_output "mode=unsigned"
  write_output "path=$ZIP"
  exit 0
fi

KEYCHAIN="$RUNNER_TEMP/tum-signing.keychain-db"
if [[ -z "${RUNNER_TEMP:-}" ]]; then
  KEYCHAIN="$(mktemp -d)/tum-signing.keychain-db"
fi
KEYCHAIN_PASSWORD="$(uuidgen)"
P12="$(mktemp)"
cleanup() {
  security delete-keychain "$KEYCHAIN" >/dev/null 2>&1 || true
  rm -f "$P12"
}
trap cleanup EXIT

echo "$APPLE_CERTIFICATE_BASE64" | base64 -D > "$P12"
security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security set-keychain-settings -lut 21600 "$KEYCHAIN"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security import "$P12" -P "$APPLE_CERTIFICATE_PASSWORD" -A -t cert -f pkcs12 -k "$KEYCHAIN"
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN" >/dev/null
security list-keychains -d user -s "$KEYCHAIN" $(security list-keychains -d user | tr -d '"')

codesign --force --options runtime --timestamp \
  --sign "$APPLE_SIGNING_IDENTITY" \
  --keychain "$KEYCHAIN" \
  "$APP"
codesign --verify --strict --verbose=2 "$APP"

NOTARY_ZIP="$(mktemp -d)/TokenUsageMonitor.zip"
ditto -c -k --keepParent "$APP" "$NOTARY_ZIP"
xcrun notarytool submit "$NOTARY_ZIP" \
  --apple-id "$APPLE_ID" \
  --password "$APPLE_APP_SPECIFIC_PASSWORD" \
  --team-id "$APPLE_TEAM_ID" \
  --wait
xcrun stapler staple "$APP"

DMG="$ROOT/dist/TokenUsageMonitor-${VERSION}.dmg"
rm -f "$DMG"
hdiutil create -volname "Token Usage Monitor" -srcfolder "$APP" -ov -format UDZO "$DMG"
echo "Notarized DMG: $DMG"
write_output "mode=signed"
write_output "path=$DMG"
