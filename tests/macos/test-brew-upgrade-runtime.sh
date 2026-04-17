#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HELPERS="$ROOT/lib/test/runtime-helpers.sh"
TMPDIR="$(mktemp -d)"
REPO_DIR="$TMPDIR/repo"
MOCK_BIN="$TMPDIR/bin"
HOME_DIR="$TMPDIR/home"
BREW_PREFIX="$TMPDIR/homebrew"
SCRIPT_FILE="$REPO_DIR/scripts/macos/brew-upgrade"
HOST_PYTHON3="$(command -v python3)"
mkdir -p "$MOCK_BIN" "$HOME_DIR/Documents/Ezirius/Systems/Installations and Configurations/Computers" "$BREW_PREFIX" "$REPO_DIR/scripts/macos" "$REPO_DIR/lib/shell" "$REPO_DIR/config/brew" "$REPO_DIR/config/repo" "$REPO_DIR/config/podman"
trap 'rm -rf "$TMPDIR"' EXIT
source "$HELPERS"

cp "$ROOT/scripts/macos/brew-upgrade" "$REPO_DIR/scripts/macos/brew-upgrade"
cp "$ROOT/lib/shell/common.sh" "$REPO_DIR/lib/shell/common.sh"
cp "$ROOT/config/brew/shared-macos.Brewfile" "$REPO_DIR/config/brew/shared-macos.Brewfile"
cp "$ROOT/config/repo/shared.conf" "$REPO_DIR/config/repo/shared.conf"
cp "$ROOT/config/podman/shared-macos.conf" "$REPO_DIR/config/podman/shared-macos.conf"
chmod +x "$SCRIPT_FILE"

cat > "$REPO_DIR/config/brew/shared-macos.Brewfile" <<'EOF'
brew 'caddy'
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
printf 'Maldoria\n'
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
  update)
    printf 'update\n' >> "\$STATE_DIR/brew.log"
    if [[ -f "\$STATE_DIR/up-to-date" ]]; then
      printf 'Already up-to-date.\n'
    else
      printf 'Updated 1 tap (homebrew/core).\n'
    fi
    ;;
  outdated)
    if [[ "\$2" == --formula && -f "\$STATE_DIR/outdated-formula-\$3" ]]; then
      printf '%s\n' "\$3"
    elif [[ "\$2" == --cask && -f "\$STATE_DIR/outdated-cask-\$3" ]]; then
      printf '%s\n' "\$3"
    fi
    ;;
  upgrade)
    printf '%s\n' "\$*" >> "\$STATE_DIR/brew.log"
    ;;
  *) exit 0 ;;
esac
EOF
chmod +x "$MOCK_BIN/uname" "$MOCK_BIN/scutil" "$MOCK_BIN/xcode-select" "$MOCK_BIN/python3" "$MOCK_BIN/brew"

BREWFILE="$TMPDIR/Brewfile"
cat > "$BREWFILE" <<'EOF'
brew 'caddy'
cask "ghostty"
EOF

STATE_DIR="$TMPDIR/state-dirty-repo"
mkdir -p "$STATE_DIR"
touch "$REPO_DIR/dirty.txt"
if PATH="$MOCK_BIN:$PATH" HOME="$HOME_DIR" STATE_DIR="$STATE_DIR" "$SCRIPT_FILE" "$BREWFILE" >"$STATE_DIR/out" 2>"$STATE_DIR/err"; then
  printf 'assertion failed: brew-upgrade should fail when the repository has uncommitted changes\n' >&2
  exit 1
fi
assert_contains "$STATE_DIR/err" 'Repository has uncommitted changes. Commit and push before running brew-upgrade.' 'brew-upgrade reports dirty working trees through the safety gate'
rm -f "$REPO_DIR/dirty.txt"

