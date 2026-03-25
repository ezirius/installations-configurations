# Personal macOS installation and configuration helpers

This repository currently automates a macOS-focused setup flow for Homebrew, Podman, iTerm2, and GitHub SSH/Git configuration.

## Layout

- `config/`
  - `brew/` contains the Brewfile applied by `scripts/macos/brewfile-install`
  - `containers/` contains Podman machine defaults copied into `~/.config/containers/`
  - `git/` contains public GitHub key metadata keyed by host, such as `config/git/maldoria.conf`
  - `iterm2/` contains managed iTerm2 preferences applied by `scripts/macos/iterm2-configure`
- `docs/macos/` contains macOS-specific setup notes
- `lib/shell/` contains shared shell helpers used by scripts
- `scripts/macos/` contains macOS setup and verification scripts
- `tests/macos/` contains lightweight shell checks for the macOS workflow

## macOS Podman workflow

Run these in order:

1. Run `scripts/macos/brew-install`
2. Run `scripts/macos/brewfile-install`
3. Run `scripts/macos/brew-upgrade`
4. Run `scripts/macos/iterm2-configure`
5. Run `scripts/macos/podman-machine-install`
6. Optionally run `scripts/macos/podman-check`

Or run `scripts/macos/bootstrap` to execute the same setup-and-upgrade flow in one command.

The Brewfile step installs the default macOS tooling for this setup, including `iTerm2` for OpenCode use on macOS rather than relying on `Terminal.app`. The main reason is that `Terminal.app` had two practical issues in OpenCode: copy required pressing `Cmd+R`, and `Shift+Enter` did not insert a new line. Moving to `iTerm2` resolved those issues, and the iTerm2 configure step applies the managed clipboard-access preference used by this workflow.

See `docs/macos/podman.md` for the same workflow in a shorter form and `docs/macos/iterm2.md` for the dedicated iTerm2 note. The machine install step applies the configured Podman machine settings before starting the machine.

## Verification

Run `tests/macos/test-all.sh` to execute the repository shell checks in one command.

Scripts that do not take positional arguments now reject them explicitly, and scripts with a single optional override accept at most one positional argument.

## macOS Git/GitHub setup

This is a separate post-setup step, not part of the Podman/bootstrap order above.

Run `scripts/macos/git-configure` from inside the repo you want to configure.

- It sets global Git identity defaults for the current host
- It reads public key metadata from `config/git/<host>.conf`
- It exports the matching `.pub` files into `~/.ssh/`
- It writes a repo-specific SSH alias into `~/.ssh/config`
- It updates the current repo's `origin` to use that alias
- It enables SSH commit signing with the host signing key and updates `~/.ssh/allowed_signers`

The matching private keys must already exist in 1Password and be available through the 1Password SSH agent.

## Change log

When a script makes filesystem changes, it appends rows to a host log in `~/Documents/Ezirius/Systems/Installations and Configurations/Computers`.

- Open logfile format: `<Host> Installations and Configurations-<YYYYMMDD>---------.csv`
- Closed files are any matching host logs whose names no longer end with `---------`
- If an open host log already exists, scripts keep appending to it until you close it by renaming the trailing dashes to an end date; otherwise they create a new open file for the current date
- Logged columns are `Date`, `Time`, `Username`, `Type`, `Script`, `Item`, `Change`, `Path`, and `Details`
- Only real filesystem changes are logged
- This includes Homebrew installation, Homebrew metadata updates, Brewfile-managed installs/upgrades, managed config-file writes, and Git/SSH config updates
- Orchestrator and check scripts such as `scripts/macos/bootstrap` and `scripts/macos/podman-check` do not write their own CSV rows unless they directly make filesystem changes

Example row:

```csv
"20260322","143505","ezirius","Configuration","scripts/macos/git-configure","SSH config","Updated","/Users/ezirius/.ssh/config","Managed GitHub SSH alias github-maldoria-installations-configurations"
```
