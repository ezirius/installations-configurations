#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT_FILE="$ROOT/scripts/macos/git-configure"
EXPECTED_NAME=""
EXPECTED_EMAIL=""
TMPDIR="$(mktemp -d)"
MOCK_BIN="$TMPDIR/bin"
HOME_DIR="$TMPDIR/home"
REPO_DIR="$TMPDIR/openclaw-container"
SOCK_PATH="$TMPDIR/op.sock"
mkdir -p "$MOCK_BIN" "$HOME_DIR" "$REPO_DIR"

SERVER_PID=""
cleanup() {
  if [[ -n "$SERVER_PID" ]]; then
    kill "$SERVER_PID" >/dev/null 2>&1 || true
    wait "$SERVER_PID" 2>/dev/null || true
  fi
  rm -rf "$TMPDIR"
}
trap cleanup EXIT

if ! command -v git >/dev/null 2>&1; then
  echo "Git configure runtime checks passed (integration skipped: git not installed)"
  exit 0
fi

EXPECTED_NAME="$(git -C "$ROOT" config user.name || true)"
EXPECTED_EMAIL="$(git -C "$ROOT" config user.email || true)"

if [[ -z "$EXPECTED_NAME" || -z "$EXPECTED_EMAIL" ]]; then
  echo "Git configure runtime checks passed (integration skipped: repo git identity not set)"
  exit 0
fi

assert_contains() {
  local file="$1"
  local needle="$2"
  local message="$3"
  if ! grep -Fq -- "$needle" "$file"; then
    printf 'assertion failed: %s\nmissing: %s\nfile: %s\n' "$message" "$needle" "$file" >&2
    exit 1
  fi
}

assert_git_value() {
  local key="$1"
  local expected="$2"
  local actual
  actual="$(git -C "$REPO_DIR" config --get "$key" || true)"
  if [[ "$actual" != "$expected" ]]; then
    printf 'assertion failed: repo git config %s\nexpected: %s\nactual:   %s\n' "$key" "$expected" "$actual" >&2
    exit 1
  fi
}

assert_global_git_value() {
  local key="$1"
  local expected="$2"
  local actual
  actual="$(HOME="$HOME_DIR" git config --get "$key" || true)"
  if [[ "$actual" != "$expected" ]]; then
    printf 'assertion failed: global git config %s\nexpected: %s\nactual:   %s\n' "$key" "$expected" "$actual" >&2
    exit 1
  fi
}

cat > "$MOCK_BIN/uname" <<'EOF'
#!/usr/bin/env bash
printf 'Darwin\n'
EOF
chmod +x "$MOCK_BIN/uname"

python3 - <<'PY' "$SOCK_PATH" &
import os, socket, sys, time
path = sys.argv[1]
if os.path.exists(path):
    os.unlink(path)
sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
sock.bind(path)
sock.listen(1)
time.sleep(120)
PY
SERVER_PID=$!
sleep 1

git -C "$REPO_DIR" init -b main >/dev/null

mkdir -p "$HOME_DIR/.ssh"
cat > "$HOME_DIR/.ssh/config" <<'EOF'
Host github-maldoria-openclaw-container
  HostName github.example.invalid
EOF
if PATH="$MOCK_BIN:$PATH" \
  HOME="$HOME_DIR" \
  ONEPASSWORD_AGENT_SOCK="$SOCK_PATH" \
  GITHUB_SSH_CONFIG_PATH="$HOME_DIR/.ssh/config" \
  GIT_ALLOWED_SIGNERS_PATH="$HOME_DIR/.ssh/allowed_signers" \
  GIT_CONFIG_HOST="maldoria" \
  GIT_CONFIG_REPO="openclaw-container" \
  GIT_CONFIG_REPO_ROOT="$REPO_DIR" \
  "$SCRIPT_FILE" >"$TMPDIR/conflict.out" 2>"$TMPDIR/conflict.err"; then
  printf 'assertion failed: git-configure should refuse a conflicting unmanaged SSH alias\n' >&2
  exit 1
fi
assert_contains "$TMPDIR/conflict.err" 'A custom Host github-maldoria-openclaw-container entry already exists' 'git-configure refuses conflicting unmanaged SSH aliases'
rm -f "$HOME_DIR/.ssh/config"

PATH="$MOCK_BIN:$PATH" \
HOME="$HOME_DIR" \
ONEPASSWORD_AGENT_SOCK="$SOCK_PATH" \
GITHUB_SSH_CONFIG_PATH="$HOME_DIR/.ssh/config" \
GIT_ALLOWED_SIGNERS_PATH="$HOME_DIR/.ssh/allowed_signers" \
GIT_CONFIG_HOST="maldoria" \
GIT_CONFIG_REPO="openclaw-container" \
GIT_CONFIG_REPO_ROOT="$REPO_DIR" \
"$SCRIPT_FILE" >/dev/null

