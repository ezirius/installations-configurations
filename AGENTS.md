# AGENTS

## Purpose

This repository manages installation and configuration files through a small,
shared shell workflow.

The current focus is Homebrew installation through layered Brewfiles.
Apple Mac restore images, full installer download handling from Apple's
official sources, and macOS system configuration are also active under the
same repo layout.

## Current Active Layout

- `configs/` stores application configs grouped by OS scope.
- `libs/shared/` stores shell helpers shared by macOS and Linux scripts.
- `scripts/` stores runnable scripts grouped by OS scope and application.
- `tests/shared/` stores shared shell tests grouped by application.
- `logs/` stores runtime activity logs and is gitignored.

The repo is intentionally small. Brew is the primary active application
workflow right now, with macOS download handling and macOS system configuration
also active under the same repo layout.

### Active Files

The active implementation surface is:

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

Keep rules, documentation, and behaviour aligned with these files.

External runtime values must live under `configs/`.
This includes URLs, default paths, labels, tokens, headers, and similar
operational defaults.
Test fixtures may remain inline in tests.
Missing required runtime config files are hard failures.

## Naming Rules

### OS Scope

- `shared` means the config applies to both macOS and Linux.
- `macos` means the config applies only to macOS.
- `linux` means the config applies only to Linux.

### Brewfile Paths

Brew config lives under one of these folders:

- `configs/shared/brew/`
- `configs/macos/brew/`
- `configs/linux/brew/`

General config layout follows this pattern:

```text
configs/<os>/<application>/...
```

This path pattern is the default for future application families as well.

System config currently follows this path pattern under:

- `configs/macos/system/system-settings-shared.conf`
- `configs/macos/system/system-settings-<host>.conf`

Download workflows currently follow this path pattern under:

- `configs/macos/downloads/macos-download-shared.conf`
- `scripts/macos/downloads/macos-download`
- `tests/shared/downloads/test-macos-download.sh`

Each Brewfile must use this filename pattern:

```text
Brewfile-<host>-<username>
```

Where:

- `<host>` is either `shared` or the normalised current hostname.
- `<username>` is the normalised `whoami` value.

Normalization rules:

- lowercase everything
- trim the hostname at the first `.`
- replace non-alphanumeric characters with `-`
- collapse repeated `-`

Examples:

- `configs/shared/brew/Brewfile-shared-ezirius`
- `configs/shared/brew/Brewfile-maldoria-ezirius`
- `configs/macos/brew/Brewfile-shared-ezirius`
- `configs/linux/brew/Brewfile-shared-ezirius`

## Brewfile Content Rules

The active workflow supports only these Brewfile entry forms:

```ruby
brew "formula-name"
cask "cask-name"
```

Allowed non-entry lines:

- blank lines
- comment lines beginning with `#`

Behaviour is strict:

- only double-quoted `brew` and `cask` entries are supported
- single-quoted entries are unsupported
- inline trailing comments are unsupported
- unsupported non-empty lines fail clearly
- unsupported directives must never be ignored silently
- do not broaden Brewfile syntax unless the parser and tests are updated together

Layering rules:

- the same token may appear in more than one Brewfile layer
- layered files are processed in resolution order
- entries are additive; there is no override syntax
- already installed entries are skipped at install time

## Shared Code Rules

- Put reusable shell helpers in `libs/shared/`.
- Keep script-specific orchestration in `scripts/<os>/<application>/`.
- If code is shared by both macOS and Linux, prefer `libs/shared/shared/common.sh`
  first unless there is already a better-focused shared file.
- If code is shared only within one application family, place it under
  `libs/shared/<application>/`.
- Do not move application-specific logic into `libs/shared/shared/common.sh`
  unless it is truly generic across application families.

### `libs/shared/shared/common.sh`

`libs/shared/shared/common.sh` is the current generic shared helper library.

It is the right place for:

- terminal color helpers
- generic error and help helpers
- repo-root resolution helpers
- OS, host, and username detection
- generic Homebrew shellenv loading
- generic activity log helpers

Shared logging defaults used by those helpers must come from:

- `configs/shared/shared/logging-shared.conf`

It is not the right place for:

- install-only workflow logic
- script-specific command sequencing
- config-family-specific business rules unless they are clearly reused

## Output Rules

Use:

- green for success and active selections
- amber for warnings and skips
- red for errors

Keep non-interactive output plain text.

For shared entrypoint CLI output, keep the contract simple:

- green: success
- amber: warnings and skips
- red: errors

