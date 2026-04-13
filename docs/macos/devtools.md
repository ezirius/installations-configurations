# macOS developer tooling setup

## Managed scope

This repository manages a shared CLI and terminal-editor baseline in addition to Ghostty, Nushell, Caddy, Podman, and Git/SSH setup.

The managed source config currently includes the shared tool configs below:

- `config/bat/`
- `config/eza/`
- `config/tlrc/`
- `config/starship/`
- `config/atuin/`
- `config/zellij/`
- `config/btop/`
- `config/fd/`
- `config/lazygit/`
- `config/micro/`
- `config/vim/`

`scripts/macos/devtools-configure` deploys those shared config trees into `~/.config`, writes `~/.vimrc` as a bridge to `~/.config/vim/vimrc`, and creates compatibility bridges for the macOS `lazygit` and `zellij` application-support paths.

That means the managed runtime outputs include:

- `~/.config/bat/`
- `~/.config/eza/`
- `~/.config/tlrc/`
- `~/.config/starship/`
- `~/.config/atuin/`
- `~/.config/zellij/`
- `~/.config/btop/`
- `~/.config/fd/`
- `~/.config/lazygit/`
- `~/.config/micro/`
- `~/.config/vim/`
- `~/.vimrc`

## Theme standard

The shared developer-tooling layer follows the same restrained blue dark palette family used by Ghostty and the Nushell workflow.

That includes:

- `bat`
- `eza`
- `tlrc`
- `starship`
- `zellij`
- `btop`
- `micro`
- `vim`

The goal is one coherent dark terminal environment rather than unrelated per-tool themes.

Not every managed tool in this layer is themed. For example, `fd` is managed through ignore behaviour rather than colours, and `atuin` is managed through history/search behaviour rather than palette configuration.

## Shell integration

Shell-facing integration remains in Nushell only.

The managed Nushell setup wires together:

- `fd`
- `fzf`
- `bat`
- `eza`
- `zoxide`
- `atuin`
- `starship`
- `direnv`
- `jq`
- `yq`
- `jj`

No `bash` or `zsh` shell hooks are used for this workflow.

## Editors

The repository manages two terminal editors in the shared stack:

- `micro` as the main lightweight quick editor
- Homebrew `vim` as a serious fallback/editor ubiquity tool

Both are configured with a balanced setup and the same blue dark theme family.

## Setup order

Run either:

1. `scripts/macos/brew-install`
2. `scripts/macos/brew-upgrade`
3. `scripts/macos/brew-configure`
4. `scripts/macos/brew-service start`

or run `scripts/macos/bootstrap` to perform the same managed script sequence once the required prerequisites are already in place.

## Verification

Run `tests/macos/test-all.sh` to execute the repository shell checks in one command.
