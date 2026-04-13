#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BREWFILE="$ROOT/config/brew/shared-macos.Brewfile"
test -f "$BREWFILE"
grep -q 'brew "age"' "$BREWFILE"
grep -q 'brew "atuin"' "$BREWFILE"
grep -q 'brew "basedpyright"' "$BREWFILE"
grep -q 'brew "bat"' "$BREWFILE"
grep -q 'brew "btop"' "$BREWFILE"
grep -q 'brew "coreutils"' "$BREWFILE"
grep -q 'brew "direnv"' "$BREWFILE"
grep -q 'brew "dua-cli"' "$BREWFILE"
grep -q 'brew "eza"' "$BREWFILE"
grep -q 'brew "fd"' "$BREWFILE"
grep -q 'brew "fzf"' "$BREWFILE"
grep -q 'brew "git"' "$BREWFILE"
grep -q 'brew "git-delta"' "$BREWFILE"
grep -q 'brew "ipython"' "$BREWFILE"
grep -q 'brew "jj"' "$BREWFILE"
grep -q 'brew "jq"' "$BREWFILE"
grep -q 'brew "just"' "$BREWFILE"
grep -q 'brew "make"' "$BREWFILE"
grep -q 'brew "micro"' "$BREWFILE"
grep -q 'brew "nushell"' "$BREWFILE"
grep -q 'brew "openssl"' "$BREWFILE"
grep -q 'brew "podman"' "$BREWFILE"
grep -q 'brew "podman-compose"' "$BREWFILE"
grep -q 'brew "pytest"' "$BREWFILE"
grep -q 'brew "python"' "$BREWFILE"
grep -q 'brew "ripgrep"' "$BREWFILE"
grep -q 'brew "rsync"' "$BREWFILE"
grep -q 'brew "ruff"' "$BREWFILE"
grep -q 'brew "starship"' "$BREWFILE"
grep -q 'brew "tlrc"' "$BREWFILE"
grep -q 'brew "uv"' "$BREWFILE"
grep -q 'brew "vivid"' "$BREWFILE"
grep -q 'brew "vim"' "$BREWFILE"
grep -q 'brew "wget"' "$BREWFILE"
grep -q 'brew "worktrunk"' "$BREWFILE"
grep -q 'brew "yq"' "$BREWFILE"
grep -q 'brew "zellij"' "$BREWFILE"
grep -q 'cask "ghostty"' "$BREWFILE"
grep -q 'brew "zoxide"' "$BREWFILE"
grep -q '^  process_brewfile "\$(shared_platform_config_path "config/brew" "Brewfile")"$' "$ROOT/scripts/macos/brew-install"
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
