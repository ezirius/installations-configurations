# macOS Podman setup

## Setup order

Run these in order:

1. Run `scripts/macos/brew-install`
2. Run `scripts/macos/brewfile-install`
3. Run `scripts/macos/podman-machine-install`
4. Optionally run `scripts/macos/podman-check`

## What gets configured

- `scripts/macos/brew-install` installs Homebrew if needed
- `scripts/macos/brewfile-install` applies `config/brew/Brewfile`
- `scripts/macos/podman-machine-install` copies `config/containers/containers.conf` into `~/.config/containers/containers.conf`, ensures the Podman machine exists, applies the configured machine settings where supported, and then starts the machine
- `scripts/macos/podman-check` prints Podman status information and runs a small test container

For GitHub SSH and Git setup on macOS, run `scripts/macos/git-configure` from inside the repo you want to configure after the main system setup flow if needed.

Filesystem-changing script actions are also appended to the host CSV log in `~/Documents/Ezirius/Systems/Installations and Configurations/Computers`. Checks, starts, and other non-filesystem actions are not logged, and an open logfile keeps being reused until you close it by renaming the trailing dashes to an end date.
