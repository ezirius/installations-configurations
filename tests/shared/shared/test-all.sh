#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"

cd "$ROOT"

bash -n \
  scripts/brew/macos/brew-install \
  scripts/brew/macos/brew-upgrade \
  scripts/brew/macos/brew-configure \
  scripts/brew/macos/brew-service \
  scripts/caddy/macos/caddy-configure \
  scripts/caddy/macos/caddy-service \
  scripts/caddy/macos/caddy-trust \
  scripts/podman/macos/podman-check \
  scripts/podman/macos/podman-configure \
  scripts/system/macos/system-configure \
  scripts/brew/macos/brew-bootstrap \
  tests/brew/macos/test-brewfile.sh \
  tests/brew/macos/test-brew-install.sh \
  tests/brew/macos/test-brew-install-runtime.sh \
  tests/brew/macos/test-brew-configure.sh \
  tests/brew/macos/test-brew-configure-runtime.sh \
  tests/brew/macos/test-brew-service.sh \
  tests/brew/macos/test-brew-service-runtime.sh \
  tests/brew/macos/test-brewfile-runtime.sh \
  tests/brew/macos/test-brew-host-fallback-runtime.sh \
  tests/brew/macos/test-brew-upgrade.sh \
  tests/brew/macos/test-brew-upgrade-runtime.sh \
  tests/caddy/macos/test-caddy-config.sh \
  tests/caddy/macos/test-caddy-override-runtime.sh \
  tests/caddy/macos/test-caddy-runtime.sh \
  tests/caddy/macos/test-caddy-service.sh \
  tests/caddy/macos/test-caddy-service-runtime.sh \
  tests/caddy/macos/test-caddy-trust.sh \
  tests/caddy/macos/test-caddy-trust-runtime.sh \
  tests/shared/shared/test-help.sh \
  tests/shared/shared/test-common.sh \
  tests/shared/shared/test-docs.sh \
  tests/shared/shared/test-args.sh \
  tests/brew/macos/test-brew-bootstrap.sh \
  tests/brew/macos/test-brew-bootstrap-runtime.sh \
  tests/brew/macos/test-brew-bootstrap-fail-fast-runtime.sh \
  tests/podman/macos/test-podman.sh \
  tests/podman/macos/test-podman-check-runtime.sh \
  tests/podman/macos/test-podman-diagnose-runtime.sh \
  tests/podman/macos/test-podman-machine-runtime.sh \
  tests/system/macos/test-system-config.sh \
  tests/system/macos/test-system-runtime.sh \
  tests/shared/shared/test-all.sh

"$ROOT/tests/brew/macos/test-brewfile.sh"
"$ROOT/tests/brew/macos/test-brew-install.sh"
"$ROOT/tests/brew/macos/test-brew-install-runtime.sh"
"$ROOT/tests/brew/macos/test-brew-configure.sh"
"$ROOT/tests/brew/macos/test-brew-configure-runtime.sh"
"$ROOT/tests/brew/macos/test-brew-service.sh"
"$ROOT/tests/brew/macos/test-brew-service-runtime.sh"
"$ROOT/tests/brew/macos/test-brewfile-runtime.sh"
"$ROOT/tests/brew/macos/test-brew-host-fallback-runtime.sh"
"$ROOT/tests/brew/macos/test-brew-upgrade.sh"
"$ROOT/tests/brew/macos/test-brew-upgrade-runtime.sh"
"$ROOT/tests/caddy/macos/test-caddy-config.sh"
"$ROOT/tests/caddy/macos/test-caddy-override-runtime.sh"
"$ROOT/tests/caddy/macos/test-caddy-runtime.sh"
"$ROOT/tests/caddy/macos/test-caddy-service.sh"
"$ROOT/tests/caddy/macos/test-caddy-service-runtime.sh"
"$ROOT/tests/caddy/macos/test-caddy-trust.sh"
"$ROOT/tests/caddy/macos/test-caddy-trust-runtime.sh"
"$ROOT/tests/shared/shared/test-help.sh"
"$ROOT/tests/shared/shared/test-common.sh"
"$ROOT/tests/shared/shared/test-docs.sh"
"$ROOT/tests/shared/shared/test-args.sh"
"$ROOT/tests/brew/macos/test-brew-bootstrap.sh"
"$ROOT/tests/brew/macos/test-brew-bootstrap-runtime.sh"
"$ROOT/tests/brew/macos/test-brew-bootstrap-fail-fast-runtime.sh"
"$ROOT/tests/podman/macos/test-podman.sh"
"$ROOT/tests/podman/macos/test-podman-check-runtime.sh"
"$ROOT/tests/podman/macos/test-podman-diagnose-runtime.sh"
"$ROOT/tests/podman/macos/test-podman-machine-runtime.sh"
"$ROOT/tests/system/macos/test-system-config.sh"
"$ROOT/tests/system/macos/test-system-runtime.sh"

echo "All macOS checks passed"
