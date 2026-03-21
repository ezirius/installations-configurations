# Managing Personal macOS and Linux Configurations and Rebuilds (Installations and Configurations)

## Layout

Only this README is in the base directory.

- `config/`
- `docs/`
- `examples/`
- `lib/`
- `scripts/`
- `tests/`

## Current macOS Podman workflow

1. Run `scripts/macos/brew-install`
2. Run `scripts/macos/brewfile-install`
3. Run `scripts/macos/podman-machine-install`
4. Optionally run `scripts/shared/podman-check`
