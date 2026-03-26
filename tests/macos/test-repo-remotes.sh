#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

assert_git_value() {
  local repo_path="$1"
  local key="$2"
  local expected="$3"
  local actual

  actual="$(git -C "$repo_path" config --local --get "$key" || true)"
  if [[ "$actual" != "$expected" ]]; then
    printf 'assertion failed: %s %s\nexpected: %s\nactual:   %s\n' "$repo_path" "$key" "$expected" "$actual" >&2
    exit 1
  fi
}

assert_git_value "$ROOT" remote.origin.url 'git@github-maldoria-installations-configurations:ezirius/installations-configurations.git'
assert_git_value "$ROOT/../opencode-container" remote.origin.url 'git@github-maldoria-opencode-container:ezirius/opencode-container.git'
assert_git_value "$ROOT/../honcho-container" remote.origin.url 'git@github-maldoria-honcho-container:ezirius/honcho-container.git'
assert_git_value "$ROOT/../hermes-agent-container" remote.origin.url 'git@github-maldoria-hermes-agent-container:ezirius/hermes-agent-container.git'
assert_git_value "$ROOT/../openclaw-container" remote.origin.url 'git@github-maldoria-openclaw-container:ezirius/openclaw-container.git'

assert_git_value "$ROOT/../opencode-container" branch.main.remote 'origin'
assert_git_value "$ROOT/../honcho-container" branch.main.remote 'origin'
assert_git_value "$ROOT/../hermes-agent-container" branch.main.remote 'origin'
assert_git_value "$ROOT/../openclaw-container" branch.main.remote 'origin'

echo "Repo remote checks passed"
