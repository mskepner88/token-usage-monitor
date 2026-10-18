#!/usr/bin/env bash
# One-time helper: copy Claude Code OAuth into TUM's local file (no Keychain use by the app).
set -euo pipefail

OUT_DIR="${HOME}/Library/Application Support/TokenUsageMonitor"
OUT_FILE="${OUT_DIR}/claude-credentials.json"
mkdir -p "${OUT_DIR}"

# Prefer the current macOS username account — Claude Code may leave a stale "root" entry.
security find-generic-password -s "Claude Code-credentials" -a "${USER}" -w > "${OUT_FILE}"
chmod 600 "${OUT_FILE}"

python3 - <<'PY'
import json
from pathlib import Path
from datetime import datetime, timezone
p = Path.home() / "Library/Application Support/TokenUsageMonitor/claude-credentials.json"
oauth = json.loads(p.read_text())["claudeAiOauth"]
exp = datetime.fromtimestamp(oauth["expiresAt"] / 1000, timezone.utc)
now = datetime.now(timezone.utc)
print(f"Wrote {p}")
print(f"subscription={oauth.get('subscriptionType')} expires={exp.isoformat()} ({'valid' if exp > now else 'EXPIRED'})")
if exp <= now:
    raise SystemExit("Token is expired — run: claude auth login")
PY

echo "Refresh TUM (chart icon → circular arrow)."
