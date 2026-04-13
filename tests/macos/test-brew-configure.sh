#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT_FILE="$ROOT/scripts/macos/brew-configure"

test -f "$SCRIPT_FILE"
grep -q '^require_macos$' "$SCRIPT_FILE"
python3 - "$SCRIPT_FILE" <<'PY'
from pathlib import Path
import sys

lines = Path(sys.argv[1]).read_text().splitlines()
expected = [
    '"$SCRIPT_DIR/caddy-configure"',
    '"$SCRIPT_DIR/caddy-trust"',
    '"$SCRIPT_DIR/ghostty-configure"',
    '"$SCRIPT_DIR/jj-configure"',
    '"$SCRIPT_DIR/nushell-configure"',
    '"$SCRIPT_DIR/devtools-configure"',
    '"$SCRIPT_DIR/system-configure"',
    '"$SCRIPT_DIR/podman-configure"',
]

positions = [lines.index(item) for item in expected]
assert positions == sorted(positions)
PY

echo "Brew configure checks passed"
