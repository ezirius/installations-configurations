#!/usr/bin/env bash
set -euo pipefail

preferred_python3_command() {
  local brew_python=""

  load_homebrew_shellenv
  if command -v brew >/dev/null 2>&1; then
    brew_python="$(brew --prefix)/bin/python3"
    if [[ -x "$brew_python" ]]; then
      printf '%s\n' "$brew_python"
      return 0
    fi
  fi

  if command -v python3 >/dev/null 2>&1; then
    command -v python3
    return 0
  fi

  fail "python3 is required but was not found. Install Python 3 or ensure Homebrew Python is available."
}

parse_brewfile_entries() {
  local brewfile_path="$1"
  local python3_command

  python3_command="$(preferred_python3_command)"
  "$python3_command" - "$brewfile_path" <<'PY'
import pathlib
import re
import sys

brewfile = pathlib.Path(sys.argv[1]).read_text().splitlines()
pattern = re.compile(r'''^(brew|cask)\s+(['"])([^'"]+)\2''')

for line in brewfile:
    match = pattern.match(line.strip())
    if match:
        print(f"{match.group(1)}|{match.group(3)}")
PY
}

write_brewfile_entries() {
  local brewfile_path="$1"
  local entries_file="$2"

  if [[ ! -f "$brewfile_path" ]]; then
    echo "Brewfile not found: $brewfile_path" >&2
    return 1
  fi

  parse_brewfile_entries "$brewfile_path" > "$entries_file"
}

for_each_brew_entry() {
  local entries_file="$1"
  local callback_name="$2"
  local entry_type
  local entry_name

  while IFS='|' read -r entry_type entry_name; do
    [[ -n "$entry_name" ]] || continue
    "$callback_name" "$entry_type" "$entry_name"
  done < "$entries_file"
}

snapshot_brew_entries_state() {
  local entries_file="$1"
  local output_file="$2"
  local entry_type
  local entry_name
  local version_line

  : > "$output_file"

  while IFS='|' read -r entry_type entry_name; do
    [[ -n "$entry_name" ]] || continue
    version_line=""

    if [[ "$entry_type" == "brew" ]]; then
      version_line="$(brew list --versions "$entry_name" 2>/dev/null || true)"
    elif [[ "$entry_type" == "cask" ]]; then
      version_line="$(brew list --cask --versions "$entry_name" 2>/dev/null || true)"
    else
      echo "Unsupported Brewfile entry type: $entry_type" >&2
      return 1
    fi

    if [[ -n "$version_line" ]]; then
      printf '%s|%s|installed|%s\n' "$entry_type" "$entry_name" "$version_line" >> "$output_file"
    else
      printf '%s|%s|missing|\n' "$entry_type" "$entry_name" >> "$output_file"
    fi
  done < "$entries_file"
}

report_brew_install_state_changes() {
  local before_file="$1"
  local after_file="$2"
  local python3_command="$3"

  "$python3_command" - "$before_file" "$after_file" <<'PY'
from pathlib import Path
import sys

def read_state(path):
    rows = {}
    for line in Path(path).read_text().splitlines():
        entry_type, name, state, version = line.split("|", 3)
        rows[(entry_type, name)] = {"state": state, "version": version}
    return rows

before = read_state(sys.argv[1])
after = read_state(sys.argv[2])

for (entry_type, name), after_data in after.items():
    before_data = before[(entry_type, name)]
    if before_data["state"] == "missing" and after_data["state"] == "installed":
        print(f"{entry_type}|{name}|Installed")
PY
}

report_brew_upgrade_state_changes() {
  local before_file="$1"
  local after_file="$2"
  local python3_command="$3"

  "$python3_command" - "$before_file" "$after_file" <<'PY'
from pathlib import Path
import sys

def read_state(path):
    rows = {}
    for line in Path(path).read_text().splitlines():
        entry_type, name, state, version = line.split("|", 3)
        rows[(entry_type, name)] = {"state": state, "version": version}
    return rows

before = read_state(sys.argv[1])
after = read_state(sys.argv[2])

for (entry_type, name), after_data in after.items():
    before_data = before[(entry_type, name)]
    if before_data["state"] == "installed" and after_data["state"] == "installed" and before_data["version"] != after_data["version"]:
        print(f"{name}|Upgraded")
PY
}

for_each_managed_brewfile() {
  local callback_name="$1"
  local explicit_brewfile="${2:-}"
  local selected_brewfile

  if [[ -n "$explicit_brewfile" ]]; then
    "$callback_name" "$explicit_brewfile"
    return 0
  fi

  selected_brewfile="$(preferred_platform_config_path "config/brew" "brew-packages" "Brewfile")"
  "$callback_name" "$selected_brewfile"
}

load_homebrew_shellenv() {
  load_repo_config
  if [[ -x "$REPO_HOMEBREW_PRIMARY_PREFIX/bin/brew" ]]; then
    eval "$("$REPO_HOMEBREW_PRIMARY_PREFIX/bin/brew" shellenv)"
  elif [[ -x "$REPO_HOMEBREW_SECONDARY_PREFIX/bin/brew" ]]; then
    eval "$("$REPO_HOMEBREW_SECONDARY_PREFIX/bin/brew" shellenv)"
  fi
}

require_homebrew() {
  load_homebrew_shellenv
  if ! command -v brew >/dev/null 2>&1; then
    fail "Homebrew is not installed"
  fi
}

homebrew_root_path() {
  load_homebrew_shellenv
  load_repo_config

  if command -v brew >/dev/null 2>&1; then
    brew --prefix
  elif [[ -d "$REPO_HOMEBREW_PRIMARY_PREFIX" ]]; then
    printf '%s\n' "$REPO_HOMEBREW_PRIMARY_PREFIX"
  elif [[ -d "$REPO_HOMEBREW_SECONDARY_PREFIX" ]]; then
    printf '%s\n' "$REPO_HOMEBREW_SECONDARY_PREFIX"
  else
    printf '%s\n' "$REPO_HOMEBREW_PRIMARY_PREFIX"
  fi
}
