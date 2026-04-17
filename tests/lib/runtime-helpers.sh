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
