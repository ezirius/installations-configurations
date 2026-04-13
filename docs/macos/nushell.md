# macOS Nushell setup

## Managed config model

This repository manages `Nushell` as the shell used inside `Ghostty`, not as the macOS login shell.

The canonical managed config lives in:

- `~/.config/nushell/`

As an extra compatibility bridge on macOS, `scripts/macos/nushell-configure` also links:

- `~/Library/Application Support/nushell` -> `~/.config/nushell`

If `~/Library/Application Support/nushell` already exists as a real unmanaged directory or file, the script stops so you can migrate or remove that content first.

## What gets configured

`scripts/macos/nushell-configure` deploys and maintains:

- `autoload/installations-configurations.nu`
- generated `atuin` Nushell integration
- generated `starship` Nushell integration
- generated `zoxide` Nushell integration
- generated `jj` Nushell completions

The managed shell setup keeps the key integrations inside Nushell only:

- explicit Homebrew paths for GUI-launched terminal sessions
- `zoxide` integration for `z` and `zi`
- `fzf` defaults and small Nu-native helper commands built around `fd`, `bat`, and `eza`
- `jj` completions

The current shared Nushell workflow also integrates:

- `atuin` history initialisation
- `starship` prompt initialisation
- `direnv` environment loading on directory changes
- `jq` and `yq` helper commands
- `micro` as the default editor target for fuzzy file-open commands

`scripts/macos/jj-configure` renders the managed `jj` config from this repository clone's local `git config user.name` and `git config user.email`, so set those values in this clone before running the managed shell/bootstrap flow.

You also need `python3` available before running the managed setup scripts because the config-deployment path uses it before any Brewfile-managed packages are installed. Once Homebrew Python is installed from the shared Brewfile, the scripts prefer that managed Python automatically.

The managed setup is additive: it relies on Nushell's autoload behaviour rather than replacing a user's primary `config.nu` or `env.nu` files.

The managed config keeps a restrained dark palette through Ghostty and `fzf` rather than mixing different terminal themes.

## Setup order

Run either:

1. `scripts/macos/brew-install`
2. `scripts/macos/brew-upgrade`
3. `scripts/macos/brew-configure`
4. `scripts/macos/brew-service start`

or run `scripts/macos/bootstrap` to perform the same managed script sequence once the required prerequisites are already in place.

## Verification

Run `tests/macos/test-all.sh` to execute the repository shell checks in one command.
