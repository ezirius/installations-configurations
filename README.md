# Personal macOS installation and configuration helpers

This repository now automates the macOS Homebrew, Caddy, Podman, and standalone system-settings workflow.

## Layout

A category is the top-level folder such as `config/`, `docs/`, `scripts/`, or `tests/`.

A subcategory is the next folder that groups files by tool or topic such as `brew/`, `caddy/`, `podman/`, `shared/`, or `system/`.

Scope tells you who a file is for. `shared/` means every machine can use it. `macos/` means the file is for macOS. A hostname in a filename means the file is only for that machine.

- `config/` stores managed settings files
- `config/brew/` stores Brewfiles and Brew wrapper settings
- `config/caddy/` stores the managed Caddyfile source
- `config/podman/` stores Podman machine and runtime defaults
- `config/repo/` stores repo-wide naming and path rules
- `config/system/` stores managed macOS system-setting defaults
- `docs/` stores setup notes written for people
- `lib/shell/shared/` stores shared shell helpers
- `scripts/` stores runnable setup and verification commands
- `tests/shared/shared/` stores the shared test runner entrypoints and shared shell checks

## Quickstart

Before running the managed setup flow:

1. Ensure `python3` is already available on the machine. Several managed scripts use it before the Brewfile-managed packages are installed.

2. Ensure Homebrew itself is already installed. This repository intentionally does not run the upstream moving installer script automatically.

Run these in order:

1. Run `scripts/brew/macos/brew-install`
2. Run `scripts/brew/macos/brew-upgrade`
3. Run `scripts/brew/macos/brew-configure`
4. Run `scripts/brew/macos/brew-service start`
5. Optionally run `scripts/podman/macos/podman-check`

Or run `scripts/brew/macos/brew-bootstrap` to execute the same managed script sequence in one command once the prerequisites above are already in place.

The shared macOS Brewfile installs the managed package set for this repository: `caddy`, `podman`, `podman-compose`, and `podman-desktop`. Wrapper defaults live in metadata files under `config/`, with `config/repo/` and `config/podman/` supporting the remaining shared shell helpers.

## Config selection

This repository uses host fallback only: when a matching host-specific file exists, it is used; otherwise the shared file is used.

- Brewfiles:
  - shared: `config/brew/macos/brew-packages-shared.Brewfile`
  - host-specific: `config/brew/macos/brew-packages-<host>.Brewfile`
In the current repository state, a host-specific Brewfile is optional and replaces the shared Brewfile when present.

`scripts/brew/macos/brew-install` first checks for Xcode Command Line Tools and triggers `xcode-select --install` if they are missing, then stops until that installation is complete. After that, it checks for an existing Homebrew installation, stops with a manual-install message when Homebrew is missing, and then installs only missing entries from the shared Brewfile package set. `scripts/brew/macos/brew-install` and `scripts/brew/macos/brew-upgrade` also require this repository to be committed and pushed before they run. This repository does not execute the upstream moving installer script automatically because that path is not checksum-verifiable in this workflow.

`caddy` is managed through `config/caddy/macos/caddy-runtime-shared.Caddyfile` and Homebrew's background service integration.

The normal Caddy change workflow is:

1. Edit `config/caddy/macos/caddy-runtime-shared.Caddyfile`
2. Run `scripts/caddy/macos/caddy-configure`
3. Run `scripts/caddy/macos/caddy-service reload`

For local HTTPS trust, run `scripts/caddy/macos/caddy-trust` after `scripts/caddy/macos/caddy-configure` has deployed the managed Caddyfile for `https://127.0.0.1:8123`. In the default workflow this already happens inside `scripts/brew/macos/brew-configure`.

`scripts/brew/macos/brew-configure` is the post-install umbrella command for the current Brew workflow. It runs the configured wrapper steps from `config/brew/macos/brew-settings-shared.conf`, which currently are:

1. `scripts/caddy/macos/caddy-configure`
2. `scripts/caddy/macos/caddy-trust`
3. `scripts/podman/macos/podman-configure`
4. `scripts/system/macos/system-configure`

`scripts/brew/macos/brew-service` is the service-lifecycle umbrella command. It currently manages the background Caddy service and accepts `start`, `stop`, `restart`, `reload`, and `status`.

Managed user config is centralised under `~/.config`:

- `~/.config/containers/containers.conf`

Where possible, the repository adds managed include or autoload files instead of replacing user primary config wholesale.

Operational defaults are expected to live in configuration files under `config/` rather than in scripts or `lib/shell/shared/common.sh`. Scripts keep control flow and validation logic, while config files own path layouts, service defaults, deployment manifests, and wrapper-level default values.

The repository also ships a macOS system-settings command:

1. `scripts/system/macos/system-configure`

It now runs as part of `scripts/brew/macos/brew-configure`, and it can still be run directly when you only want to re-apply the managed system settings.

Run `scripts/system/macos/system-configure --help` to inspect the command without applying the managed settings.

See `docs/caddy/macos/caddy.md`, `docs/podman/macos/podman.md`, and `docs/system/macos/system.md` for the focused macOS notes. The machine install step applies the configured Podman machine settings before starting the machine.

## Verification

The main verification entrypoint is `tests/shared/shared/test-all.sh`.

Scripts that do not take positional arguments now reject them explicitly, and scripts with a single optional override accept at most one positional argument.
