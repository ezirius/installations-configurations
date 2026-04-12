# macOS system settings setup

## Managed config model

This repository currently manages a small shared layer of macOS host settings through:

- `config/system/shared-macos.conf`

The repository can support host-specific system overrides later if needed, but the current policy is to keep system settings in the shared macOS layer and keep host-specific config limited to Git/SSH metadata.

`scripts/macos/system-configure` supports shared and host-specific files, but the current repository only ships the shared file, so the effective managed source today is `config/system/shared-macos.conf`.

## Shared defaults

The current shared macOS defaults are:

- enable Dock auto-hide
- disable automatic Spaces rearranging based on recent use
- prevent automatic system sleep while on AC power when the display is off

## What the script does

`scripts/macos/system-configure`:

1. loads the shared macOS system config
2. loads the optional host-specific macOS system config
3. applies the managed Dock settings with `defaults`
4. restarts the Dock only when Dock-related values changed
5. applies the AC sleep setting with `pmset`
6. logs only real changes

For portable Macs, the power-management setting is applied with `pmset -c sleep 0`.

## Requirements

This script needs:

- Xcode Command Line Tools
- `sudo` for the `pmset` change

## Setup order

Run either:

1. `scripts/macos/brew-install`
2. `scripts/macos/brewfile-install`
3. `scripts/macos/brew-upgrade`
4. `scripts/macos/system-configure`

or run `scripts/macos/bootstrap` to perform the same managed script sequence once the required prerequisites are already in place.

## Verification

Run `tests/macos/test-all.sh` to execute the repository shell checks in one command.