assert_contains "$HOME_DIR/.ssh/config" 'Host github-maldoria-openclaw-container' 'ssh alias is written'
assert_contains "$HOME_DIR/.ssh/config" 'IdentityAgent' 'ssh config uses 1Password agent'
assert_contains "$HOME_DIR/.ssh/config" 'maldoria-github-ezirius-openclaw-container.pub' 'ssh config points at repo key'
assert_contains "$HOME_DIR/.ssh/allowed_signers" "$EXPECTED_EMAIL" 'allowed signers file is written'

test -f "$HOME_DIR/.ssh/maldoria-github-ezirius-openclaw-container.pub"
test -f "$HOME_DIR/.ssh/maldoria-github-ezirius-sign.pub"

assert_git_value remote.origin.url 'git@github-maldoria-openclaw-container:ezirius/openclaw-container.git'
assert_global_git_value user.name "$EXPECTED_NAME"
assert_global_git_value user.email "$EXPECTED_EMAIL"
assert_global_git_value include.path "$HOME_DIR/.config/git/installations-configurations.conf"
assert_contains "$HOME_DIR/.config/git/installations-configurations.conf" '[core]' 'managed git include is written'
assert_contains "$HOME_DIR/.config/git/installations-configurations.conf" 'editor = micro' 'managed git include sets the editor'
assert_contains "$HOME_DIR/.config/git/installations-configurations.conf" 'pager = delta' 'managed git include sets delta as pager'

HOME="$HOME_DIR" git config --global color.ui always
PATH="$MOCK_BIN:$PATH" \
HOME="$HOME_DIR" \
ONEPASSWORD_AGENT_SOCK="$SOCK_PATH" \
GITHUB_SSH_CONFIG_PATH="$HOME_DIR/.ssh/config" \
GIT_ALLOWED_SIGNERS_PATH="$HOME_DIR/.ssh/allowed_signers" \
GIT_CONFIG_HOST="maldoria" \
GIT_CONFIG_REPO="openclaw-container" \
GIT_CONFIG_REPO_ROOT="$REPO_DIR" \
"$SCRIPT_FILE" >/dev/null
assert_global_git_value color.ui always

git -C "$REPO_DIR" remote set-url origin git@gitlab.com:ezirius/openclaw-container.git
if PATH="$MOCK_BIN:$PATH" \
  HOME="$HOME_DIR" \
  ONEPASSWORD_AGENT_SOCK="$SOCK_PATH" \
  GITHUB_SSH_CONFIG_PATH="$HOME_DIR/.ssh/config" \
  GIT_ALLOWED_SIGNERS_PATH="$HOME_DIR/.ssh/allowed_signers" \
  GIT_CONFIG_HOST="maldoria" \
  GIT_CONFIG_REPO="openclaw-container" \
  GIT_CONFIG_REPO_ROOT="$REPO_DIR" \
  "$SCRIPT_FILE" >"$TMPDIR/out" 2>"$TMPDIR/err"; then
  printf 'assertion failed: git-configure should refuse unexpected remote hosts\n' >&2
  exit 1
fi
assert_contains "$TMPDIR/err" 'not the expected managed host' 'git-configure refuses unexpected remote hosts'

git -C "$REPO_DIR" remote set-url origin git@github.com:someone-else/openclaw-container.git
if PATH="$MOCK_BIN:$PATH" \
  HOME="$HOME_DIR" \
  ONEPASSWORD_AGENT_SOCK="$SOCK_PATH" \
  GITHUB_SSH_CONFIG_PATH="$HOME_DIR/.ssh/config" \
  GIT_ALLOWED_SIGNERS_PATH="$HOME_DIR/.ssh/allowed_signers" \
  GIT_CONFIG_HOST="maldoria" \
  GIT_CONFIG_REPO="openclaw-container" \
  GIT_CONFIG_REPO_ROOT="$REPO_DIR" \
  "$SCRIPT_FILE" >"$TMPDIR/out2" 2>"$TMPDIR/err2"; then
  printf 'assertion failed: git-configure should refuse unexpected remote paths\n' >&2
  exit 1
fi
assert_contains "$TMPDIR/err2" 'does not match expected' 'git-configure refuses unexpected remote paths'

git -C "$REPO_DIR" remote set-url origin 'git@github-maldoria-openclaw-container:ezirius/openclaw-container.git'

PATH="$MOCK_BIN:$PATH" \
HOME="$HOME_DIR" \
ONEPASSWORD_AGENT_SOCK="$SOCK_PATH" \
GITHUB_SSH_CONFIG_PATH="$HOME_DIR/.ssh/config" \
GIT_ALLOWED_SIGNERS_PATH="$HOME_DIR/.ssh/allowed_signers" \
GIT_CONFIG_HOST="maldoria" \
GIT_CONFIG_REPO="openclaw-container" \
GIT_CONFIG_REPO_ROOT="$REPO_DIR" \
"$SCRIPT_FILE" >/dev/null

assert_git_value remote.origin.url 'git@github-maldoria-openclaw-container:ezirius/openclaw-container.git'

echo "Git configure runtime checks passed"
