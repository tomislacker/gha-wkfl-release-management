#!/usr/bin/env bash
# Rewrites the README usage examples so every `uses:` reference to this
# repository carries the literal commit SHA and tag of the latest release, and
# the actions/checkout line shown alongside them matches the pin the reusable
# workflow itself uses. Idempotent; run by the Release workflow after each
# release, and usable by hand: TAG=v1.2.3 SHA=<40-hex> ./update-readme-pins.sh
set -euo pipefail

TAG="${TAG:-}"
SHA="${SHA:-}"
README_FILE="${README_FILE:-README.md}"
WORKFLOW_FILE="${WORKFLOW_FILE:-.github/workflows/release-management.yml}"
REPO_SLUG="${REPO_SLUG:-tomislacker/gha-wkfl-release-management}"

err() {
  printf 'error: %s\n' "$*" >&2
}

if [[ ! $TAG =~ ^v?(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
  err "TAG must be a stable semver tag, got $(printf '%q' "$TAG")"
  exit 1
fi
if [[ ! $SHA =~ ^[0-9a-f]{40}$ ]]; then
  err "SHA must be a 40-character lowercase commit SHA, got $(printf '%q' "$SHA")"
  exit 1
fi
if [[ ! $REPO_SLUG =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]; then
  err "REPO_SLUG must be an owner/repo slug, got $(printf '%q' "$REPO_SLUG")"
  exit 1
fi
if [[ ! -f $README_FILE ]]; then
  err "no such file: $README_FILE"
  exit 1
fi

before="$(cat "$README_FILE")"
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

# Every `uses:` reference to this repository -- with or without a workflow
# path suffix, placeholder or already pinned -- gets the release's SHA + tag.
sed -E "s|(uses: ${REPO_SLUG}[^@[:space:]]*)@[^[:space:]]+.*$|\1@${SHA} # ${TAG}|" \
  "$README_FILE" >"$tmp"

# Keep the actions/checkout example line identical to the pin the reusable
# workflow itself uses, so the documented pin is always a real, current one.
if [[ -f $WORKFLOW_FILE ]]; then
  checkout_pin="$(grep -oE 'actions/checkout@[0-9a-f]{40} # v[0-9]+\.[0-9]+\.[0-9]+' \
    "$WORKFLOW_FILE" | head -n 1 || true)"
  if [[ -n $checkout_pin ]]; then
    sed -E -i "s|actions/checkout@[^[:space:]]+.*$|${checkout_pin}|" "$tmp"
  fi
fi

# cat instead of mv so the README keeps its permissions (mktemp files are 0600)
cat "$tmp" >"$README_FILE"

if [[ $before == "$(cat "$README_FILE")" ]]; then
  echo "README pins already current"
else
  echo "README pins updated to ${TAG} (${SHA})"
fi
