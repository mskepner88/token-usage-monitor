#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
"$ROOT/scripts/package-app.sh"
open "$ROOT/dist/Token Usage Monitor.app"
