#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
BREWFILE="$ROOT/config/brew/macos/brew-packages-shared.Brewfile"
test -f "$BREWFILE"
grep -q 'brew "podman"' "$BREWFILE"
grep -q 'brew "podman-compose"' "$BREWFILE"
grep -q 'cask "podman-desktop"' "$BREWFILE"
python3 - "$BREWFILE" <<'PY'
from pathlib import Path
import sys

brews = []
casks = []
for line in Path(sys.argv[1]).read_text().splitlines():
    if line.startswith('brew '):
        brews.append(line)
    elif line.startswith('cask '):
        casks.append(line)

assert brews == sorted(brews)
assert casks == sorted(casks)
assert max(Path(sys.argv[1]).read_text().splitlines().index(line) for line in brews) < min(Path(sys.argv[1]).read_text().splitlines().index(line) for line in casks)
PY
echo "Brewfile checks passed"
