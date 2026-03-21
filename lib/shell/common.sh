#!/usr/bin/env bash
set -euo pipefail

repo_root() {
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  cd "$script_dir/../.." && pwd
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