STATE_DIR="$TMPDIR/state-no-upstream"
mkdir -p "$STATE_DIR"
git -C "$REPO_DIR" checkout -b local-only >/dev/null
if PATH="$MOCK_BIN:$PATH" HOME="$HOME_DIR" STATE_DIR="$STATE_DIR" "$SCRIPT_FILE" "$BREWFILE" >"$STATE_DIR/out" 2>"$STATE_DIR/err"; then
  printf 'assertion failed: brew-upgrade should fail when the current branch has no upstream\n' >&2
  exit 1
fi
assert_contains "$STATE_DIR/err" 'Current branch has no upstream. Push the branch before running brew-upgrade.' 'brew-upgrade reports missing upstream branches through the safety gate'
git -C "$REPO_DIR" checkout main >/dev/null

STATE_DIR="$TMPDIR/state-ahead-of-upstream"
mkdir -p "$STATE_DIR"
git -C "$REPO_DIR" checkout -b ahead origin/main >/dev/null
touch "$REPO_DIR/ahead.txt"
git -C "$REPO_DIR" add ahead.txt >/dev/null
git -C "$REPO_DIR" commit -m 'Ahead-only runtime test' >/dev/null
if PATH="$MOCK_BIN:$PATH" HOME="$HOME_DIR" STATE_DIR="$STATE_DIR" "$SCRIPT_FILE" "$BREWFILE" >"$STATE_DIR/out" 2>"$STATE_DIR/err"; then
  printf 'assertion failed: brew-upgrade should fail when the current branch has unpushed commits\n' >&2
  exit 1
fi
assert_contains "$STATE_DIR/err" 'Current branch has unpushed commits. Push before running brew-upgrade.' 'brew-upgrade reports branches ahead of upstream through the safety gate'
git -C "$REPO_DIR" checkout main >/dev/null

STATE_DIR="$TMPDIR/state-updated"
mkdir -p "$STATE_DIR"
touch "$STATE_DIR/installed-formula-caddy" "$STATE_DIR/installed-cask-ghostty" "$STATE_DIR/outdated-formula-caddy" "$STATE_DIR/outdated-cask-ghostty"
PATH="$MOCK_BIN:$PATH" HOME="$HOME_DIR" STATE_DIR="$STATE_DIR" "$SCRIPT_FILE" "$BREWFILE" >/dev/null
assert_contains "$STATE_DIR/brew.log" 'update' 'brew-upgrade runs brew update before explicit Brewfile upgrades'
assert_contains "$STATE_DIR/brew.log" 'upgrade caddy' 'brew-upgrade upgrades outdated formulae'
assert_contains "$STATE_DIR/brew.log" 'upgrade --cask ghostty' 'brew-upgrade upgrades outdated casks'

STATE_DIR="$TMPDIR/state-default-shared"
mkdir -p "$STATE_DIR"
touch "$STATE_DIR/installed-formula-caddy" "$STATE_DIR/installed-cask-ghostty" "$STATE_DIR/outdated-formula-caddy" "$STATE_DIR/outdated-cask-ghostty"
PATH="$MOCK_BIN:$PATH" HOME="$HOME_DIR" STATE_DIR="$STATE_DIR" "$SCRIPT_FILE" >"$STATE_DIR/out"
assert_contains "$STATE_DIR/out" "Checking Brewfile: $REPO_DIR/config/brew/shared-macos.Brewfile" 'brew-upgrade processes the shared Brewfile by default'
assert_not_contains "$STATE_DIR/out" "Checking Brewfile: $REPO_DIR/config/brew/maldoria-macos.Brewfile" 'brew-upgrade does not report a host-specific Brewfile when none is present'

mapfile -t default_shared_log < "$STATE_DIR/brew.log"
if [[ "${default_shared_log[0]-}" != 'update' ]]; then
  printf 'assertion failed: brew-upgrade should run brew update before processing default shared entries\n' >&2
  exit 1
fi
assert_contains "$STATE_DIR/brew.log" 'upgrade caddy' 'brew-upgrade upgrades outdated shared formulae in default mode'
assert_contains "$STATE_DIR/brew.log" 'upgrade --cask ghostty' 'brew-upgrade upgrades outdated shared casks in default mode'

