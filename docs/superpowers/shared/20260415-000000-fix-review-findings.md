# Fix Review Findings Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Correct the validated review findings around local Caddy HTTPS, Podman machine reconciliation, test-suite coverage, and documentation accuracy.

**Architecture:** Keep the existing config-driven shell workflow intact and apply the smallest behavioural fixes in-place. Drive each bug fix with a failing shell test first, then implement the minimal script or config change, then update the docs and broader verification so the repository contract stays aligned.

**Tech Stack:** Bash shell scripts, config files under `config/`, Markdown documentation, shell-based runtime tests under `tests/shared/shared/`

---

### Task 1: Make Local Caddy HTTPS Explicit and Deploy Safely

**Files:**
- Modify: `config/caddy/macos/caddy-runtime-shared.Caddyfile`
- Modify: `scripts/caddy/macos/caddy-configure`
- Modify: `tests/caddy/macos/test-caddy-config.sh`
- Modify: `tests/caddy/macos/test-caddy-runtime.sh`

- [ ] **Step 1: Write the failing tests**

```bash
grep -q '^https://127.0.0.1:8123 {$' tests/caddy/macos/test-caddy-config.sh
grep -q 'first-run custom prefix without pre-created etc' tests/caddy/macos/test-caddy-runtime.sh
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `./tests/caddy/macos/test-caddy-config.sh && ./tests/caddy/macos/test-caddy-runtime.sh`
Expected: FAIL because the Caddyfile still starts with `127.0.0.1:8123 {` and the runtime test does not yet cover the missing `etc/` directory case.

- [ ] **Step 3: Write minimal implementation**

```caddy
https://127.0.0.1:8123 {
    reverse_proxy https://hovaryn.mioverso.com:8123
}
```

```bash
render_caddyfile() {
  local output_path="$1"
  shift

  mkdir -p "$(dirname "$output_path")"
  TEMP_FILE="$(mktemp)"
  "$PYTHON3_COMMAND" - "$TEMP_FILE" "$@" <<'PY'
from pathlib import Path
import sys

destination = Path(sys.argv[1])
parts = []
for source_path in sys.argv[2:]:
    parts.append(Path(source_path).read_text().rstrip())

destination.write_text("\n\n".join(part for part in parts if part) + "\n")
PY

  mv "$TEMP_FILE" "$output_path"
  TEMP_FILE=""
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `./tests/caddy/macos/test-caddy-config.sh && ./tests/caddy/macos/test-caddy-runtime.sh`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add config/caddy/macos/caddy-runtime-shared.Caddyfile scripts/caddy/macos/caddy-configure tests/caddy/macos/test-caddy-config.sh tests/caddy/macos/test-caddy-runtime.sh
git commit -S -m "fix: Make Local Caddy HTTPS Explicit" -m "- Make the managed local Caddy listener explicitly serve HTTPS so the trust workflow matches the actual runtime behaviour.
- Create the rendered-file parent directory before moving the temporary output so first-run deployments on fresh Homebrew prefixes do not fail."
```

### Task 2: Harden Caddy Trust Detection and Documentation

**Files:**
- Modify: `scripts/caddy/macos/caddy-trust`
- Modify: `tests/caddy/macos/test-caddy-trust-runtime.sh`
- Modify: `README.md`
- Modify: `docs/caddy/macos/caddy.md`

- [ ] **Step 1: Write the failing tests**

```bash
grep -q 'stale certificate name is not enough' tests/caddy/macos/test-caddy-trust-runtime.sh
grep -q 'https://127.0.0.1:8123' docs/caddy/macos/caddy.md
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `./tests/caddy/macos/test-caddy-trust-runtime.sh && ./tests/shared/shared/test-docs.sh`
Expected: FAIL because stale-name trust detection is not covered and the docs still describe ambiguous HTTPS behaviour.

- [ ] **Step 3: Write minimal implementation**

```bash
find_trusted_keychain() {
  local keychain

  for keychain in "${CADDY_TRUST_KEYCHAINS[@]}"; do
    if security verify-cert -c "$keychain" >/dev/null 2>&1 && \
      security find-certificate -c "$CADDY_TRUST_CERT_NAME" "$keychain" >/dev/null 2>&1; then
      printf '%s\n' "$keychain"
      return 0
    fi
  done

  return 1
}
```

```md
Because the managed reverse proxy serves local HTTPS on `https://127.0.0.1:8123`, the local Caddy CA must also be trusted on the machine.
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `./tests/caddy/macos/test-caddy-trust-runtime.sh && ./tests/shared/shared/test-docs.sh`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/caddy/macos/caddy-trust tests/caddy/macos/test-caddy-trust-runtime.sh README.md docs/caddy/macos/caddy.md
git commit -S -m "fix: Tighten Caddy Trust Verification" -m "- Refuse to treat a matching certificate name as sufficient trust state so stale or untrusted local CA entries do not produce false success.
- Update the README and Caddy documentation so the local HTTPS contract is explicit and matches the managed listener." 
```

### Task 3: Reconcile Podman Machines Without Unnecessary Restarts

**Files:**
- Modify: `scripts/podman/macos/podman-configure`
- Modify: `tests/podman/macos/test-podman-machine-runtime.sh`
- Modify: `docs/podman/macos/podman.md`

- [ ] **Step 1: Write the failing tests**

```bash
grep -q 'unchanged machine matches 8192 memory and 60 disk' tests/podman/macos/test-podman-machine-runtime.sh
grep -q 'PODMAN_MACHINE_NAME_DEFAULT' docs/podman/macos/podman.md
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `./tests/podman/macos/test-podman-machine-runtime.sh && ./tests/shared/shared/test-docs.sh`
Expected: FAIL because the no-op fixture does not yet reflect the managed config and the docs omit the managed machine-name config.

- [ ] **Step 3: Write minimal implementation**

```bash
machine_settings_need_update() {
  [[ "$MACHINE_STATE_BEFORE" != "$(desired_machine_state_summary)" ]]
}

if machine_settings_need_update; then
  prepare_machine_for_update
  apply_machine_preferences
  restore_machine_after_update
fi
```

```json
{"running":false,"cpus":4,"memory":8192,"disk_size":60,"rootful":false}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `./tests/podman/macos/test-podman-machine-runtime.sh && ./tests/shared/shared/test-docs.sh`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/podman/macos/podman-configure tests/podman/macos/test-podman-machine-runtime.sh docs/podman/macos/podman.md
git commit -S -m "fix: Avoid Unnecessary Podman Machine Restarts" -m "- Compare the managed Podman machine settings before applying mutable updates so no-op runs do not interrupt healthy machines.
- Document the managed machine-name config and tighten the runtime fixture so the tests reflect the documented defaults." 
```

### Task 4: Harden Podman Diagnose Output and Hermetic Coverage

**Files:**
- Modify: `scripts/podman/macos/podman-check`
- Modify: `tests/podman/macos/test-podman-diagnose-runtime.sh`
- Modify: `tests/podman/macos/test-podman.sh`
- Modify: `lib/shell/shared/common.sh`

- [ ] **Step 1: Write the failing tests**

```bash
grep -q 'safe_log_host_name' tests/podman/macos/test-podman-diagnose-runtime.sh
grep -q 'integration skipped unconditionally' tests/podman/macos/test-podman.sh
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `./tests/podman/macos/test-podman-diagnose-runtime.sh && ./tests/podman/macos/test-podman.sh`
Expected: FAIL because diagnose output still uses the unsafe host-name helper and the top-level Podman test still depends on local Podman state.

- [ ] **Step 3: Write minimal implementation**

```bash
REPORT_FILE="$output_dir/$(safe_log_host_name) Podman Diagnose-$timestamp.log"
```

```bash
echo "Podman checks passed (repository-only coverage)"
exit 0
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `./tests/podman/macos/test-podman-diagnose-runtime.sh && ./tests/podman/macos/test-podman.sh`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/podman/macos/podman-check tests/podman/macos/test-podman-diagnose-runtime.sh tests/podman/macos/test-podman.sh lib/shell/shared/common.sh
git commit -S -m "fix: Harden Podman Diagnose Logging and Coverage" -m "- Use the safe log host name for diagnose report filenames so unusual host names cannot produce invalid or misleading output paths.
- Keep the top-level Podman verification test hermetic so the repository suite reflects repository behaviour rather than local machine state." 
```

### Task 5: Restore Help Coverage and Align System Command Behaviour

**Files:**
- Modify: `scripts/system/macos/system-configure`
- Modify: `tests/shared/shared/test-all.sh`
- Modify: `tests/shared/shared/test-help.sh`
- Modify: `README.md`
- Modify: `docs/system/macos/system.md`

- [ ] **Step 1: Write the failing tests**

```bash
grep -q 'test-help.sh' tests/shared/shared/test-all.sh
grep -q '^if is_help_flag "\${1-}"; then$' scripts/system/macos/system-configure
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `./tests/shared/shared/test-help.sh && ./tests/shared/shared/test-all.sh`
Expected: FAIL because `system-configure` still rejects `--help` and `test-all.sh` does not yet include the help suite.

- [ ] **Step 3: Write minimal implementation**

```bash
if is_help_flag "${1-}"; then
  show_help "Usage: $(basename "$0")

Apply the managed macOS system settings.

Notes:
  - Loads the host-specific macOS system config when present, otherwise the shared macOS system config.
  - Requires sudo for the managed pmset change."
fi
```

```bash
"$ROOT/tests/shared/shared/test-help.sh"
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `./tests/shared/shared/test-help.sh && ./tests/shared/shared/test-all.sh`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/system/macos/system-configure tests/shared/shared/test-all.sh tests/shared/shared/test-help.sh README.md docs/system/macos/system.md
git commit -S -m "fix: Restore Help Coverage for macOS Commands" -m "- Add the standard help path to system-configure so it matches the rest of the managed command surface.
- Include the help checks in the main verification flow and update the system-setting documentation so the CLI contract stays visible and tested." 
```

### Task 6: Final Verification

**Files:**
- Modify: `README.md`
- Modify: `docs/caddy/macos/caddy.md`
- Modify: `docs/podman/macos/podman.md`
- Modify: `docs/system/macos/system.md`

- [ ] **Step 1: Run targeted verification**

Run: `./tests/caddy/macos/test-caddy-config.sh && ./tests/caddy/macos/test-caddy-runtime.sh && ./tests/caddy/macos/test-caddy-trust-runtime.sh && ./tests/podman/macos/test-podman-machine-runtime.sh && ./tests/podman/macos/test-podman-diagnose-runtime.sh && ./tests/podman/macos/test-podman.sh && ./tests/shared/shared/test-help.sh && ./tests/shared/shared/test-docs.sh`
Expected: PASS.

- [ ] **Step 2: Run full verification**

Run: `./tests/shared/shared/test-all.sh`
Expected: PASS with `All macOS checks passed`.

- [ ] **Step 3: Commit**

```bash
git add README.md docs/caddy/macos/caddy.md docs/podman/macos/podman.md docs/system/macos/system.md
git commit -S -m "docs: Align macOS Workflow Documentation with Verified Behaviour" -m "- Refresh the macOS workflow documentation after the review-driven fixes so the README and focused docs describe the verified command surface and config ownership clearly.
- Keep the final documentation update separate from the script fixes so the history stays easier to scan and audit." 
```
