#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

export HOME="$WORKDIR/home"
mkdir -p "$HOME"

source "$ROOT/lib/shell/common.sh"

INSTALLATIONS_CONFIGURATIONS_LOG_DIR="$HOME/Documents/Ezirius/Systems/Installations and Configurations/Computers"
HOST_NAME="$(detect_log_host_name)"
OPEN_LOG="$INSTALLATIONS_CONFIGURATIONS_LOG_DIR/$HOST_NAME Installations and Configurations-20260322---------.csv"
CLOSED_LOG="$INSTALLATIONS_CONFIGURATIONS_LOG_DIR/$HOST_NAME Installations and Configurations-20260320-20260321.csv"

mkdir -p "$INSTALLATIONS_CONFIGURATIONS_LOG_DIR"

initialize_change_log "scripts/macos/test-logging"
test -f "$INSTALLATIONS_CONFIGURATIONS_LOG_FILE"
grep -q '^Date,Time,Username,Type,Script,Item,Change,Path,Details$' "$INSTALLATIONS_CONFIGURATIONS_LOG_FILE"

log_change "Configuration" "CSV sample" "Created" "$HOME/sample" 'created "sample", with commas'
grep -q '"created ""sample"", with commas"$' "$INSTALLATIONS_CONFIGURATIONS_LOG_FILE"

printf '%s\n' 'Date,Time,Username,Type,Script,Item,Change,Path,Details' > "$OPEN_LOG"
initialize_change_log "scripts/macos/test-logging"
test "$INSTALLATIONS_CONFIGURATIONS_LOG_FILE" = "$OPEN_LOG"

rm -f "$OPEN_LOG"
touch "$CLOSED_LOG"
initialize_change_log "scripts/macos/test-logging"
test "$INSTALLATIONS_CONFIGURATIONS_LOG_FILE" != "$CLOSED_LOG"
test -f "$INSTALLATIONS_CONFIGURATIONS_LOG_FILE"

echo "Logging checks passed"
