# macOS Podman setup

## Setup order

Run these in order:

1. Run `scripts/macos/brew-install`
2. Run `scripts/macos/brewfile-install`
3. Run `scripts/macos/brew-upgrade`
4. Run `scripts/macos/iterm2-configure`
5. Run `scripts/macos/podman-machine-install`
6. Optionally run `scripts/macos/podman-check`

Or run `scripts/macos/bootstrap` to execute the same setup-and-upgrade flow in one command.

## What gets configured

- `scripts/macos/brew-install` installs Homebrew if needed
- `scripts/macos/brewfile-install` applies `config/brew/Brewfile`, including `iTerm2` as the managed macOS terminal for OpenCode instead of relying on `Terminal.app`, where OpenCode copy required `Cmd+R` and `Shift+Enter` did not create a new line
- `scripts/macos/brew-upgrade` runs `brew update` and upgrades the formulae and casks listed in `config/brew/Brewfile`
- `scripts/macos/iterm2-configure` applies managed iTerm2 preferences from `config/iterm2/defaults.conf`, including `AllowClipboardAccess=true`
- `scripts/macos/podman-machine-install` copies `config/containers/containers.conf` into `~/.config/containers/containers.conf`, ensures the Podman machine exists, applies the configured machine settings where supported, and then starts the machine
- `scripts/macos/podman-check` prints Podman status information and runs a small test container

See `docs/macos/iterm2.md` for the iTerm2-specific rationale and managed settings.

## Verification

Run `tests/macos/test-all.sh` to execute the repository shell checks in one command.

Scripts without positional arguments reject unexpected arguments explicitly. Scripts with a single optional override accept at most one positional argument.

For GitHub SSH and Git setup on macOS, run `scripts/macos/git-configure` from inside the repo you want to configure after the main system setup flow if needed.

Filesystem-changing script actions are also appended to the host CSV log in `~/Documents/Ezirius/Systems/Installations and Configurations/Computers`. Orchestrator and check scripts such as `scripts/macos/bootstrap` and `scripts/macos/podman-check` do not write their own CSV rows unless they directly make filesystem changes, and an open logfile keeps being reused until you close it by renaming the trailing dashes to an end date.