## Activity Logging Rules

- Write activity logs under `logs/<os>/shared/`.
- Use one per-host CSV file: `installations-and-configurations-<host>.csv`.
- The CSV header is: `date,time,host,action,application,version`.
- Use normalised host names in both the filename and CSV rows.
- Use brew and cask tokens in the `application` column.
- Use South Africa time via the `Africa/Johannesburg` timezone.
- If a version cannot be resolved after a successful operation, log an empty version field.

Action values:

- installs: `Installed`
- upgrades: `Updated`
- removals: `Removed`

When the workflow installs Homebrew itself, log it as:

- action: `Installed`
- application: `brew`
- version: the resolved Homebrew version, or empty when unavailable

When the system workflow changes a managed setting, log it as:

- action: `Updated`
- application: the stable managed setting token
- version: empty

## Implementation Rules

- Always keep the code as simple as possible.
- Prefer the smallest practical change.
- Always use superpowers and TDD for all tasks.
- Use TDD for behavioural changes and refactors that can affect behaviour.
- Keep all external values in `configs/` for scripts and libraries.
- Do not make scripts declarative just to move external values out of code.
- This rule does not apply to test files; test fixtures may remain in tests.
- Keep shell code compatible with the current macOS Bash environment.
- Prefer simple portable shell patterns over newer Bash-only features when a
  compatible alternative exists.
- Let Homebrew handle architecture selection such as ARM vs x86.
- Support Linux and macOS through OS folder selection, not architecture logic.
- Shared entrypoint scripts should accept only no arguments or `--help` / `-h`.
- Any other argument should fail with the aligned message:
  `ERROR: <script-name> takes no arguments. Use --help for usage.`
- When iterating with `while read` over file or redirected input, do not let
  child commands inherit that same stdin.
- For the current shared installer workflow, prefer a dedicated fixed file
  descriptor for loop input so child commands like `brew` cannot consume
  Brewfile entries and force partial installs across multiple runs.
- Clean up `mktemp` artifacts on both success and failure paths in active
  scripts.
- Prefer shell patterns that avoid `pipefail` surprises on success paths, such
  as avoiding `... | head -n1` when a direct helper can return the same value.

## Testing Rules

- Update or add tests before changing behaviour.
- Keep `tests/shared/brew/test-brew-install.sh` green.
- Keep `tests/shared/downloads/test-macos-download.sh` green.
- Treat the active shared shell test as a characterization test for the current
  Homebrew workflow.
- Prefer fake repo tests with stubbed system commands for shared script behaviour.
- Cover known shell failure modes in tests, including child commands that
  consume stdin unexpectedly.
- Cover Homebrew bootstrap behaviour in tests, including logging Homebrew's own
  installation when the workflow performs it.
- When moving helpers into `libs/shared/`, rerun the shared test immediately.
- Run shell syntax checks on changed scripts and libraries.
- When changing shared path conventions, update the fake repo test layout first
  so tests fail on the old contract before runtime code is changed.
- Prefer behaviour-based assertions over brittle absolute numbering in
  interactive download tests.
- When an interactive selection depends on rendered menu ordering, derive the
  selector from captured output instead of hard-coding menu numbers.
- Cover strict parser behaviour in tests, including unsupported trailing content
  on otherwise valid-looking Brewfile lines.

## Documentation Rules

- Be concise in user-facing responses.
- Present user-facing responses in a clear, easy-to-read format.
- Use tables when they improve clarity; otherwise prefer short sections and lists.
- Use British English in user-facing writing and documentation.
- Use the metric system in user-facing writing and documentation.
- When a domain normally uses imperial units as the standard reference, write measurements as metric first followed by imperial in parentheses.
- Keep all scripts, code, libraries, tests, configs, and active docs well documented.
- Add short header comments to active scripts and config files when the contract
  is not obvious from the filename alone.
- Add short header comments to active shared libraries when their role is not
  obvious from the filename alone.
- Add a short header comment to each active test file describing covered
  behaviours and the isolation approach when it is not obvious from the filename.
- Treat missing or weak documentation in active files as a defect to fix, not as
  optional cleanup.
- Keep active docs precise and aligned with the current file layout and behaviour.
- Keep `README.md` aligned with the current active layout, not deleted legacy
  paths.

## Repo Hygiene Rules

- Ignore repo-local runtime artifacts such as `downloads/` and `logs/`.
- Keep `.gitignore` ordered with hidden entries first, then non-hidden entries,
  and alphabetical order within each group.

