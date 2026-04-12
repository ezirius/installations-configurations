#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT_FILE="$ROOT/scripts/macos/brewfile-install"
TMPDIR="$(mktemp -d)"
MOCK_BIN="$TMPDIR/bin"
HOME_DIR="$TMPDIR/home"
BREW_PREFIX="$TMPDIR/homebrew"
mkdir -p "$MOCK_BIN" "$HOME_DIR/Documents/Ezirius/Systems/Installations and Configurations/Computers" "$BREW_PREFIX"
trap 'rm -rf "$TMPDIR"' EXIT

assert_contains() {
  local file="$1" needle="$2" message="$3"
  if ! grep -Fq -- "$needle" "$file"; then
    printf 'assertion failed: %s\nmissing: %s\nfile: %s\n' "$message" "$needle" "$file" >&2
    exit 1
  fi
}

cat > "$MOCK_BIN/uname" <<'EOF'
#!/usr/bin/env bash
printf 'Darwin\n'
EOF
cat > "$MOCK_BIN/scutil" <<'EOF'
#!/usr/bin/env bash
printf 'Maldoria\n'
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
      if [[ -f "\$STATE_DIR/bundle-ok" ]]; then
        exit 0
      fi
      exit 1
    fi
    ;;
  *) exit 0 ;;
esac
EOF
chmod +x "$MOCK_BIN/uname" "$MOCK_BIN/scutil" "$MOCK_BIN/xcode-select" "$MOCK_BIN/python3" "$MOCK_BIN/brew"

BREWFILE="$TMPDIR/Brewfile"
cat > "$BREWFILE" <<'EOF'
brew "caddy"
cask "ghostty"
EOF

STATE_DIR="$TMPDIR/state-idempotent"
mkdir -p "$STATE_DIR"
touch "$STATE_DIR/bundle-ok"
PATH="$MOCK_BIN:$PATH" HOME="$HOME_DIR" STATE_DIR="$STATE_DIR" "$SCRIPT_FILE" "$BREWFILE" >/dev/null
if grep -Fq -- 'bundle install' "$STATE_DIR/brew.log" 2>/dev/null; then
  printf 'assertion failed: brewfile-install should not run brew bundle install when check succeeds\n' >&2
  exit 1
fi

STATE_DIR="$TMPDIR/state-install"
mkdir -p "$STATE_DIR"
PATH="$MOCK_BIN:$PATH" HOME="$HOME_DIR" STATE_DIR="$STATE_DIR" "$SCRIPT_FILE" "$BREWFILE" >/dev/null
assert_contains "$STATE_DIR/brew.log" 'bundle install --file=' 'brewfile-install applies the Brewfile when needed'

STATE_DIR="$TMPDIR/state-missing-brewfile"
mkdir -p "$STATE_DIR"
if PATH="$MOCK_BIN:$PATH" HOME="$HOME_DIR" STATE_DIR="$STATE_DIR" "$SCRIPT_FILE" "$TMPDIR/missing.Brewfile" >"$STATE_DIR/out" 2>"$STATE_DIR/err"; then
  printf 'assertion failed: brewfile-install should fail for a missing Brewfile\n' >&2
  exit 1
fi
assert_contains "$STATE_DIR/err" 'Brewfile not found' 'brewfile-install reports a missing Brewfile clearly'

echo "Brewfile runtime checks passed"
