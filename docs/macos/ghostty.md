# macOS Ghostty setup

## Why this setup uses Ghostty

This repository manages `Ghostty` as the single terminal for the macOS workflow.

Ghostty is configured to launch `Nushell` directly, while the macOS default login shell stays unchanged.

## Managed config

This repository keeps the canonical managed Ghostty include in:

- `~/.config/ghostty/installations-configurations.ghostty`

`scripts/macos/ghostty-configure` deploys that file from `config/ghostty/installations-configurations.ghostty`, renders the absolute Homebrew `nu` path into the `command` setting, and ensures the main `~/.config/ghostty/config.ghostty` includes the managed file. This keeps the managed config additive so Ghostty works reliably whether it is launched from Finder, Spotlight, Dock, or another shell.

The managed config also applies one restrained dark palette so the terminal stays readable and visually consistent with the Nushell and `fzf` setup.

The wider shared developer-tooling stack uses the same blue dark palette family through `bat`, `eza`, `tlrc`, `starship`, `micro`, `vim`, `btop`, and `zellij`, so Ghostty acts as the visual anchor for the whole terminal workflow.

## Setup order

Run either:

1. Set this repository clone's local `git config user.name` and `git config user.email` before the wider managed flow if you plan to use `scripts/macos/brew-bootstrap` or `scripts/macos/jj-configure`
2. Ensure `python3` is already available on the machine
3. `scripts/macos/brew-install`
4. `scripts/macos/brew-upgrade`
5. `scripts/macos/brew-configure`
6. `scripts/macos/brew-service start`

or run `scripts/macos/brew-bootstrap` to perform the same managed script sequence once the required prerequisites are already in place.

## Verification

Run `tests/macos/test-all.sh` to execute the repository shell checks in one command.
