# macOS system settings setup

## Managed config model

This repository manages a small shared layer of macOS host settings through:

- `config/system/shared-macos.conf`

The repository can support host-specific system overrides later if needed, but the current policy is to keep system settings in the shared macOS layer and keep host-specific config limited to Git/SSH metadata.

`scripts/macos/system-configure` supports shared and host-specific files, but the current repository only ships the shared file, so the effective managed source today is `config/system/shared-macos.conf`.

## Shared defaults

The current shared macOS defaults are:

- enable Dock auto-hide
- disable automatic Spaces rearranging based on recent use
- prevent automatic system sleep while on AC power when the display is off

The config keys are intentionally written in intent-based language:

- `DOCK_AUTO_HIDE`
- `DOCK_REORDER_SPACES_BY_RECENT_USE`
- `AC_POWER_SYSTEM_SLEEP_MINUTES`

## What the script does

`scripts/macos/system-configure`:

1. loads the shared macOS system config
2. loads the optional host-specific macOS system config
3. applies the managed Dock settings with `defaults`
4. restarts the Dock only when Dock-related values changed
5. applies the AC sleep setting with `pmset`

For portable Macs, the power-management setting is applied with `pmset -c sleep 0`.

For non-portable Macs, it is applied with `pmset -a sleep 0`.

## Requirements

This script needs:

- Xcode Command Line Tools
- `sudo` for the `pmset` change

## Setup order

Run:

1. `scripts/macos/system-configure`

The current `scripts/macos/brew-bootstrap` flow does not run `scripts/macos/system-configure` automatically.

## Verification

Run `tests/macos/test-all.sh` to execute the repository shell checks in one command.
