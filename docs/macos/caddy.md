# macOS Caddy setup

## Managed config model

This repository currently manages `caddy` through the shared `config/caddy/shared.Caddyfile` and the Homebrew service definition.

The managed source of truth lives in:

- `config/caddy/shared.Caddyfile`

The repository can support host-specific Caddy files later if needed, but the current policy is to keep Caddy in the shared macOS layer and keep host-specific config limited to Git/SSH metadata.

The deployed runtime config lives in Homebrew's expected service path:

- `$(brew --prefix)/etc/Caddyfile`

## Managed reverse proxy

`scripts/macos/caddy-configure` supports concatenating shared and host-specific Caddy files, but the current repository only ships the shared file. In the current setup it therefore deploys `config/caddy/shared.Caddyfile` into one final runtime Caddyfile, and one background Caddy service serves all of its site blocks.

You also need `python3` available before running the managed setup scripts because the config-deployment path uses it before any Brewfile-managed packages are installed.

The current shared Caddyfile is:

```caddy
127.0.0.1:8123 {
    reverse_proxy https://hovaryn.mioverso.com:8123
}
```

## How the service stays running

This repository keeps `caddy` running in the background with Homebrew services:

- `scripts/macos/brew-service start`

That uses:

- `brew services start caddy`

This is the persistent background mode. It registers `caddy` with macOS `launchctl`, uses the Homebrew `caddy` service definition, and keeps the service running across login and reboot. If the service is already running, the `start` action reloads the managed config instead of leaving the running service stale.

## Local HTTPS trust

Because the managed reverse proxy serves local HTTPS on `127.0.0.1:8123`, the local Caddy CA must also be trusted on the machine.

This repository manages that through:

- `scripts/macos/caddy-trust`

That uses:

- `caddy trust --config "$(brew --prefix)/etc/Caddyfile" --adapter caddyfile`

For config changes without downtime, use:

- `scripts/macos/brew-service reload`

That uses:

- `caddy reload --config "$(brew --prefix)/etc/Caddyfile" --adapter caddyfile`

## Normal change workflow

When you need to change the reverse proxy config:

1. Edit `config/caddy/shared.Caddyfile`
2. Run `scripts/macos/caddy-configure`
3. Run `scripts/macos/brew-service reload`

That keeps the repository as the source of truth, re-validates and deploys the managed Caddyfile, and reloads the running service without stopping it.

## Setup order

Run either:

1. `scripts/macos/brew-install`
2. `scripts/macos/brew-upgrade`
3. `scripts/macos/brew-configure`
4. `scripts/macos/brew-service start`

or run `scripts/macos/bootstrap` to perform the same managed script sequence once the required prerequisites are already in place.

## Verification

Run `tests/macos/test-all.sh` to execute the repository shell checks in one command.
