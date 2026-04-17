# macOS Caddy setup

Category: `docs/` stores setup notes written for people.

Subcategory: `caddy/` is everything for the Caddy part of the repo.

Scope: `macos/` means this page is only for the macOS workflow.

## Managed config model

This repo manages `caddy` with one shared macOS Caddyfile and the Homebrew service.

The managed source of truth lives in:

- `config/caddy/macos/caddy-runtime-shared.Caddyfile`

The deployed runtime config lives in Homebrew's expected service path:

- `$(brew --prefix)/etc/Caddyfile`

## Managed reverse proxy

`scripts/caddy/macos/caddy-configure` deploys the managed macOS Caddyfile from:

- `config/caddy/macos/caddy-runtime-shared.Caddyfile`

You also need `python3` available before running the managed setup scripts because the config-deployment path uses it before any Brewfile-managed packages are installed.

The current managed Caddyfile is:

```caddy
https://127.0.0.1:8123 {
    reverse_proxy https://hovaryn.mioverso.com:8123
}
```

## How the service stays running

This repository keeps `caddy` running in the background with Homebrew services:

- `scripts/brew/macos/brew-service start`

That uses:

- `brew services start caddy`

This is the normal background mode. Homebrew registers `caddy` with macOS `launchctl`. If `caddy` is already running, `start` reloads the managed config so the service does not keep stale settings.

## Local HTTPS trust

The managed reverse proxy serves local HTTPS on `https://127.0.0.1:8123`, so the local Caddy CA must also be trusted on the machine.

This repository manages that through:

- `scripts/caddy/macos/caddy-trust`

That uses:

- `caddy trust --config "$(brew --prefix)/etc/Caddyfile" --adapter caddyfile`

For config changes without downtime, use:

- `scripts/brew/macos/brew-service reload`

That uses:

- `caddy reload --config "$(brew --prefix)/etc/Caddyfile" --adapter caddyfile`

## Normal change workflow

When you need to change the reverse proxy config:

1. Edit `config/caddy/macos/caddy-runtime-shared.Caddyfile`
2. Run `scripts/caddy/macos/caddy-configure`
3. Run `scripts/brew/macos/brew-service reload`

That keeps the repo as the source of truth, copies the managed Caddyfile into place, and reloads the running service without stopping it.

## Setup order

Run either:

1. `scripts/brew/macos/brew-install`
2. `scripts/brew/macos/brew-upgrade`
3. `scripts/brew/macos/brew-configure`
4. `scripts/brew/macos/brew-service start`

or run `scripts/brew/macos/brew-bootstrap` to perform the same managed script sequence once the required prerequisites are already in place. `scripts/brew/macos/brew-configure` already runs `scripts/caddy/macos/caddy-trust`, so manual trust is only needed when you are running the Caddy steps directly outside that workflow.

## Verification

The main verification entrypoint is `tests/shared/shared/test-all.sh`.
