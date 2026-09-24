#!/usr/bin/env bash
#
# Derive the floating major/minor tags for a stable semver release tag.
#
# Usage:
#   compute-floating-tags.sh v1.2.3
#   TAG=v1.2.3 compute-floating-tags.sh
#
# Writes GITHUB_OUTPUT-compatible lines to stdout:
#   major=v1
#   minor=v1.2
#
# Exit codes:
#   0  success
#   2  the input is not a stable X.Y.Z / vX.Y.Z release -- a prerelease, build
#      metadata, garbage, or nothing at all. Callers should treat this as
#      "skip", not "fail"; move-floating-tags.sh separately rejects an unset
#      TAG as a hard error before it ever gets here, so a forgotten input still
#      fails loudly where it matters.
#
# Pure string logic: no git, no network, no side effects.

set -euo pipefail

readonly EXIT_NOT_STABLE=2

tag="${1-${TAG-}}"

if [[ -z $tag ]]; then
  printf 'error: no tag supplied; pass one as the first argument or set TAG\n' >&2
  exit "$EXIT_NOT_STABLE"
fi

# Semver 2.0.0 forbids leading zeros in the numeric identifiers, so 0 is only
# ever spelled "0" and v01.2.3 is not a release tag.
if [[ ! $tag =~ ^(v?)(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
  printf 'error: %q is not a stable semver tag (expected X.Y.Z or vX.Y.Z)\n' "$tag" >&2
  exit "$EXIT_NOT_STABLE"
fi

# Keep whichever prefix style the release tag used, so v1.2.3 yields v1/v1.2
# while 1.2.3 yields 1/1.2.
prefix="${BASH_REMATCH[1]}"
major="${BASH_REMATCH[2]}"
minor="${BASH_REMATCH[3]}"

printf 'major=%s%s\n' "$prefix" "$major"
printf 'minor=%s%s.%s\n' "$prefix" "$major" "$minor"
