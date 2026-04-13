#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

cd "$ROOT"

bash -n \
  scripts/macos/brew-install \
  scripts/macos/brew-upgrade \
  scripts/macos/brew-configure \
  scripts/macos/brew-service \
  scripts/macos/caddy-configure \
  scripts/macos/caddy-service \
  scripts/macos/caddy-trust \
  scripts/macos/git-configure \
  scripts/macos/ghostty-configure \
  scripts/macos/devtools-configure \
  scripts/macos/jj-configure \
  scripts/macos/nushell-configure \
  scripts/macos/system-configure \
  scripts/macos/podman-check \
  scripts/macos/podman-configure \
  scripts/macos/brew-bootstrap \
  tests/macos/test-brewfile.sh \
  tests/macos/test-brew-install.sh \
  tests/macos/test-brew-install-runtime.sh \
  tests/macos/test-brew-configure.sh \
  tests/macos/test-brew-service.sh \
  tests/macos/test-brewfile-runtime.sh \
  tests/macos/test-brew-layered-runtime.sh \
  tests/macos/test-brew-upgrade.sh \
  tests/macos/test-brew-upgrade-runtime.sh \
  tests/macos/test-caddy-config.sh \
  tests/macos/test-caddy-runtime.sh \
  tests/macos/test-caddy-layered-runtime.sh \
  tests/macos/test-caddy-service.sh \
  tests/macos/test-caddy-service-runtime.sh \
  tests/macos/test-caddy-trust.sh \
  tests/macos/test-caddy-trust-runtime.sh \
  tests/macos/test-common.sh \
  tests/macos/test-devtools-config.sh \
  tests/macos/test-devtools-runtime.sh \
  tests/macos/test-docs.sh \
  tests/macos/test-args.sh \
  tests/macos/test-git-config.sh \
  tests/macos/test-git-config-runtime.sh \
  tests/macos/test-repo-remotes.sh \
  tests/macos/test-ghostty-config.sh \
  tests/macos/test-ghostty-runtime.sh \
  tests/macos/test-jj-config.sh \
  tests/macos/test-jj-runtime.sh \
  tests/macos/test-nushell-config.sh \
  tests/macos/test-nushell-runtime.sh \
  tests/macos/test-system-config.sh \
  tests/macos/test-system-runtime.sh \
  tests/macos/test-brew-bootstrap.sh \
  tests/macos/test-brew-bootstrap-runtime.sh \
  tests/macos/test-brew-bootstrap-fail-fast-runtime.sh \
  tests/macos/test-logging.sh \
  tests/macos/test-podman.sh \
  tests/macos/test-podman-machine-runtime.sh \
  tests/macos/test-all.sh

"$ROOT/tests/macos/test-brewfile.sh"
"$ROOT/tests/macos/test-brew-install.sh"
"$ROOT/tests/macos/test-brew-install-runtime.sh"
"$ROOT/tests/macos/test-brew-configure.sh"
"$ROOT/tests/macos/test-brew-service.sh"
"$ROOT/tests/macos/test-brewfile-runtime.sh"
"$ROOT/tests/macos/test-brew-layered-runtime.sh"
"$ROOT/tests/macos/test-brew-upgrade.sh"
"$ROOT/tests/macos/test-brew-upgrade-runtime.sh"
"$ROOT/tests/macos/test-caddy-config.sh"
"$ROOT/tests/macos/test-caddy-runtime.sh"
"$ROOT/tests/macos/test-caddy-layered-runtime.sh"
"$ROOT/tests/macos/test-caddy-service.sh"
"$ROOT/tests/macos/test-caddy-service-runtime.sh"
"$ROOT/tests/macos/test-caddy-trust.sh"
"$ROOT/tests/macos/test-caddy-trust-runtime.sh"
"$ROOT/tests/macos/test-common.sh"
"$ROOT/tests/macos/test-devtools-config.sh"
"$ROOT/tests/macos/test-devtools-runtime.sh"
"$ROOT/tests/macos/test-docs.sh"
"$ROOT/tests/macos/test-args.sh"
"$ROOT/tests/macos/test-git-config.sh"
"$ROOT/tests/macos/test-git-config-runtime.sh"
"$ROOT/tests/macos/test-repo-remotes.sh"
"$ROOT/tests/macos/test-ghostty-config.sh"
"$ROOT/tests/macos/test-ghostty-runtime.sh"
"$ROOT/tests/macos/test-jj-config.sh"
"$ROOT/tests/macos/test-jj-runtime.sh"
"$ROOT/tests/macos/test-nushell-config.sh"
"$ROOT/tests/macos/test-nushell-runtime.sh"
"$ROOT/tests/macos/test-system-config.sh"
"$ROOT/tests/macos/test-system-runtime.sh"
"$ROOT/tests/macos/test-brew-bootstrap.sh"
"$ROOT/tests/macos/test-brew-bootstrap-runtime.sh"
"$ROOT/tests/macos/test-brew-bootstrap-fail-fast-runtime.sh"
"$ROOT/tests/macos/test-logging.sh"
"$ROOT/tests/macos/test-podman.sh"
"$ROOT/tests/macos/test-podman-machine-runtime.sh"

echo "All macOS checks passed"
