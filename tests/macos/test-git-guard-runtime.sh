#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMPDIR="$(mktemp -d)"
REPO_DIR="$TMPDIR/repo"
MOCK_BIN="$TMPDIR/bin"
STATE_DIR="$TMPDIR/state"
mkdir -p "$REPO_DIR/scripts/macos" "$REPO_DIR/lib/shell" "$REPO_DIR/config/brew" "$MOCK_BIN" "$STATE_DIR"
trap 'rm -rf "$TMPDIR"' EXIT

assert_contains() {
  local file="$1" needle="$2" message="$3"
  if ! grep -Fq -- "$needle" "$file"; then
    printf 'assertion failed: %s\nmissing: %s\nfile: %s\n' "$message" "$needle" "$file" >&2
    exit 1
  fi
}

cp "$ROOT/scripts/macos/brew-install" "$REPO_DIR/scripts/macos/brew-install"
cp "$ROOT/scripts/macos/brew-upgrade" "$REPO_DIR/scripts/macos/brew-upgrade"
cp "$ROOT/lib/shell/common.sh" "$REPO_DIR/lib/shell/common.sh"
cat > "$REPO_DIR/config/brew/shared-macos.Brewfile" <<'EOF'
brew "caddy"
EOF
cat > "$REPO_DIR/README.md" <<'EOF'
test repo
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
cat > "$MOCK_BIN/brew" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  shellenv) ;;
  --prefix) printf '/opt/homebrew\n' ;;
  --version) printf 'Homebrew 5.0.0\n' ;;
  bundle|update|outdated|upgrade|list) exit 0 ;;
  *) exit 0 ;;
esac
EOF
chmod +x "$MOCK_BIN/uname" "$MOCK_BIN/scutil" "$MOCK_BIN/xcode-select" "$MOCK_BIN/python3" "$MOCK_BIN/brew"

echo 'dirty' > "$REPO_DIR/dirty.txt"
if PATH="$MOCK_BIN:$PATH" "$REPO_DIR/scripts/macos/brew-install" >"$STATE_DIR/out1" 2>"$STATE_DIR/err1"; then
  printf 'assertion failed: brew-install should fail on uncommitted changes\n' >&2
  exit 1
fi
assert_contains "$STATE_DIR/err1" 'Repository has uncommitted changes' 'brew-install reports dirty working tree clearly'
rm "$REPO_DIR/dirty.txt"

echo 'ahead' >> "$REPO_DIR/README.md"
git -C "$REPO_DIR" add README.md >/dev/null
git -C "$REPO_DIR" commit -m 'Ahead' >/dev/null
if PATH="$MOCK_BIN:$PATH" "$REPO_DIR/scripts/macos/brew-upgrade" >"$STATE_DIR/out2" 2>"$STATE_DIR/err2"; then
  printf 'assertion failed: brew-upgrade should fail on unpushed commits\n' >&2
  exit 1
fi
assert_contains "$STATE_DIR/err2" 'Current branch has unpushed commits' 'brew-upgrade reports unpushed commits clearly'

git -C "$REPO_DIR" reset --soft HEAD~1 >/dev/null
git -C "$REPO_DIR" restore --staged README.md >/dev/null
git -C "$REPO_DIR" restore README.md >/dev/null
git -C "$REPO_DIR" branch --unset-upstream
if PATH="$MOCK_BIN:$PATH" "$REPO_DIR/scripts/macos/brew-install" >"$STATE_DIR/out3" 2>"$STATE_DIR/err3"; then
  printf 'assertion failed: brew-install should fail when there is no upstream\n' >&2
  exit 1
fi
assert_contains "$STATE_DIR/err3" 'Current branch has no upstream' 'brew-install reports a missing upstream clearly'

echo "Git guard runtime checks passed"
