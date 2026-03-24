#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT_FILE="$ROOT/scripts/macos/bootstrap"
test -f "$SCRIPT_FILE"
grep -q '^source "\$SCRIPT_DIR/../../lib/shell/common.sh"$' "$SCRIPT_FILE"
grep -q '^require_macos$' "$SCRIPT_FILE"
python3 - "$SCRIPT_FILE" <<'PY'
from pathlib import Path
import sys

lines = Path(sys.argv[1]).read_text().splitlines()
expected = [
    '"$SCRIPT_DIR/brew-install"',
    '"$SCRIPT_DIR/brewfile-install"',
    '"$SCRIPT_DIR/iterm2-configure"',
    '"$SCRIPT_DIR/podman-machine-install"',
]

positions = []
for item in expected:
    positions.append(lines.index(item))

assert positions == sorted(positions)
PY
echo "Bootstrap checks passed"
