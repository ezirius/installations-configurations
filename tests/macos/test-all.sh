#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

cd "$ROOT"

bash -n \
  scripts/macos/brew-install \
  scripts/macos/brewfile-install \
  scripts/macos/git-configure \
  scripts/macos/podman-check \
  scripts/macos/podman-machine-install \
  scripts/macos/iterm2-configure \
  scripts/macos/bootstrap \
  tests/macos/test-brewfile.sh \
  tests/macos/test-git-config.sh \
  tests/macos/test-iterm2-config.sh \
  tests/macos/test-bootstrap.sh \
  tests/macos/test-logging.sh \
  tests/macos/test-podman.sh \
  tests/macos/test-all.sh

"$ROOT/tests/macos/test-brewfile.sh"
"$ROOT/tests/macos/test-git-config.sh"
"$ROOT/tests/macos/test-iterm2-config.sh"
"$ROOT/tests/macos/test-bootstrap.sh"
"$ROOT/tests/macos/test-logging.sh"
"$ROOT/tests/macos/test-podman.sh"

echo "All macOS checks passed"
