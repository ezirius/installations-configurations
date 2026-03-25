#!/usr/bin/env bash
set -euo pipefail

INSTALLATIONS_CONFIGURATIONS_LOG_DIR_DEFAULT="$HOME/Documents/Ezirius/Systems/Installations and Configurations/Computers"

INSTALLATIONS_CONFIGURATIONS_LOG_FILE=""
INSTALLATIONS_CONFIGURATIONS_LOG_SCRIPT=""

repo_root() {
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  cd "$script_dir/../.." && pwd
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

load_homebrew_shellenv() {
  if [[ -x /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [[ -x /usr/local/bin/brew ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
  fi
}

require_macos() {
  if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "This script is for macOS only"
    exit 1
  fi
}

require_clt() {
  if ! xcode-select -p >/dev/null 2>&1; then
    echo "Xcode Command Line Tools are missing"
    echo "Run: xcode-select --install"
    exit 1
  fi
}

require_homebrew() {
  load_homebrew_shellenv
  if ! command -v brew >/dev/null 2>&1; then
    echo "Homebrew is not installed"
    exit 1
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

current_date() {
  date '+%Y%m%d'
}

current_time() {
  date '+%H%M%S'
}

homebrew_root_path() {
  load_homebrew_shellenv

  if command -v brew >/dev/null 2>&1; then
    brew --prefix
  elif [[ -d /opt/homebrew ]]; then
    printf '%s\n' '/opt/homebrew'
  elif [[ -d /usr/local ]]; then
    printf '%s\n' '/usr/local'
  else
    printf '%s\n' '/opt/homebrew'
  fi
}

detect_log_host_name() {
  local host_name

  if command -v scutil >/dev/null 2>&1 && scutil --get ComputerName >/dev/null 2>&1; then
    host_name="$(scutil --get ComputerName)"
  else
    host_name="$(hostname -s)"
  fi

  printf '%s' "${host_name%%.*}"
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
  local script_name="$1"
  local log_dir="${INSTALLATIONS_CONFIGURATIONS_LOG_DIR:-$INSTALLATIONS_CONFIGURATIONS_LOG_DIR_DEFAULT}"
  local host_name
  local open_log_file=""
  local current_log_file
  local candidate
  local candidate_mtime
  local newest_mtime=""

  shopt -s nullglob

  INSTALLATIONS_CONFIGURATIONS_LOG_SCRIPT="$script_name"
  host_name="$(detect_log_host_name)"

  mkdir -p "$log_dir"

  for candidate in "$log_dir"/"$host_name Installations and Configurations-"*.csv; do
    [[ "$candidate" == *"---------.csv" ]] || continue
    candidate_mtime="$(file_mtime "$candidate")"

    if [[ -z "$newest_mtime" || "$candidate_mtime" -gt "$newest_mtime" ]]; then
      newest_mtime="$candidate_mtime"
      open_log_file="$candidate"
    fi
  done

  shopt -u nullglob

  if [[ -n "$open_log_file" ]]; then
    INSTALLATIONS_CONFIGURATIONS_LOG_FILE="$open_log_file"
    return
  fi

  current_log_file="$log_dir/$host_name Installations and Configurations-$(current_date)---------.csv"
  INSTALLATIONS_CONFIGURATIONS_LOG_FILE="$current_log_file"

  if [[ ! -f "$INSTALLATIONS_CONFIGURATIONS_LOG_FILE" ]]; then
    printf '%s\n' 'Date,Time,Username,Type,Script,Item,Change,Path,Details' > "$INSTALLATIONS_CONFIGURATIONS_LOG_FILE"
  fi
}

log_change() {
  local change_type="$1"
  local item="$2"
  local change_name="$3"
  local path_value="$4"
  local details="$5"
  local username="${USER:-$(id -un 2>/dev/null || printf 'unknown')}"
  local log_date
  local log_time

  [[ -n "$INSTALLATIONS_CONFIGURATIONS_LOG_FILE" ]] || fail "Change log not initialized"

  log_date="$(current_date)"
  log_time="$(current_time)"

  printf '%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
    "$(csv_escape "$log_date")" \
    "$(csv_escape "$log_time")" \
    "$(csv_escape "$username")" \
    "$(csv_escape "$change_type")" \
    "$(csv_escape "$INSTALLATIONS_CONFIGURATIONS_LOG_SCRIPT")" \
    "$(csv_escape "$item")" \
    "$(csv_escape "$change_name")" \
    "$(csv_escape "$path_value")" \
    "$(csv_escape "$details")" \
    >> "$INSTALLATIONS_CONFIGURATIONS_LOG_FILE"
}

require_command() {
  local command_name="$1"
  local install_hint="${2:-}"

  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "Required command is missing: $command_name" >&2
    if [[ -n "$install_hint" ]]; then
      echo "$install_hint" >&2
    fi
    exit 1
  fi
}

read_machine_config_value() {
  local config_file="$1"
  local key="$2"

  python3 - "$config_file" "$key" <<'PY'
import configparser
import pathlib
import sys

config_path = pathlib.Path(sys.argv[1])
key = sys.argv[2]

parser = configparser.ConfigParser()
parser.read(config_path)

if not parser.has_section("machine") or not parser.has_option("machine", key):
    raise SystemExit(1)

print(parser.get("machine", key))
PY
}
