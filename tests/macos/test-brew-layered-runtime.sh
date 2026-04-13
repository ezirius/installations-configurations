#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMPDIR="$(mktemp -d)"
REPO_DIR="$TMPDIR/repo"
STATE_DIR="$TMPDIR/state"
MOCK_BIN="$TMPDIR/bin"
HOME_DIR="$TMPDIR/home"
BREW_PREFIX="$TMPDIR/homebrew"
mkdir -p "$REPO_DIR/scripts/macos" "$REPO_DIR/lib/shell" "$REPO_DIR/config/brew" "$STATE_DIR" "$MOCK_BIN" "$HOME_DIR/Documents/Ezirius/Systems/Installations and Configurations/Computers" "$BREW_PREFIX"
trap 'rm -rf "$TMPDIR"' EXIT

cp "$ROOT/scripts/macos/brew-install" "$REPO_DIR/scripts/macos/brew-install"
cp "$ROOT/lib/shell/common.sh" "$REPO_DIR/lib/shell/common.sh"
chmod +x "$REPO_DIR/scripts/macos/brew-install"

cat > "$REPO_DIR/config/brew/shared-macos.Brewfile" <<'EOF'
brew "caddy"
EOF
cat > "$REPO_DIR/config/brew/maldoria-macos.Brewfile" <<'EOF'
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
cat > "$MOCK_BIN/python3" <<'EOF'
#!/usr/bin/env bash
exec /usr/bin/python3 "$@"
EOF
cat > "$MOCK_BIN/brew" <<EOF
#!/usr/bin/env bash
set -euo pipefail
STATE_DIR="\${STATE_DIR:?}"
case "\$1" in
  shellenv) ;;
  --prefix) printf '%s\n' "$BREW_PREFIX" ;;
  list) exit 1 ;;
  bundle)
    printf '%s\n' "\$*" >> "\$STATE_DIR/brew.log"
    if [[ "\$2" == check ]]; then
      exit 1
    fi
    ;;
  *) exit 0 ;;
esac
EOF
chmod +x "$MOCK_BIN/uname" "$MOCK_BIN/scutil" "$MOCK_BIN/xcode-select" "$MOCK_BIN/python3" "$MOCK_BIN/brew"

PATH="$MOCK_BIN:$PATH" HOME="$HOME_DIR" STATE_DIR="$STATE_DIR" "$REPO_DIR/scripts/macos/brew-install" >/dev/null

grep -Fq -- 'bundle check --file=' "$STATE_DIR/brew.log"
grep -Fq -- 'shared-macos.Brewfile' "$STATE_DIR/brew.log"
grep -Fq -- 'maldoria-macos.Brewfile' "$STATE_DIR/brew.log"

echo "Brew layered runtime checks passed"
