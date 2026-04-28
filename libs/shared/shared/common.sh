#!/usr/bin/env bash

# Shared shell helpers for scripts that run on both macOS and Linux.
#
# This file intentionally keeps only generic helpers that are useful across
# multiple scripts. Script-specific workflow logic should remain in the
# calling script.
#
# Keep here only code that is plausibly reusable across more than one active
# script. Install-only workflow behavior should stay in the calling script.
#
# The current active users are the Brew install workflow, the shared bootstrap
# workflow, the macOS download workflow, and the macOS system configuration
# workflow.

## Color and error helpers

if [[ -t 1 ]]; then
  COLOR_GREEN='\033[32m'
  COLOR_AMBER='\033[33m'
  COLOR_RED='\033[31m'
  COLOR_RESET='\033[0m'
else
  COLOR_GREEN=''
  COLOR_AMBER=''
  COLOR_RED=''
  COLOR_RESET=''
fi

print_green() {
  printf '%b%s%b\n' "$COLOR_GREEN" "$1" "$COLOR_RESET"
}

print_amber() {
  printf '%b%s%b\n' "$COLOR_AMBER" "$1" "$COLOR_RESET"
}

print_red() {
  printf '%b%s%b\n' "$COLOR_RED" "$1" "$COLOR_RESET" >&2
}

# Print a red error message and exit non-zero.
fail() {
  print_red "ERROR: $1"
  exit 1
}

# Print help text and exit successfully.
show_help() {
  printf '%s\n' "$1"
  exit 0
}

# Return success when the first argument is a standard help flag.
is_help_flag() {
  [[ "${1-}" == "-h" || "${1-}" == "--help" ]]
}

# Resolve the repository root from the path of a script inside
# scripts/<scope>/<application>/.
repo_root_from_script_path() {
  local script_path="$1"
  local script_dir

  script_dir="$(cd "$(dirname "$script_path")" && pwd)"
  cd "$script_dir/../../.." && pwd
}

# Map the runtime OS to the repository OS scope token.
detect_os() {
  case "$(uname -s)" in
    Darwin)
      printf 'macos\n'
      ;;
    Linux)
      printf 'linux\n'
      ;;
    *)
      fail "Unsupported OS: $(uname -s)"
      ;;
  esac
}

# Normalize host and username tokens to the repository filename contract.
normalize_name() {
  printf '%s' "$1" \
    | tr '[:upper:]' '[:lower:]' \
    | tr -c 'a-z0-9' '-' \
    | sed -E 's/^-+//; s/-+$//; s/-+/-/g'
}

# Detect the current host, trimming everything after the first dot.
detect_host() {
  local host_name

  host_name="$(hostname)"
  host_name="${host_name%%.*}"
  normalize_name "$host_name"
}

# Detect the current normalized username using whoami.
detect_username() {
  normalize_name "$(whoami)"
}

# Load Homebrew into PATH when installed in a standard prefix.
load_homebrew_shellenv() {
  if command -v brew >/dev/null 2>&1; then
    return 0
  fi

  if [[ "${HOMEBREW_SKIP_STANDARD_PREFIX_SHELLENV:-0}" == "1" ]]; then
    return 0
  fi

  if [[ -x /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [[ -x /usr/local/bin/brew ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
  fi
}

# Return the current South Africa date for activity logging.
current_sa_date() {
  TZ='Africa/Johannesburg' date '+%Y%m%d'
}

# Return the current South Africa time for activity logging.
current_sa_time() {
  TZ='Africa/Johannesburg' date '+%H%M%S'
}

# Build the activity log file path for one OS and normalized host.
activity_log_file_path() {
  local root_path="$1"
  local os_name="$2"
  local host_name="$3"

  printf '%s/logs/%s/shared/installations-and-configurations-%s.csv\n' "$root_path" "$os_name" "$host_name"
}

# Create the activity log file and header when it does not yet exist.
ensure_activity_log_file() {
  local log_file_path="$1"
  local log_dir

  log_dir="$(dirname "$log_file_path")"
  mkdir -p "$log_dir"

  if [[ ! -f "$log_file_path" ]]; then
    printf 'date,time,host,action,application,version\n' > "$log_file_path"
  fi
}

# Append one activity row to the shared CSV log.
append_activity_log_row() {
  local log_file_path="$1"
  local host_name="$2"
  local action_name="$3"
  local application_name="$4"
  local version_name="$5"

  ensure_activity_log_file "$log_file_path"
  printf '%s,%s,%s,%s,%s,%s\n' \
    "$(current_sa_date)" \
    "$(current_sa_time)" \
    "$host_name" \
    "$action_name" \
    "$application_name" \
    "$version_name" >> "$log_file_path"
}
