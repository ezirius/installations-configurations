# macOS system settings setup

Category: `docs/` stores setup notes written for people.

Subcategory: `system/` is everything for the standalone system-settings part of the repo.

Scope: `macos/` means this page is only for the macOS workflow.

## Managed config model

This repo manages a small shared set of macOS host settings through:

- `config/system/macos/system-settings-shared.conf`

The checked-in default lives in the shared macOS layer. If a matching `config/system/macos/system-settings-<host>.conf` exists for the current Mac, the script uses it instead of the shared file.

`scripts/system/macos/system-configure` uses simple host fallback: it loads the matching host-specific file when present, otherwise it uses `config/system/macos/system-settings-shared.conf`.

## Shared defaults

The current shared macOS defaults are:

- enable Dock auto-hide
- disable automatic Spaces rearranging based on recent use
- prevent automatic system sleep while on AC power when the display is off

The config keys are written to describe the setting they control:

- `DOCK_AUTO_HIDE`
- `DOCK_REORDER_SPACES_BY_RECENT_USE`
- `AC_POWER_SYSTEM_SLEEP_MINUTES`

## What the script does

`scripts/system/macos/system-configure`:

1. loads the matching host-specific macOS system config when present, otherwise the shared fallback
2. applies the managed Dock settings with `defaults`
3. restarts the Dock only when Dock-related values changed
4. applies the AC sleep setting with `pmset`

For portable Macs, the power-management setting is applied with `pmset -c sleep 0`.

For non-portable Macs, it is applied with `pmset -a sleep 0`.

## Requirements

This script needs:

- Xcode Command Line Tools
- `sudo` for the `pmset` change

## Setup order

Run:

1. `scripts/brew/macos/brew-configure`
2. or run `scripts/system/macos/system-configure` directly when you only want to re-apply the managed system settings

Run `scripts/system/macos/system-configure --help` to review the managed command usage without applying changes.

The current `scripts/brew/macos/brew-configure` flow includes `scripts/system/macos/system-configure`, so the broader Homebrew-backed configuration now applies these managed system settings automatically.

## Verification

The main verification entrypoint is `tests/shared/shared/test-all.sh`.
