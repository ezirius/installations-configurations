#!/usr/bin/env bash
set -euo pipefail

INSTALLATIONS_CONFIGURATIONS_CONFIG_LOADED_REPO="0"

source_shell_config() {
  local config_path="$1"
  [[ -f "$config_path" ]] || fail "Config file not found: $config_path"
  # shellcheck disable=SC1090
  source "$config_path"
}

load_repo_config() {
  if [[ "$INSTALLATIONS_CONFIGURATIONS_CONFIG_LOADED_REPO" == "1" ]]; then
    return 0
  fi

  source_shell_config "$(repo_root)/config/repo/shared.conf"
  INSTALLATIONS_CONFIGURATIONS_CONFIG_LOADED_REPO="1"
}

repo_root() {
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  cd "$script_dir/../.." && pwd
}

platform_key() {
  load_repo_config
  case "$(uname -s)" in
    Darwin)
      printf '%s\n' "$REPO_PLATFORM_DARWIN"
      ;;
    Linux)
      printf '%s\n' "$REPO_PLATFORM_LINUX"
      ;;
    *)
      fail "Unsupported platform: $(uname -s)"
      ;;
  esac
}

raw_host_name() {
  local host_name

  if command -v scutil >/dev/null 2>&1 && scutil --get ComputerName >/dev/null 2>&1; then
    host_name="$(scutil --get ComputerName)"
  else
    host_name="$(hostname -s)"
  fi

  printf '%s\n' "${host_name%%.*}"
}

normalized_host_name() {
  normalize_name "$(raw_host_name)"
}

normalize_name() {
  printf '%s' "$1" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//'
}

shared_platform_config_path() {
  local relative_dir="$1"
  local extension="$2"
  load_repo_config
  printf "$REPO_SHARED_PLATFORM_PATTERN\n" "$(repo_root)" "$relative_dir" "$(platform_key)" "$extension"
}

shared_cross_platform_config_path() {
  local relative_dir="$1"
  local extension="$2"
  load_repo_config
  printf "$REPO_SHARED_SHARED_PATTERN\n" "$(repo_root)" "$relative_dir" "$extension"
}

host_platform_config_path() {
  local relative_dir="$1"
  local extension="$2"
  load_repo_config
  printf "$REPO_HOST_PLATFORM_PATTERN\n" "$(repo_root)" "$relative_dir" "$(normalized_host_name)" "$(platform_key)" "$extension"
}

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
pattern = re.compile(r'^(brew|cask)\s+"([^"]+)"')

for line in brewfile:
    match = pattern.match(line.strip())
    if match:
        print(f"{match.group(1)}|{match.group(2)}")
PY
}

canonicalize_path() {
  local input_path="$1"

  if [[ -d "$input_path" ]]; then
    (
      cd "$input_path"
      pwd
    )
  else
    fail "Directory not found: $input_path"
  fi
}

require_git_repo_path() {
  local repo_path="$1"

  git -C "$repo_path" rev-parse --show-toplevel >/dev/null 2>&1 \
    || fail "Not a git repository: $repo_path"
}

require_clean_pushed_repo_state() {
  local repo_path="$1"
  local command_name="$2"
  local upstream_ref
  local ahead_count
  local behind_count

  require_git_repo_path "$repo_path"

  if [[ -n "$(git -C "$repo_path" status --porcelain)" ]]; then
    fail "Repository has uncommitted changes. Commit and push before running $command_name."
  fi

  upstream_ref="$(git -C "$repo_path" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null || true)"
  [[ -n "$upstream_ref" ]] || fail "Current branch has no upstream. Push the branch before running $command_name."

  IFS=$' \t' read -r behind_count ahead_count < <(git -C "$repo_path" rev-list --left-right --count "$upstream_ref...HEAD" 2>/dev/null || printf '0 0')
  if [[ "$behind_count" != "0" ]]; then
    fail "Current branch is behind or diverged from upstream. Pull or reconcile before running $command_name."
  fi
  if [[ "$ahead_count" != "0" ]]; then
    fail "Current branch has unpushed commits. Push before running $command_name."
  fi
}

load_homebrew_shellenv() {
  load_repo_config
  if [[ -x "$REPO_HOMEBREW_PRIMARY_PREFIX/bin/brew" ]]; then
    eval "$("$REPO_HOMEBREW_PRIMARY_PREFIX/bin/brew" shellenv)"
  elif [[ -x "$REPO_HOMEBREW_SECONDARY_PREFIX/bin/brew" ]]; then
    eval "$("$REPO_HOMEBREW_SECONDARY_PREFIX/bin/brew" shellenv)"
  fi
}

require_macos() {
  if [[ "$(uname -s)" != "Darwin" ]]; then
    fail "This script is for macOS only"
  fi
}

require_clt() {
  if ! xcode-select -p >/dev/null 2>&1; then
    fail "Xcode Command Line Tools are missing. Run: xcode-select --install"
  fi
}

require_homebrew() {
  load_homebrew_shellenv
  if ! command -v brew >/dev/null 2>&1; then
    fail "Homebrew is not installed"
  fi
}

fail() {
  echo "$1" >&2
  exit 1
}

usage_error() {
  echo "Usage: $1" >&2
  exit 1
}

is_help_flag() {
  [[ "${1-}" == "-h" || "${1-}" == "--help" ]]
}

show_help() {
  printf '%s\n' "$1"
  exit 0
}

prompt_yes_no() {
  local prompt_message="$1"
  local response=""

  while true; do
    printf '%s [y/N]: ' "$prompt_message"
    if ! IFS= read -r response; then
      return 2
    fi

    case "$response" in
      [Yy]|[Yy][Ee][Ss])
        return 0
        ;;
      ""|[Nn]|[Nn][Oo])
        return 1
        ;;
      *)
        printf 'Please answer yes or no.\n'
        ;;
    esac
  done
}

current_date() {
  date '+%Y%m%d'
}

current_time() {
  date '+%H%M%S'
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

detect_log_host_name() {
  printf '%s' "$(raw_host_name)"
}

safe_log_host_name() {
  local host_name
  host_name="$(detect_log_host_name)"
  host_name="${host_name//\//-}"
  printf '%s' "$host_name"
}

file_mtime() {
  local file_path="$1"

  if stat -f '%m' "$file_path" >/dev/null 2>&1; then
    stat -f '%m' "$file_path"
  else
    stat -c '%Y' "$file_path"
  fi
}

csv_escape() {
  local value="$1"

  value="${value//$'\n'/ }"
  value="${value//$'\r'/ }"
  value="${value//\"/\"\"}"

  printf '"%s"' "$value"
}

initialize_change_log() {
  :
}

log_change() {
  :
}

require_command() {
  local command_name="$1"
  local install_hint="${2:-}"

  if ! command -v "$command_name" >/dev/null 2>&1; then
    printf 'Required command is missing: %s\n' "$command_name" >&2
    if [[ -n "$install_hint" ]]; then
      printf '%s\n' "$install_hint" >&2
    fi
    exit 1
  fi
}

read_machine_config_value() {
  local config_file="$1"
  local key="$2"
  local python3_command

  python3_command="$(preferred_python3_command)"

  "$python3_command" - "$config_file" "$key" <<'PY'
import configparser
import pathlib
import sys

config_path = pathlib.Path(sys.argv[1])
key = sys.argv[2]

parser = configparser.ConfigParser(interpolation=None)
parser.read(config_path)

if not parser.has_section("machine") or not parser.has_option("machine", key):
    raise SystemExit(1)

print(parser.get("machine", key))
PY
}
