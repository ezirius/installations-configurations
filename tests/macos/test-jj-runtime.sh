#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT_FILE="$ROOT/scripts/macos/jj-configure"
TMPDIR="$(mktemp -d)"
MOCK_BIN="$TMPDIR/bin"
HOME_DIR="$TMPDIR/home"
mkdir -p "$MOCK_BIN" "$HOME_DIR/Documents/Ezirius/Systems/Installations and Configurations/Computers" "$HOME_DIR/.config"
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

cat > "$MOCK_BIN/brew" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  shellenv) ;;
  --prefix) printf '/opt/homebrew\n' ;;
  *) exit 0 ;;
esac
EOF

cat > "$MOCK_BIN/jj" <<'EOF'
#!/usr/bin/env bash
printf 'jj mock\n' >/dev/null
EOF

cat > "$MOCK_BIN/git" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == -C ]]; then
  shift 2
fi

case "$1 $2" in
  'rev-parse --show-toplevel')
    printf '/workspace/opencode-development/installations-configurations\n'
    ;;
  'config user.name')
    printf 'Repo User\n'
    ;;
  'config user.email')
    printf 'repo.user@example.invalid\n'
    ;;
  *)
    exit 1
    ;;
esac
EOF
chmod +x "$MOCK_BIN/uname" "$MOCK_BIN/scutil" "$MOCK_BIN/xcode-select" "$MOCK_BIN/brew" "$MOCK_BIN/jj" "$MOCK_BIN/git"

PATH="$MOCK_BIN:$PATH" HOME="$HOME_DIR" XDG_CONFIG_HOME="$HOME_DIR/.config" "$SCRIPT_FILE" >/dev/null

TARGET_CONFIG="$HOME_DIR/.config/jj/config.toml"
assert_contains "$TARGET_CONFIG" 'name = "Repo User"' 'jj user name is rendered from repo git config'
assert_contains "$TARGET_CONFIG" 'email = "repo.user@example.invalid"' 'jj user email is rendered from repo git config'
LOG_FILE="$HOME_DIR/Documents/Ezirius/Systems/Installations and Configurations/Computers/Maldoria Installations and Configurations-$(date '+%Y%m%d')---------.csv"
assert_contains "$LOG_FILE" 'jj config' 'jj config deployment is logged'

cat > "$MOCK_BIN/git" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == -C ]]; then
  shift 2
fi

case "$1 $2" in
  'rev-parse --show-toplevel')
    printf '/workspace/opencode-development/installations-configurations\n'
    ;;
  'config user.name'|'config user.email')
    exit 0
    ;;
  *)
    exit 1
    ;;
esac
EOF
chmod +x "$MOCK_BIN/git"
if PATH="$MOCK_BIN:$PATH" HOME="$HOME_DIR" XDG_CONFIG_HOME="$HOME_DIR/.config" "$SCRIPT_FILE" >"$TMPDIR/out" 2>"$TMPDIR/err"; then
  printf 'assertion failed: jj-configure should fail when repo git identity is missing\n' >&2
  exit 1
fi
assert_contains "$TMPDIR/err" 'Git user.name is not set for this repository' 'jj-configure reports missing repo git identity clearly'

echo "jj runtime checks passed"
