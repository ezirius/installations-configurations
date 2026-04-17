#!/usr/bin/env bash

assert_contains() {
  local file="$1"
  local needle="$2"
  local message="$3"

  if ! grep -Fq -- "$needle" "$file"; then
    printf 'assertion failed: %s\nmissing: %s\nfile: %s\n' "$message" "$needle" "$file" >&2
    exit 1
  fi
}

assert_not_contains() {
  local file="$1"
  local needle="$2"
  local message="$3"

  if grep -Fq -- "$needle" "$file"; then
    printf 'assertion failed: %s\nunexpected: %s\nfile: %s\n' "$message" "$needle" "$file" >&2
    exit 1
  fi
}

create_zero_commit_brew_repo() {
  local root="$1"
  local repo_dir="$2"
  local script_name="$3"

  mkdir -p "$repo_dir/scripts/brew/macos" "$repo_dir/lib/shell/shared" "$repo_dir/config/brew/macos" "$repo_dir/config/repo/shared" "$repo_dir/config/podman/macos"
  cp "$root/scripts/brew/macos/$script_name" "$repo_dir/scripts/brew/macos/$script_name"
  cp "$root/lib/shell/shared/common.sh" "$repo_dir/lib/shell/shared/common.sh"
  cp "$root/lib/shell/shared/homebrew.sh" "$repo_dir/lib/shell/shared/homebrew.sh"
  cp "$root/config/brew/macos/brew-settings-shared.conf" "$repo_dir/config/brew/macos/brew-settings-shared.conf"
  cp "$root/config/brew/macos/brew-packages-shared.Brewfile" "$repo_dir/config/brew/macos/brew-packages-shared.Brewfile"
  cp "$root/config/repo/shared/repo-settings-shared.conf" "$repo_dir/config/repo/shared/repo-settings-shared.conf"
  cp "$root/config/podman/macos/podman-runtime-settings-shared.conf" "$repo_dir/config/podman/macos/podman-runtime-settings-shared.conf"
  chmod +x "$repo_dir/scripts/brew/macos/$script_name"
  git -C "$repo_dir" init -b main >/dev/null
}
