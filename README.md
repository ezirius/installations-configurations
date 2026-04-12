# Personal macOS installation and configuration helpers

This repository currently automates a macOS-focused setup flow for Homebrew, Caddy, Ghostty, Nushell, a shared CLI developer-tooling baseline, Podman, and GitHub SSH/Git configuration.

## Layout

- `config/`
  - `brew/` contains the shared platform Brewfiles applied by `scripts/macos/brewfile-install`
  - `caddy/` contains the shared Caddy config copied into the Homebrew Caddy service location
  - `podman/` contains Podman machine defaults copied into `~/.config/containers/`
  - `system/` contains shared and optional host-specific macOS system settings applied by `scripts/macos/system-configure`
  - `ghostty/` contains the managed Ghostty include config copied into `~/.config/ghostty/`
  - `bat/`, `eza/`, `tlrc/`, `micro/`, `vim/`, `starship/`, `atuin/`, `zellij/`, `btop/`, `fd/`, and `lazygit/` contain the shared developer-tooling config copied into `~/.config/`
  - `ssh/` contains the current host-specific public GitHub SSH metadata, such as `config/ssh/maldoria.conf`
  - `jj/` contains the managed `jj` config copied into `~/.config/jj/`
  - `nushell/` contains the managed Nushell autoload config copied into `~/.config/nushell/`
- `docs/macos/` contains macOS-specific setup notes
- `lib/shell/` contains shared shell helpers used by scripts
- `scripts/macos/` contains macOS setup and verification scripts
- `tests/macos/` contains lightweight shell checks for the macOS workflow

## Quickstart

Before running the managed setup flow:

1. Set this repository clone's local Git identity because `scripts/macos/jj-configure` reads `user.name` and `user.email` from this clone:

```sh
git config user.name "Your Name"
git config user.email "you@example.com"
```

2. Ensure `python3` is already available on the machine. Several managed scripts use it before the Brewfile-managed packages are installed. Once Homebrew Python is installed from the shared Brewfile, the scripts prefer that managed Python automatically.

Run these in order:

1. Run `scripts/macos/brew-install`
2. Run `scripts/macos/brewfile-install`
3. Run `scripts/macos/brew-upgrade`
4. Run `scripts/macos/caddy-configure`
5. Run `scripts/macos/caddy-service start`
6. Run `scripts/macos/caddy-trust`
7. Run `scripts/macos/ghostty-configure`
8. Run `scripts/macos/jj-configure`
9. Run `scripts/macos/nushell-configure`
10. Run `scripts/macos/devtools-configure`
11. Run `scripts/macos/system-configure`
12. Run `scripts/macos/podman-machine-install`
13. Optionally run `scripts/macos/podman-check`

Or run `scripts/macos/bootstrap` to execute the same managed script sequence in one command once the prerequisites above are already in place.

The shared macOS Brewfile installs the default tooling for this setup, including `ghostty`, `nushell`, `git`, `ripgrep`, `fd`, `fzf`, `bat`, `eza`, `jq`, `just`, `uv`, `starship`, `atuin`, `micro`, `vim`, `zellij`, `jj`, `caddy`, and the container/inspection toolchain. The current repository policy is to keep general macOS config in `shared-macos` files, reserve `shared-linux` for Linux-only support when it is added, and keep host-specific config limited to Git/SSH metadata such as `config/ssh/maldoria.conf`. The managed terminal workflow is Ghostty launching Nushell directly, while the macOS default login shell stays unchanged.

`scripts/macos/brew-install` first checks for Xcode Command Line Tools and triggers `xcode-select --install` if they are missing, then stops until that installation is complete. After that, it only checks for an existing Homebrew installation and stops with a manual-install message when Homebrew is missing. This repository does not execute the upstream moving installer script automatically because that path is not checksum-verifiable in this workflow.

`caddy` is currently managed through the shared `config/caddy/shared.Caddyfile` and Homebrew's background service integration. The repository is structured so host-specific Caddy files can be added later if needed, but the current policy is to keep Caddy in the shared macOS layer and reserve host-specific config for Git/SSH items only.

The normal Caddy change workflow is:

