# macOS Podman setup

## Managed config

The Podman machine defaults live in:

- `config/podman/containers.conf`

`scripts/macos/podman-machine-install` copies that file into:

- `~/.config/containers/containers.conf`

and then ensures the managed Podman machine exists, applies the configured settings where supported, and starts the machine if needed.

The current shared defaults are intentionally conservative baseline values:

- `cpus=4`
- `memory=4096`
- `disk_size=60`
- `rootful=false`

## What the script does

`scripts/macos/podman-machine-install`:

1. validates that `podman` and the managed config source are available
2. copies the managed `containers.conf` into `~/.config/containers/containers.conf`
3. creates the managed machine if it does not yet exist
4. applies supported machine settings from `containers.conf`
5. safely stops and restarts an already-running machine when mutable settings need to change
6. verifies that `podman info` succeeds at the end

Unsupported `podman machine set` flags are skipped explicitly rather than failing silently.

## Verification

After running the machine install step, you can run:

1. `scripts/macos/podman-check`

That prints Podman status information and runs a small test container.

Run `tests/macos/test-all.sh` to execute the repository shell checks in one command.
