#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT_FILE="$ROOT/scripts/macos/git-configure"
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
  actual="$(HOME="$HOME_DIR" git config --global --get "$key" || true)"
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
assert_contains "$HOME_DIR/.ssh/allowed_signers" '66864416+ezirius@users.noreply.github.com' 'allowed signers file is written'

test -f "$HOME_DIR/.ssh/maldoria-github-ezirius-openclaw-container.pub"
test -f "$HOME_DIR/.ssh/maldoria-github-ezirius-sign.pub"

assert_git_value remote.origin.url 'git@github-maldoria-openclaw-container:ezirius/openclaw-container.git'
assert_global_git_value user.name 'Ezirius'
assert_global_git_value user.email '66864416+ezirius@users.noreply.github.com'

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