1. Edit `config/caddy/shared.Caddyfile`
2. Run `scripts/macos/caddy-configure`
3. Run `scripts/macos/caddy-service reload`

For local HTTPS trust, run `scripts/macos/caddy-trust` after the service is running.

`jj` is managed through `~/.config/jj/config.toml`, and `scripts/macos/jj-configure` renders that file from this repository clone's local `git config user.name` and `git config user.email`. Set those values in this clone before running `jj-configure` or `bootstrap`.

`scripts/macos/devtools-configure` deploys the shared app config for the CLI and editor stack into `~/.config`. This includes blue dark-mode theme defaults for `bat`, `eza`, `tlrc`, `starship`, `zellij`, `btop`, `micro`, `vim`, and `lazygit`, plus managed behaviour/config for tools such as `fd` and `atuin`. On macOS it also bridges `~/.config/lazygit` and `~/.config/zellij` into the Application Support paths those tools still probe by default, and writes `~/.vimrc` as a bridge to `~/.config/vim/vimrc`.

The managed shell integration remains Nushell-only. The Nushell autoload file wires together `fd`, `fzf`, `bat`, `eza`, `zoxide`, `atuin`, `starship`, `jj`, `direnv`, `jq`, and `yq`. No `bash` or `zsh` shell hooks are used for this workflow.

`scripts/macos/system-configure` currently applies the shared macOS host settings from `config/system/shared-macos.conf`. The current shared defaults enable Dock auto-hide, disable automatic Spaces rearranging based on recent use, and prevent automatic sleeping on AC power while the display is off. Host-specific system overrides are intentionally not used at the moment.

Managed user config is centralised under `~/.config`:

- `~/.config/ghostty/config.ghostty`
- `~/.config/ghostty/installations-configurations.ghostty`
- `~/.config/nushell/`
- `~/.config/git/installations-configurations.conf`
- `~/.config/jj/config.toml`
- `~/.config/bat/`
- `~/.config/eza/`
- `~/.config/tlrc/`
- `~/.config/micro/`
- `~/.config/vim/`
- `~/.config/starship/`
- `~/.config/atuin/`
- `~/.config/zellij/`
- `~/.config/btop/`
- `~/.config/fd/`
- `~/.config/lazygit/`
- `~/.config/containers/containers.conf`

Additional compatibility bridge:

- `~/.vimrc` -> `source ~/.config/vim/vimrc`

Where possible, the repository adds managed include or autoload files instead of replacing user primary config wholesale.

As an extra macOS compatibility bridge, `scripts/macos/nushell-configure` also links `~/Library/Application Support/nushell` to `~/.config/nushell` when that path is available for use. If `~/Library/Application Support/nushell` already exists as a real unmanaged directory or file, the script stops so you can migrate or remove that content first instead of overwriting it.

See `docs/macos/caddy.md`, `docs/macos/devtools.md`, `docs/macos/git.md`, `docs/macos/ghostty.md`, `docs/macos/nushell.md`, `docs/macos/podman.md`, and `docs/macos/system.md` for the focused macOS notes. The machine install step applies the configured Podman machine settings before starting the machine.

## GitHub setup on Maldoria

Run `scripts/macos/git-configure` from inside the repo you want to configure.

- It reads `user.name` and `user.email` from this repository clone's local Git config
- It reads public key metadata from `config/ssh/<host>.conf`
- It exports the matching `.pub` files into `~/.ssh/`
- It writes a repo-specific SSH alias into `~/.ssh/config`
- It writes a managed Git include into `~/.config/git/installations-configurations.conf`
- It adds that include to `~/.gitconfig` through `include.path`
- It updates the current repo's `origin` to use that alias
- It enables SSH commit signing with the host signing key and updates `~/.ssh/allowed_signers`

The matching private keys must already exist in 1Password and be available through the 1Password SSH agent. Run this after the shared Brewfile-managed `git`, `git-delta`, and `micro` tooling is installed if you want the full managed review/editor defaults to be effective immediately.

## Verification

Run `tests/macos/test-all.sh` to execute the repository shell checks in one command.

Scripts that do not take positional arguments now reject them explicitly, and scripts with a single optional override accept at most one positional argument.

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
