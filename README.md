# Installation And Configurations

## Current Layout

The current active repo layout is intentionally small:

- `configs/` stores application configs grouped by OS scope.
- `libs/shared/` stores shell helpers shared by macOS and Linux scripts.
- `scripts/` stores runnable scripts grouped by OS scope and application.
- `tests/shared/` stores shared shell tests grouped by application.
- `logs/` is reserved for runtime output and is gitignored.

The current active workflows are:

- Homebrew installation through layered Brewfiles
- Apple Mac restore images and full installer downloads from Apple's official sources
- macOS system configuration with host-specific override and shared fallback settings files

## Active Files

The current active implementation surface is:

- `configs/shared/shared/logging-shared.conf`
- `configs/shared/brew/brew-install-shared.conf`
- `configs/macos/brew/Brewfile-shared-ezirius`
- `configs/macos/downloads/macos-download-shared.conf`
- `configs/macos/system/system-settings-shared.conf`
- `libs/shared/shared/common.sh`
- `scripts/shared/brew/brew-install`
- `scripts/macos/downloads/macos-download`
- `scripts/shared/shared/bootstrap`
- `scripts/macos/system/system-configure`
- `tests/shared/brew/test-brew-install.sh`
- `tests/shared/downloads/test-macos-download.sh`
- `tests/shared/shared/test-bootstrap.sh`
- `tests/shared/system/test-system-configure.sh`

These files are the current source of truth for the active Brew, downloads,
bootstrap, and system workflows.
Repository documentation should stay aligned with them.

External runtime values must live under `configs/`.
This includes URLs, default paths, labels, tokens, headers, and similar
operational defaults.
Test fixtures may remain inline in tests.
Missing required runtime config files are hard failures.

All active scripts, libs, tests, configs, and docs should be well documented.

Active test files should include a short header that describes the covered
behaviours and the isolation approach used by the test.

Shared entrypoint scripts should accept only no arguments or `--help` / `-h`.
Any other argument should fail with:

```text
ERROR: <script-name> takes no arguments. Use --help for usage.
```

The current shared entrypoints are:

- `scripts/shared/brew/brew-install`
- `scripts/shared/shared/bootstrap`

The current macOS-only entrypoints are:

- `scripts/macos/downloads/macos-download`
- `scripts/macos/system/system-configure`

## Brewfile Contract

Brewfiles live under:

- `configs/shared/brew/`
- `configs/macos/brew/`
- `configs/linux/brew/`

Each Brewfile must use this filename pattern:

```text
Brewfile-<host>-<username>
```

Where:

- `<host>` is either `shared` or the current hostname normalised to lowercase up to the first `.`
- `<username>` is `whoami`, normalised to lowercase with non-alphanumeric characters converted to `-`
- leading and trailing `-` characters are trimmed
- repeated `-` characters are collapsed

Examples:

- `configs/shared/brew/Brewfile-shared-ezirius`
- `configs/shared/brew/Brewfile-maldoria-ezirius`
- `configs/macos/brew/Brewfile-shared-ezirius`
- `configs/macos/brew/Brewfile-maldoria-ezirius`

## Brewfile Resolution

`scripts/shared/brew/brew-install` detects:

- OS: `macos` or `linux`
- host: normalised hostname
- username: normalised `whoami`

It then loads every matching Brewfile in this order:

1. `configs/shared/brew/Brewfile-shared-<username>`
2. `configs/shared/brew/Brewfile-<host>-<username>`
3. `configs/<os>/brew/Brewfile-shared-<username>`
4. `configs/<os>/brew/Brewfile-<host>-<username>`

Shared files provide the baseline. Host-specific files add to that baseline.

If no matching Brewfiles exist, the script fails with an error.

## Brewfile Contents

The current parser recognizes these entry forms:

```ruby
brew "formula-name"
cask "cask-name"
```

Blank lines and full-line comments beginning with `#` are ignored.
Single-quoted entries and inline trailing comments are rejected.
Any other non-empty line is rejected as an error so unsupported Brewfile
directives do not fail silently.

The same token may appear in more than one Brewfile layer.
Layered entries are additive, processed in resolution order, and there is no
override syntax.

## `scripts/shared/brew/brew-install`

This script is the current shared Homebrew installer entrypoint.

Behaviour:

1. Detect repo root from the script location.
2. Detect OS, host, and username.
3. Load Homebrew into `PATH` for the running script if it is installed in a standard prefix.
4. Install Homebrew itself if it is still missing, then log `Installed,brew,<version>`.
5. Persist Homebrew command availability for future shells:
   - `~/.zprofile` for `zsh`
   - `~/.bash_profile` and `~/.bashrc` for Bash
   - Nushell `config.nu` with `PATH`-only Homebrew entries stored in the canonical `.config` location
6. Resolve matching Brewfiles.
7. Parse each matching Brewfile in order.
8. Install only missing formulae and casks.
9. Skip already installed entries.
10. Reject unsupported Brewfile directives with a clear error.
11. Append one CSV row for each successful install to the per-host activity log.
12. Do not run `brew update` or upgrade already installed entries.