## Git Rules

- Match the current commit title style: short imperative subject with a type
  prefix such as `fix:` or `refactor:`.
- Scope commit messages to the actual worktree. If the diff includes repo
  layout consolidation and workflow replacement, prefer a `refactor:` framing
  over a narrow `fix:` title.
- SSH commit signing on this machine uses 1Password's SSH agent. For terminal
  commits, ensure `SSH_AUTH_SOCK` points to:
  `/Users/ezirius/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock`
  when signing is required.

## Current Brewfile Resolution Order

`scripts/shared/brew/brew-install` resolves Brewfiles in this order:

1. `configs/shared/brew/Brewfile-shared-<username>`
2. `configs/shared/brew/Brewfile-<host>-<username>`
3. `configs/<os>/brew/Brewfile-shared-<username>`
4. `configs/<os>/brew/Brewfile-<host>-<username>`

This order is intentional:

- shared files provide the baseline
- host-specific files add to the baseline
- OS-specific files refine the shared baseline

## Current `brew-install` Behaviour

The active installer:

1. Detects repo root from the script path.
2. Detects `os`, `host`, and `username`.
3. Loads Homebrew into `PATH` when installed in a standard prefix.
4. Installs Homebrew itself if it is still missing.
5. Logs Homebrew itself as `Installed,brew,<version>` when the workflow installs it.
6. Resolves all matching Brewfiles.
7. Parses each Brewfile in order.
8. Installs only missing formulae and casks.
9. Skips already installed entries.
10. Fails clearly on unsupported Brewfile lines.
11. Logs each successful install to the per-host CSV activity log.

Additional current behaviour:

- supports `--help`
- takes no positional arguments
- does not run `brew update`
- does not upgrade already installed entries
- uses `Installed` as the install activity action name
- writes logs to `logs/<os>/shared/installations-and-configurations-<host>.csv`
- creates the CSV header automatically when the log file does not exist
- isolates Brewfile processing input from child commands so one run can process
  the full Brewfile reliably
- leaves Homebrew metadata updates and package upgrades out of the current
  workflow scope

## Current Shared Paths

The current shared path conventions are:

- configs: `configs/<os>/<application>/...`
- scripts: `scripts/<os>/<application>/...`
- generic shared libs: `libs/shared/shared/...`
- application-shared libs: `libs/shared/<application>/...`
- tests: `tests/shared/<application>/...`

## Current Download Behaviour

`scripts/macos/downloads/macos-download` currently:

1. uses Apple's public macOS IPSW catalog as the direct official source for
   Apple Silicon restore images
2. uses `softwareupdate --list-full-installers` and
   `--fetch-full-installer` for official full installer listing and downloads
3. groups macOS download options into `ARM` and `X86` sections
4. labels each row as `IPSW` or `Installer`
5. offers Apple Silicon IPSW downloads and ARM/X86 full installer downloads
6. numbers only actionable downloads
7. sorts each section newest to oldest by version and build
8. stores IPSW downloads under `downloads/macos/downloads/` by default
9. re-prompts on invalid interactive selection instead of exiting immediately
10. supports `--help`
11. takes no positional arguments

Important current limitation:

- Apple Silicon restore images come from Apple's public macOS IPSW catalog
- full installers come from Apple's `softwareupdate` tooling
- Intel restore IPSW rows are not shown in the default output because they are
  not actionable from current official Apple sources

## Current Bootstrap Behaviour

`scripts/shared/shared/bootstrap` currently:

1. detects repo root from the script path
2. runs `scripts/shared/brew/brew-install`
3. runs `scripts/macos/system/system-configure` only if the Brew step succeeds on macOS
4. fails on macOS when `scripts/macos/system/system-configure` is missing or not executable
5. skips macOS-only workflows on Linux
6. stops on the first failure
7. supports `--help`
8. takes no positional arguments

## Current System Behaviour

`scripts/macos/system/system-configure` currently:

1. detects repo root and current host
2. requires macOS and the needed system commands
3. resolves `configs/macos/system/system-settings-<host>.conf` first when present
4. falls back to `configs/macos/system/system-settings-shared.conf`
5. applies Dock auto-hide and Spaces ordering only when values differ
6. restarts the Dock only when Dock settings changed
7. applies AC power sleep with `pmset` only when needed
8. uses `pmset -c` on portable Macs and `pmset -a` on non-portable Macs
9. logs each managed setting change to the shared per-host CSV activity log
