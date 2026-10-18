#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

swift build -c release --product TUMMac

BIN="$(swift build -c release --show-bin-path)/TUMMac"
APP_DIR="$ROOT/dist/Token Usage Monitor.app"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"
RES="$CONTENTS/Resources"

rm -rf "$APP_DIR"
mkdir -p "$MACOS" "$RES"
cp "$BIN" "$MACOS/Token Usage Monitor"
cp "$ROOT/Sources/TUMMac/Resources/Info.plist" "$CONTENTS/Info.plist"

# Ad-hoc sign for local Gatekeeper friendliness.
codesign --force --deep --sign - "$APP_DIR" >/dev/null 2>&1 || true

echo "Built: $APP_DIR"
echo "Open with: open \"$APP_DIR\""