The script does not implement architecture selection. Homebrew handles ARM/x86 selection.
Homebrew metadata updates and package upgrades are currently outside this
workflow's scope.

Nushell config resolution order is:

1. `$XDG_CONFIG_HOME/nushell/config.nu` when `XDG_CONFIG_HOME` is set
2. `~/.config/nushell/config.nu` when `XDG_CONFIG_HOME` is not set

On macOS when `XDG_CONFIG_HOME` is not set, the workflow also keeps
`~/Library/Application Support/nushell` as a compatibility symlink to the
canonical per-user `.config/nushell` directory.

## `libs/shared/shared/common.sh`

This file is the current shared shell helper library for both macOS and Linux.

It owns generic helpers for:

- terminal colors and error output
- help-flag handling
- repo-root resolution from a script path
- OS, host, and username detection
- Homebrew shell environment loading
- South Africa activity-log timestamps and CSV log helpers

Shared logging defaults used by those helpers are loaded from:

- `configs/shared/shared/logging-shared.conf`

Script-specific workflow logic should stay in the calling script instead of
being moved into `libs/shared/shared/common.sh` too early.

## Output Conventions

`scripts/shared/brew/brew-install` uses color when writing to a terminal:

- green: success and active selections
- amber/orange: warnings
- plain text: skips
- red: errors

Non-interactive output remains plain text.

Shared entrypoint scripts use the same CLI color contract:

- green: success
- amber/orange: warnings
- plain text: skips
- red: errors

## Activity Logs

The active install workflow writes CSV activity logs under:

- `logs/macos/shared/`
- `logs/linux/shared/`

Each host writes to:

```text
logs/<os>/shared/installations-and-configurations-<host>.csv
```

The CSV header is:

```text
date,time,host,action,application,version
```

Current action values:

- `Installed` for Homebrew itself when `scripts/shared/brew/brew-install` installs it
- `Installed` from `scripts/shared/brew/brew-install`
- `Updated` from `scripts/macos/system/system-configure` when a managed system setting changes

Dates and times are written in South Africa time using the
`Africa/Johannesburg` timezone.

Those shared logging defaults are configured in:

- `configs/shared/shared/logging-shared.conf`

## Tests

The current scripts are covered by:

- `tests/shared/brew/test-brew-install.sh`
- `tests/shared/downloads/test-macos-download.sh`
- `tests/shared/shared/test-bootstrap.sh`
- `tests/shared/system/test-system-configure.sh`

Run it with:

```bash
tests/shared/brew/test-brew-install.sh
tests/shared/downloads/test-macos-download.sh
tests/shared/shared/test-bootstrap.sh
tests/shared/system/test-system-configure.sh
```

## `scripts/macos/downloads/macos-download`

This script lists official Apple macOS restore images and full installers,
groups them by architecture, and lets the user download one official Apple
artifact.

Behaviour:

1. Uses Apple's public macOS IPSW catalog as the official direct source for Apple Silicon restore images.
2. Uses `softwareupdate --list-full-installers` and `--fetch-full-installer` for official full installer downloads.
3. Uses Apple's public macOS IPSW catalog and `softwareupdate` as the active official sources.
4. Groups entries into `ARM` and `X86` sections.
5. Labels each entry as `IPSW` or `Installer`.
6. Shows only actionable parsed rows and marks each shown row as `Download available`.
7. Lets the user select one downloadable entry by number.
8. Sorts each section newest to oldest by version and build.
9. Supports `--help` and takes no positional arguments.

External macOS download defaults are configured in:

- `configs/macos/downloads/macos-download-shared.conf`

Note:

- Apple Silicon restore images come from Apple's public macOS IPSW catalog.
- Full installers come from Apple's `softwareupdate` tooling.
- Intel restore IPSW rows are not shown in the default output because they are
  not actionable from current official Apple sources.

## `scripts/shared/shared/bootstrap`

This script is the current cross-application shared entrypoint.

Behaviour:

1. Detect repo root from the script location.
2. Run `scripts/shared/brew/brew-install`.
3. On macOS, run `scripts/macos/system/system-configure` only if the Brew step succeeds.
4. On macOS, fail if `scripts/macos/system/system-configure` is missing or not executable.
5. On Linux, skip macOS-only workflows.
6. Stop on the first failure.

## `scripts/macos/system/system-configure`

This script applies the managed macOS system settings from `configs/macos/system/`.

Behaviour:

1. Detect repo root and current host.
2. Require macOS and the needed system commands.
3. Resolve the preferred config with host fallback:
   - `configs/macos/system/system-settings-<host>.conf`
   - `configs/macos/system/system-settings-shared.conf`
4. Apply Dock auto-hide and Spaces ordering only when values differ.
5. Restart the Dock only when Dock settings changed.
6. Apply AC power sleep with `pmset` only when the managed value differs.
7. Use `pmset -c` on portable Macs and `pmset -a` on non-portable Macs.
8. Append one `Updated` CSV row for each managed setting that actually changes.

The current managed macOS system settings are:

- Dock auto-hide
- Spaces reordering by recent use
- AC power system sleep minutes

Managed setting log tokens also come from the system config file.