HOST_BREWFILE="$REPO_DIR/config/brew/maldoria-macos.Brewfile"
cat > "$HOST_BREWFILE" <<'EOF'
brew "podman"
EOF
git -C "$REPO_DIR" add config/brew/maldoria-macos.Brewfile >/dev/null
git -C "$REPO_DIR" commit -m 'Add host brewfile for runtime test' >/dev/null
git -C "$REPO_DIR" push >/dev/null 2>&1
STATE_DIR="$TMPDIR/state-layered"
mkdir -p "$STATE_DIR"
touch "$STATE_DIR/installed-formula-caddy" "$STATE_DIR/installed-formula-podman" "$STATE_DIR/outdated-formula-caddy" "$STATE_DIR/outdated-formula-podman"
PATH="$MOCK_BIN:$PATH" HOME="$HOME_DIR" STATE_DIR="$STATE_DIR" "$SCRIPT_FILE" >"$STATE_DIR/out"
assert_contains "$STATE_DIR/out" "Checking Brewfile: $REPO_DIR/config/brew/shared-macos.Brewfile" 'brew-upgrade still processes the shared Brewfile when a host-specific Brewfile exists'
assert_contains "$STATE_DIR/out" "Checking Brewfile: $REPO_DIR/config/brew/maldoria-macos.Brewfile" 'brew-upgrade processes the host-specific Brewfile when present'

mapfile -t layered_log < "$STATE_DIR/brew.log"
if [[ "${layered_log[0]-}" != 'update' ]]; then
  printf 'assertion failed: brew-upgrade should run brew update before shared and host-specific upgrades\n' >&2
  exit 1
fi
assert_contains "$STATE_DIR/brew.log" 'upgrade caddy' 'brew-upgrade still upgrades shared Brewfile entries in default mode'
assert_contains "$STATE_DIR/brew.log" 'upgrade podman' 'brew-upgrade also upgrades host-specific Brewfile entries in default mode'

STATE_DIR="$TMPDIR/state-missing"
mkdir -p "$STATE_DIR"
PATH="$MOCK_BIN:$PATH" HOME="$HOME_DIR" STATE_DIR="$STATE_DIR" "$SCRIPT_FILE" "$BREWFILE" >/dev/null
assert_not_contains "$STATE_DIR/brew.log" 'install ' 'brew-upgrade does not install missing entries'
assert_not_contains "$STATE_DIR/brew.log" 'upgrade ' 'brew-upgrade does not upgrade missing entries'
mapfile -t missing_log < "$STATE_DIR/brew.log"
if [[ "${#missing_log[@]}" -ne 1 || "${missing_log[0]}" != 'update' ]]; then
  printf 'assertion failed: brew-upgrade should only run brew update when Brewfile entries are missing\n' >&2
  exit 1
fi

STATE_DIR="$TMPDIR/state-up-to-date"
mkdir -p "$STATE_DIR"
touch "$STATE_DIR/installed-formula-caddy" "$STATE_DIR/installed-cask-ghostty" "$STATE_DIR/up-to-date"
PATH="$MOCK_BIN:$PATH" HOME="$HOME_DIR" STATE_DIR="$STATE_DIR" "$SCRIPT_FILE" "$BREWFILE" >/dev/null
assert_not_contains "$STATE_DIR/brew.log" 'install ' 'brew-upgrade does not install current entries during upgrade runs'
assert_not_contains "$STATE_DIR/brew.log" 'upgrade ' 'brew-upgrade does not upgrade current entries'
mapfile -t up_to_date_log < "$STATE_DIR/brew.log"
if [[ "${#up_to_date_log[@]}" -ne 1 || "${up_to_date_log[0]}" != 'update' ]]; then
  printf 'assertion failed: brew-upgrade should only run brew update when Brewfile entries are already current\n' >&2
  exit 1
fi

echo "Brew upgrade runtime checks passed"
