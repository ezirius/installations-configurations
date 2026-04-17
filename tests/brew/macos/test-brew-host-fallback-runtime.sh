#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
TMPDIR="$(mktemp -d)"
REPO_DIR="$TMPDIR/repo"
STATE_DIR="$TMPDIR/state"
MOCK_BIN="$TMPDIR/bin"
HOME_DIR="$TMPDIR/home"
BREW_PREFIX="$TMPDIR/homebrew"
HOST_PYTHON3="$(command -v python3)"
mkdir -p "$REPO_DIR/scripts/brew/macos" "$REPO_DIR/lib/shell" "$REPO_DIR/lib/shell/shared" "$REPO_DIR/config/brew/macos" "$REPO_DIR/config/repo/shared" "$REPO_DIR/config/podman/macos" "$STATE_DIR" "$MOCK_BIN" "$HOME_DIR/Documents/Ezirius/Systems/Installations and Configurations/Computers" "$BREW_PREFIX"
trap 'rm -rf "$TMPDIR"' EXIT

cp "$ROOT/scripts/brew/macos/brew-install" "$REPO_DIR/scripts/brew/macos/brew-install"
cp "$ROOT/lib/shell/shared/common.sh" "$REPO_DIR/lib/shell/shared/common.sh"
cp "$ROOT/lib/shell/shared/homebrew.sh" "$REPO_DIR/lib/shell/shared/homebrew.sh"
cp "$ROOT/config/brew/macos/brew-settings-shared.conf" "$REPO_DIR/config/brew/macos/brew-settings-shared.conf"
cp "$ROOT/config/repo/shared/repo-settings-shared.conf" "$REPO_DIR/config/repo/shared/repo-settings-shared.conf"
cp "$ROOT/config/podman/macos/podman-runtime-settings-shared.conf" "$REPO_DIR/config/podman/macos/podman-runtime-settings-shared.conf"
chmod +x "$REPO_DIR/scripts/brew/macos/brew-install"

cat > "$REPO_DIR/config/brew/macos/brew-packages-shared.Brewfile" <<'EOF'
brew "caddy"
EOF
cat > "$REPO_DIR/config/brew/macos/brew-packages-maldoria.Brewfile" <<'EOF'
cask "ghostty"
EOF

git -C "$REPO_DIR" init -b main >/dev/null
git -C "$REPO_DIR" config user.name 'Repo User'
git -C "$REPO_DIR" config user.email 'repo.user@example.invalid'
git -C "$REPO_DIR" add . >/dev/null
git -C "$REPO_DIR" commit -m 'Initial' >/dev/null
git -C "$REPO_DIR" init --bare "$TMPDIR/remote.git" >/dev/null
git -C "$REPO_DIR" remote add origin "$TMPDIR/remote.git"
git -C "$REPO_DIR" push -u origin main >/dev/null 2>&1

cat > "$MOCK_BIN/uname" <<'EOF'
#!/usr/bin/env bash
printf 'Darwin\n'
EOF
cat > "$MOCK_BIN/scutil" <<'EOF'
#!/usr/bin/env bash
printf 'Maldoria.local\n'
EOF
cat > "$MOCK_BIN/xcode-select" <<'EOF'
#!/usr/bin/env bash
[[ "$1" == -p ]]
printf '/Library/Developer/CommandLineTools\n'
EOF
cat > "$MOCK_BIN/python3" <<EOF
#!/usr/bin/env bash
exec "$HOST_PYTHON3" "\$@"
EOF
cat > "$MOCK_BIN/brew" <<EOF
#!/usr/bin/env bash
set -euo pipefail
STATE_DIR="\${STATE_DIR:?}"
case "\$1" in
  shellenv) ;;
  --prefix) printf '%s\n' "$BREW_PREFIX" ;;
  list)
    if [[ "\$2" == --versions ]]; then
      [[ -f "\$STATE_DIR/installed-formula-\$3" ]] && printf '%s 1.0.0\n' "\$3" || exit 1
    elif [[ "\$2" == --cask && "\$3" == --versions ]]; then
      [[ -f "\$STATE_DIR/installed-cask-\$4" ]] && printf '%s 1.0.0\n' "\$4" || exit 1
    fi
    ;;
  install)
    printf '%s\n' "\$*" >> "\$STATE_DIR/brew.log"
    if [[ "\$2" == --cask ]]; then
      : > "\$STATE_DIR/installed-cask-\$3"
    else
      : > "\$STATE_DIR/installed-formula-\$2"
    fi
    ;;
  *) exit 0 ;;
esac
EOF
chmod +x "$MOCK_BIN/uname" "$MOCK_BIN/scutil" "$MOCK_BIN/xcode-select" "$MOCK_BIN/python3" "$MOCK_BIN/brew"

PATH="$MOCK_BIN:$PATH" HOME="$HOME_DIR" STATE_DIR="$STATE_DIR" "$REPO_DIR/scripts/brew/macos/brew-install" >"$STATE_DIR/out"

if grep -Fq -- 'install caddy' "$STATE_DIR/brew.log"; then
  printf 'assertion failed: brew-install should not process the shared Brewfile when a host-specific Brewfile exists\n' >&2
  exit 1
fi
grep -Fq -- 'install --cask ghostty' "$STATE_DIR/brew.log"

if grep -Fq -- "Checking Brewfile: $REPO_DIR/config/brew/macos/brew-packages-shared.Brewfile" "$STATE_DIR/out"; then
  printf 'assertion failed: brew-install should not report the shared Brewfile when a host-specific Brewfile exists\n' >&2
  exit 1
fi

grep -Fq -- "Checking Brewfile: $REPO_DIR/config/brew/macos/brew-packages-maldoria.Brewfile" "$STATE_DIR/out"

if grep -Fq -- 'upgrade ' "$STATE_DIR/brew.log"; then
  printf 'assertion failed: brew-install should not upgrade entries while processing host-fallback Brewfiles\n' >&2
  exit 1
fi

echo "Brew host fallback runtime checks passed"
