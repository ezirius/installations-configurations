# Personal macOS installation and configuration helpers

This repository now automates the macOS Homebrew, Caddy, Podman, and standalone system-settings workflow.

## Layout

- `config/`
  - `brew/` contains the shared platform Brewfiles applied by `scripts/macos/brew-install`
  - `caddy/` contains the managed macOS Caddy config copied into the Homebrew Caddy service location
  - `podman/` contains Podman machine defaults copied into `~/.config/containers/`
  - `repo/` contains repository-wide naming and path-layout metadata
  - `system/` contains the managed macOS system-setting defaults
- `docs/macos/` contains macOS-specific setup notes
- `lib/shell/` contains shared shell helpers used by scripts
- `scripts/macos/` contains macOS setup and verification scripts
- `tests/macos/` contains lightweight shell checks for the macOS workflow

## Quickstart

Before running the managed setup flow:

1. Ensure `python3` is already available on the machine. Several managed scripts use it before the Brewfile-managed packages are installed.

2. Ensure Homebrew itself is already installed. This repository intentionally does not run the upstream moving installer script automatically.

Run these in order:

1. Run `scripts/macos/brew-install`
2. Run `scripts/macos/brew-upgrade`
3. Run `scripts/macos/brew-configure`
4. Run `scripts/macos/brew-service start`
5. Optionally run `scripts/macos/podman-check`

Or run `scripts/macos/brew-bootstrap` to execute the same managed script sequence in one command once the prerequisites above are already in place.

The shared macOS Brewfile installs the managed package set for this repository: `caddy`, `podman`, `podman-compose`, and `podman-desktop`. Wrapper defaults live in metadata files under `config/`, with `config/repo/` and `config/podman/` supporting the remaining shared shell helpers.

## Layered config

This repository supports layered config where a shared file can be extended by a matching host-specific file when one exists.

- Brewfiles:
  - shared: `config/brew/shared-macos.Brewfile`
  - host-specific: `config/brew/<host>-macos.Brewfile`
In the current repository state:

- a host-specific Brewfile is optional and only applied when present

`scripts/macos/brew-install` first checks for Xcode Command Line Tools and triggers `xcode-select --install` if they are missing, then stops until that installation is complete. After that, it checks for an existing Homebrew installation, stops with a manual-install message when Homebrew is missing, and then installs only missing entries from the shared Brewfile package set. `scripts/macos/brew-install` and `scripts/macos/brew-upgrade` also require this repository to be committed and pushed before they run. This repository does not execute the upstream moving installer script automatically because that path is not checksum-verifiable in this workflow.

`caddy` is managed through `config/caddy/shared-macos.Caddyfile` and Homebrew's background service integration.

The normal Caddy change workflow is:

1. Edit `config/caddy/shared-macos.Caddyfile`
2. Run `scripts/macos/caddy-configure`
3. Run `scripts/macos/caddy-service reload`

For local HTTPS trust, run `scripts/macos/caddy-trust` after `scripts/macos/caddy-configure` has deployed the managed Caddyfile. In the default workflow this already happens inside `scripts/macos/brew-configure`.

`scripts/macos/brew-configure` is the post-install umbrella command for the current Brew workflow. It runs the configured wrapper steps from `config/brew/shared-macos.conf`, which currently are:

1. `scripts/macos/caddy-configure`
2. `scripts/macos/caddy-trust`
3. `scripts/macos/podman-configure`

`scripts/macos/brew-service` is the service-lifecycle umbrella command. It currently manages the background Caddy service and accepts `start`, `stop`, `restart`, `reload`, and `status`.

Managed user config is centralised under `~/.config`:

- `~/.config/containers/containers.conf`

Where possible, the repository adds managed include or autoload files instead of replacing user primary config wholesale.

Operational defaults are expected to live in configuration files under `config/` rather than in scripts or `lib/shell/common.sh`. Scripts keep control flow and validation logic, while config files own path layouts, service defaults, deployment manifests, and wrapper-level default values.

The repository also ships a standalone macOS system-settings command:

1. `scripts/macos/system-configure`

It is not part of the current Brew bootstrap path.

See `docs/macos/caddy.md`, `docs/macos/podman.md`, and `docs/macos/system.md` for the focused macOS notes. The machine install step applies the configured Podman machine settings before starting the machine.

## Verification

Run `tests/macos/test-all.sh` to execute the repository shell checks in one command.

Scripts that do not take positional arguments now reject them explicitly, and scripts with a single optional override accept at most one positional argument.
