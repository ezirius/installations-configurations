# Restore macOS System Settings Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restore the three historical macOS system settings as a standalone feature that fits the current reduced repo structure and standards.

**Architecture:** Reintroduce one macOS-scoped config file, one standalone configure script, one focused doc, and two tests, while keeping the feature outside the current Brew umbrella. Keep defaults in config, keep control flow in the script, and avoid restoring the old logging system.

**Tech Stack:** Bash, macOS `defaults`, `pmset`, shell tests, markdown docs.

---

### Task 1: Restore Config And Script

**Files:**
- Create: `config/system/shared-macos.conf`
- Create: `scripts/macos/system-configure`
- Test: `tests/macos/test-system-config.sh`

- [ ] **Step 1: Write failing shape tests for the restored system feature**
- [ ] **Step 2: Run `tests/macos/test-system-config.sh` and verify it fails**
- [ ] **Step 3: Restore the config file and standalone script without the old logging hooks**
- [ ] **Step 4: Re-run `tests/macos/test-system-config.sh` and verify it passes**

### Task 2: Restore Runtime Coverage

**Files:**
- Create: `tests/macos/test-system-runtime.sh`

- [ ] **Step 1: Write the runtime test covering shared config, host override, portable `pmset -c`, non-portable `pmset -a`, and no-op behaviour**
- [ ] **Step 2: Run `tests/macos/test-system-runtime.sh` and verify it fails**
- [ ] **Step 3: Adjust the restored script only as needed to satisfy the runtime contract**
- [ ] **Step 4: Re-run `tests/macos/test-system-runtime.sh` and verify it passes**

### Task 3: Restore User-Facing Docs And Suite Wiring

**Files:**
- Create: `docs/macos/system.md`
- Modify: `README.md`
- Modify: `tests/macos/test-docs.sh`
- Modify: `tests/macos/test-help.sh`
- Modify: `tests/macos/test-args.sh`
- Modify: `tests/macos/test-all.sh`

- [ ] **Step 1: Update the docs/tests to require the restored standalone system-settings feature**
- [ ] **Step 2: Run the affected docs/help/args tests and verify they fail**
- [ ] **Step 3: Restore the doc and README mention, and add the restored tests to the aggregate suite**
- [ ] **Step 4: Re-run the affected docs/help/args tests and verify they pass**

### Task 4: Final Verification

**Files:**
- Verify: `tests/macos/test-all.sh`

- [ ] **Step 1: Run `tests/macos/test-all.sh`**
- [ ] **Step 2: Verify it ends with `All macOS checks passed`**
