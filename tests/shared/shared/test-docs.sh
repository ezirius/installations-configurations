#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
README="$ROOT/README.md"

test -f "$README"
test -f "$ROOT/docs/caddy/macos/caddy.md"
test -f "$ROOT/docs/podman/macos/podman.md"
test -f "$ROOT/docs/system/macos/system.md"
test -d "$ROOT/docs/superpowers/shared"
test ! -d "$ROOT/docs/superpowers/plans"
test -f "$ROOT/config/podman/macos/podman-runtime-settings-shared.conf"
test -f "$ROOT/config/repo/shared/repo-settings-shared.conf"

grep -q '`podman/`' "$README"
grep -q '`config/podman/`' "$README"
grep -q '`config/repo/`' "$README"
grep -q '`scripts/brew/macos/brew-configure`' "$README"
grep -q '`scripts/caddy/macos/caddy-trust`' "$README"
grep -q '`scripts/brew/macos/brew-service`' "$README"
grep -q '`scripts/brew/macos/brew-bootstrap`' "$README"
grep -q '`~/.config/containers/containers.conf`' "$README"
grep -q '`docs/caddy/macos/caddy.md`' "$README"
grep -q '`docs/podman/macos/podman.md`' "$README"
grep -q '`docs/system/macos/system.md`' "$README"
grep -q '`scripts/system/macos/system-configure`' "$README"
grep -q '`tests/shared/shared/test-all.sh`' "$ROOT/docs/caddy/macos/caddy.md"
grep -q '`tests/shared/shared/test-all.sh`' "$ROOT/docs/podman/macos/podman.md"
grep -q '`tests/shared/shared/test-all.sh`' "$ROOT/docs/system/macos/system.md"
grep -q 'Category:' "$ROOT/docs/caddy/macos/caddy.md"
grep -q 'Subcategory:' "$ROOT/docs/caddy/macos/caddy.md"
grep -q 'Scope:' "$ROOT/docs/caddy/macos/caddy.md"
grep -q 'Category:' "$ROOT/docs/podman/macos/podman.md"
grep -q 'Subcategory:' "$ROOT/docs/podman/macos/podman.md"
grep -q 'Scope:' "$ROOT/docs/podman/macos/podman.md"
grep -q 'Category:' "$ROOT/docs/system/macos/system.md"
grep -q 'Subcategory:' "$ROOT/docs/system/macos/system.md"
grep -q 'Scope:' "$ROOT/docs/system/macos/system.md"
grep -q '`scripts/system/macos/system-configure`' "$ROOT/docs/system/macos/system.md"
grep -q 'brew-configure' "$ROOT/docs/system/macos/system.md"
grep -q 'system-configure' "$ROOT/docs/system/macos/system.md"
grep -q '`config/brew/macos/brew-packages-shared.Brewfile`' "$README"
grep -q '`config/brew/macos/brew-packages-<host>.Brewfile`' "$README"
grep -q '`config/caddy/macos/caddy-runtime-shared.Caddyfile`' "$README"
grep -q '`config/caddy/macos/caddy-runtime-<host>.Caddyfile`' "$README"
grep -q '`config/brew/macos/brew-settings-shared.conf`' "$README"
grep -q '`config/brew/macos/brew-settings-<host>.conf`' "$README"
grep -q 'hostname up to, but not including, the first `\.`' "$README"
grep -q 'shared file is installed or loaded first' "$README"
grep -q 'matching host-specific file is installed or loaded after it' "$README"
grep -q '`config/podman/macos/podman-machine-settings-shared.conf`' "$ROOT/docs/podman/macos/podman.md"
grep -q '`config/podman/macos/podman-machine-settings-<host>.conf`' "$ROOT/docs/podman/macos/podman.md"
grep -q '`config/podman/macos/podman-runtime-settings-<host>.conf`' "$ROOT/docs/podman/macos/podman.md"
grep -q '`PODMAN_MACHINE_NAME_DEFAULT`' "$ROOT/docs/podman/macos/podman.md"
grep -q 'disk_size' "$ROOT/docs/podman/macos/podman.md"
grep -q '`config/podman/macos/podman-runtime-settings-shared.conf`' "$ROOT/docs/podman/macos/podman.md"
grep -q 'shared machine settings first' "$ROOT/docs/podman/macos/podman.md"
grep -q '`PODMAN_DIAGNOSE_OUTPUT_DIR`' "$ROOT/docs/podman/macos/podman.md"
grep -q '`PODMAN_DIAGNOSE_EVENT_WINDOWS`' "$ROOT/docs/podman/macos/podman.md"
grep -q '`PODMAN_DIAGNOSE_HOST_COMMANDS`' "$ROOT/docs/podman/macos/podman.md"
grep -q '`PODMAN_DIAGNOSE_MACHINE_COMMANDS`' "$ROOT/docs/podman/macos/podman.md"
grep -q '`config/caddy/macos/caddy-runtime-shared.Caddyfile`' "$ROOT/docs/caddy/macos/caddy.md"
grep -q '`config/caddy/macos/caddy-runtime-<host>.Caddyfile`' "$ROOT/docs/caddy/macos/caddy.md"
grep -q '`config/caddy/macos/caddy-settings-shared.conf`' "$ROOT/docs/caddy/macos/caddy.md"
grep -q '`config/caddy/macos/caddy-settings-<host>.conf`' "$ROOT/docs/caddy/macos/caddy.md"
grep -q '`scripts/caddy/macos/caddy-configure`' "$ROOT/docs/caddy/macos/caddy.md"
grep -q '`scripts/brew/macos/brew-service start`' "$ROOT/docs/caddy/macos/caddy.md"
grep -q '`https://127.0.0.1:8123`' "$ROOT/docs/caddy/macos/caddy.md"
grep -q '`config/system/macos/system-settings-shared.conf`' "$ROOT/docs/system/macos/system.md"
grep -q '`config/system/macos/system-settings-<host>.conf`' "$ROOT/docs/system/macos/system.md"
grep -q 'loads `config/system/macos/system-settings-shared.conf` first' "$ROOT/docs/system/macos/system.md"
grep -q '`scripts/system/macos/system-configure`' "$ROOT/docs/system/macos/system.md"

shopt -s nullglob
superpowers_docs=("$ROOT"/docs/superpowers/shared/*.md)
test "${#superpowers_docs[@]}" -gt 0
for superpowers_doc in "${superpowers_docs[@]}"; do
  case "$(basename "$superpowers_doc")" in
    [0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]-[0-9][0-9][0-9][0-9][0-9][0-9]-*.md) ;;
    *)
      printf 'unexpected superpowers timed document name: %s\n' "$superpowers_doc" >&2
      exit 1
      ;;
  esac
done

echo "Documentation checks passed"
