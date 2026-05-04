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
  COLOR_AMBER='\033[38;2;255;191;0m'
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

print_warning() {
  print_amber "$1"
}

print_skip() {
  printf '%s\n' "$1"
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

# Resolve one config file path relative to the repo root.
required_config_path() {
  local root_path="$1"
  local relative_path="$2"

  printf '%s/%s\n' "$root_path" "$relative_path"
}

# Load one required shell config file from the repo.
load_required_config() {
  local root_path="$1"
  local relative_path="$2"
  local config_path

  config_path="$(required_config_path "$root_path" "$relative_path")"
  [[ -f "$config_path" ]] || fail "Required config not found: $config_path"

  # shellcheck disable=SC1090
  source "$config_path"
}

# Fail when one required config value is unset or empty.
require_config_value() {
  local variable_name="$1"

  [[ -n "${!variable_name:-}" ]] || fail "Required config value is not set: $variable_name"
}

# Clear config-owned values before sourcing so missing keys cannot be satisfied
# accidentally by exported shell environment variables.
clear_config_values() {
  local variable_name

  for variable_name in "$@"; do
    unset "$variable_name"
  done
}

# Load the shared logging config used by active install and system workflows.
load_shared_logging_config() {
  local root_path="$1"

   clear_config_values \
    'ACTIVITY_LOG_TIMEZONE' \
    'ACTIVITY_LOG_ROOT_RELATIVE' \
    'ACTIVITY_LOG_SCOPE_SUBDIR' \
    'ACTIVITY_LOG_FILE_PREFIX' \
    'ACTIVITY_LOG_CSV_HEADER' \
    'ACTION_INSTALLED' \
    'ACTION_UPDATED' \
    'ACTION_REMOVED'
  load_required_config "$root_path" 'configs/shared/shared/logging.conf'
  require_config_value 'ACTIVITY_LOG_TIMEZONE'
  require_config_value 'ACTIVITY_LOG_ROOT_RELATIVE'
  require_config_value 'ACTIVITY_LOG_SCOPE_SUBDIR'
  require_config_value 'ACTIVITY_LOG_FILE_PREFIX'
  require_config_value 'ACTIVITY_LOG_CSV_HEADER'
  require_config_value 'ACTION_INSTALLED'
  require_config_value 'ACTION_UPDATED'
  require_config_value 'ACTION_REMOVED'
}

# Resolve the repository root from the path of a script inside
# scripts/<scope>/<application>/.
repo_root_from_script_path() {
  local script_path="$1"
  local script_dir

  script_dir="$(cd "$(command dirname "$script_path")" && pwd)"
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
  TZ="$ACTIVITY_LOG_TIMEZONE" date '+%Y%m%d'
}

# Return the current South Africa time for activity logging.
current_sa_time() {
  TZ="$ACTIVITY_LOG_TIMEZONE" date '+%H%M%S'
}

# Build the activity log file path for one OS and normalized host.
activity_log_file_path() {
  local root_path="$1"
  local os_name="$2"
  local host_name="$3"

  printf '%s/%s/%s/%s/%s-%s.csv\n' \
    "$root_path" \
    "$ACTIVITY_LOG_ROOT_RELATIVE" \
    "$os_name" \
    "$ACTIVITY_LOG_SCOPE_SUBDIR" \
    "$ACTIVITY_LOG_FILE_PREFIX" \
    "$host_name"
}

# Create the activity log file and header when it does not yet exist.
ensure_activity_log_file() {
  local log_file_path="$1"
  local log_dir

  log_dir="$(command dirname "$log_file_path")"
  command mkdir -p "$log_dir"

  if [[ ! -f "$log_file_path" ]]; then
    printf '%s\n' "$ACTIVITY_LOG_CSV_HEADER" > "$log_file_path"
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

# Replace or append one managed text block in a target file while preserving all
# unrelated user content.
upsert_managed_block() {
  local target_file_path="$1"
  local block_begin="$2"
  local block_end="$3"
  local block_content="$4"
  local target_dir
  local temp_file
  local line
  local inside_block
  local block_found

  target_dir="$(command dirname "$target_file_path")"
  command mkdir -p "$target_dir"
  [[ -f "$target_file_path" ]] || : > "$target_file_path"

  temp_file="$(mktemp)"
  inside_block='0'
  block_found='0'

  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" == "$block_begin" ]]; then
      if [[ "$block_found" == '0' ]]; then
        printf '%s\n%s\n%s\n' "$block_begin" "$block_content" "$block_end" >> "$temp_file"
        block_found='1'
      fi
      inside_block='1'
      continue
    fi

    if [[ "$inside_block" == '1' ]]; then
      if [[ "$line" == "$block_end" ]]; then
        inside_block='0'
      fi
      continue
    fi

    printf '%s\n' "$line" >> "$temp_file"
  done < "$target_file_path"

  if [[ "$block_found" == '0' ]]; then
    if [[ -s "$temp_file" ]]; then
      printf '\n' >> "$temp_file"
    fi
    printf '%s\n%s\n%s\n' "$block_begin" "$block_content" "$block_end" >> "$temp_file"
  fi

  command mv "$temp_file" "$target_file_path"
}
