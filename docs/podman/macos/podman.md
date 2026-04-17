# macOS Podman setup

Category: `docs/` stores setup notes written for people.

Subcategory: `podman/` is everything for the Podman part of the repo.

Scope: `macos/` means this page is only for the macOS workflow.

## Managed config

The shared macOS Brewfile manages the Podman package set for this repository:

- `podman`
- `podman-compose`
- `podman-desktop`

The Podman machine defaults live in:

- `config/podman/macos/podman-machine-settings-shared.conf`

If `config/podman/macos/podman-machine-settings-<host>.conf` exists for the current Mac, `scripts/podman/macos/podman-configure` prefers that host-specific file and otherwise falls back to the shared one.

The managed machine name and diagnose defaults live in:

- `config/podman/macos/podman-runtime-settings-shared.conf`

`scripts/podman/macos/podman-configure` copies the selected machine settings into:

- `~/.config/containers/containers.conf`

Then it makes sure the managed Podman machine exists, compares the current machine with the managed settings, and starts the machine if needed.

The default managed machine name is controlled by `PODMAN_MACHINE_NAME_DEFAULT`.

The current shared defaults are simple baseline values:

- `cpus=4`
- `memory=8192`
- `disk_size=60`
- `rootful=false`

## What the script does

`scripts/podman/macos/podman-configure`:

1. validates that `podman` and the managed config source are available
2. resolves `config/podman/macos/podman-machine-settings-<host>.conf` first and otherwise falls back to `config/podman/macos/podman-machine-settings-shared.conf`, then copies the selected file into `~/.config/containers/containers.conf`
3. creates the managed machine if it does not yet exist
4. computes the per-setting drift between the existing machine and the selected managed machine-settings file
5. asks for approval before applying managed setting changes to an existing machine
6. stops and restarts a running machine only after approval, and only for the settings that actually differ
7. reports the specific differing settings and exits cleanly if Podman reconciliation is bypassed by user choice
8. verifies that `podman info` succeeds at the end unless reconciliation was bypassed

If the installed Podman build does not support a required managed machine-setting flag, `scripts/podman/macos/podman-configure` fails clearly instead of quietly drifting from the configured defaults.

The managed machine config covers every setting in `config/podman/macos/podman-machine-settings-shared.conf`, not just disk size. Today that means `cpus`, `memory`, `disk_size`, and `rootful` are all compared against the current machine state.

For existing machines, `disk_size` is treated as a grow-only managed setting. If the managed value is larger than the current machine disk, `scripts/podman/macos/podman-configure` can grow it after approval. If the managed value is smaller than the current machine disk, the drift is reported clearly and not applied automatically.

If you decline the approval prompt, `scripts/podman/macos/podman-configure` exits successfully so the rest of `scripts/brew/macos/brew-configure` can keep running, and it prints the exact managed settings that still differ.

## Verification

After running the machine install step, you can run:

1. `scripts/podman/macos/podman-check`
2. `scripts/podman/macos/podman-check diagnose`

`scripts/podman/macos/podman-check` prints Podman status information and runs a small test container.

`scripts/podman/macos/podman-check diagnose` prints a formatted diagnostic report to the terminal and saves a timestamped copy under `logs/podman/`. The diagnostic mode captures a point-in-time snapshot including Podman version info, machine state, containers, images, storage usage, bounded non-streaming event snapshots for the configured recent windows, machine SSH diagnostics, and the verification container run.

The diagnose mode is config-driven. The current defaults live in `config/podman/macos/podman-runtime-settings-shared.conf`:

- `PODMAN_DIAGNOSE_OUTPUT_DIR`
- `PODMAN_DIAGNOSE_EVENT_WINDOWS`
- `PODMAN_DIAGNOSE_HOST_COMMANDS`
- `PODMAN_DIAGNOSE_MACHINE_COMMANDS`

`PODMAN_DIAGNOSE_OUTPUT_DIR` may be either:

- a relative path, resolved from the repository root
- or an absolute path

The current default writes timestamped reports under `logs/podman/`.

The normal managed setup order is:

1. `scripts/brew/macos/brew-install`
2. `scripts/brew/macos/brew-upgrade`
3. `scripts/brew/macos/brew-configure`
4. `scripts/brew/macos/brew-service start`

The main verification entrypoint is `tests/shared/shared/test-all.sh`.
