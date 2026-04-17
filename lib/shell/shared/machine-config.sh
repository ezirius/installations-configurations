#!/usr/bin/env bash
set -euo pipefail

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
