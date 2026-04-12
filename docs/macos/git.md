# macOS Git and GitHub SSH setup

## Managed scope

This repository manages the macOS Git and GitHub SSH workflow through:

- host-specific public-key metadata in `config/ssh/<host>.conf`
- `scripts/macos/git-configure`

The script is intended to be run from inside the repository you want to configure.

## Prerequisites

Before running `scripts/macos/git-configure`:

1. Set this repository clone's local `git config user.name` and `git config user.email`
2. Ensure the matching private keys already exist in 1Password
3. Ensure the 1Password SSH agent socket is available on the machine
4. Ensure the shared Brewfile-managed `git`, `git-delta`, and `micro` tooling is already installed if you want the full managed editor/review defaults to be effective immediately

## What gets configured

`scripts/macos/git-configure`:

1. reads host-specific public-key metadata from `config/ssh/<host>.conf`
2. exports the matching `.pub` files into `~/.ssh/`
3. writes a repo-specific GitHub SSH alias into `~/.ssh/config`
4. writes `~/.ssh/allowed_signers`
5. writes a managed Git include file into:
   - `~/.config/git/installations-configurations.conf`
6. adds that file to global Git with:
   - `include.path`
7. updates the current repo's `origin` to use the managed GitHub SSH alias when the current remote already matches the expected host/path

The managed Git include currently carries:

- `user.name`
- `user.email`
- `user.signingkey`
- `init.defaultBranch = main`
- `core.editor = micro`
- `core.pager = delta`
- `interactive.diffFilter = delta --color-only`
- `delta.navigate = true`
- `delta.line-numbers = true`
- `merge.conflictstyle = zdiff3`
- SSH commit/tag signing settings

The script refuses to silently rewrite unexpected remote hosts or mismatched repo paths.

## Verification

Run `tests/macos/test-all.sh` to execute the repository shell checks in one command.
