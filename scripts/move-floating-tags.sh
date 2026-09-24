#!/usr/bin/env bash
#
# Force-move the floating major/minor tags (v1, v1.2) onto the commit that a
# full release tag (v1.2.3) points at, then push them.
#
# Environment:
#   TAG      (required) full release tag, e.g. v1.2.3
#   REMOTE   (default: origin) remote to fetch the tag from and push to. This
#            MUST be a trusted static value -- never a workflow input, a branch
#            name, or anything else an untrusted contributor can influence.
#   DRY_RUN  (default: false) when true, do everything except writing anything.
#            "true"/"yes"/"1" (any case) enable it, "false"/"no"/"0"/"" disable
#            it, and anything else is a hard error rather than a silent push.
#
# Must be run inside a checkout of the repository that owns the tags, with
# credentials that are allowed to push. Re-running with the same TAG is a
# no-op success.
#
# The remote is authoritative. The release tag is always re-fetched (a stale
# local tag on a long-lived self-hosted runner must never shadow it), and each
# floating tag only moves when TAG is the highest stable release the remote
# knows under that floating prefix -- so a backport released after a newer
# minor cannot silently drag a floating tag backwards.
#
# Exits 0 (with an explanatory log line) when TAG is not a stable release tag,
# so that prerelease tags simply skip instead of failing the job.

set -euo pipefail

readonly EXIT_NOT_STABLE=2

# A stable semver release: no prerelease, no build metadata, no leading zeros.
readonly STABLE_RE='^v?(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$'

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

TAG="${TAG-}"
REMOTE="${REMOTE:-origin}"
DRY_RUN="${DRY_RUN:-false}"

if [[ -z $TAG ]]; then
  printf 'error: TAG is required\n' >&2
  exit 1
fi

# git parses a leading-dash operand as an option, so a remote like
# "--upload-pack=<cmd>" would execute <cmd>. Every git invocation below also
# passes --end-of-options; this check is the belt to that suspenders.
if [[ $REMOTE == -* ]]; then
  printf 'error: REMOTE must not start with "-", got %q\n' "$REMOTE" >&2
  exit 1
fi

# Fail closed: an unrecognised DRY_RUN must never be read as "go ahead and
# push". ${DRY_RUN,,} lowercases, so TRUE and True land on the same branch.
case "${DRY_RUN,,}" in
  true | yes | 1) DRY_RUN=true ;;
  false | no | 0 | "") DRY_RUN=false ;;
  *)
    printf 'error: DRY_RUN must be true or false, got %q\n' "$DRY_RUN" >&2
    exit 1
    ;;
esac

log() {
  printf '%s\n' "$*"
}

# Commit the floating tag currently points at on the remote, and the stable
# releases the remote holds directly under that prefix. Set as globals because
# a single `git ls-remote` answers both questions in one round trip.
remote_current=""
remote_releases=()

inspect_remote() {
  local prefix="$1" listing oid ref

  remote_current="(none)"
  remote_releases=()

  if ! listing="$(git ls-remote --tags --end-of-options "$REMOTE" \
    "refs/tags/$prefix" "refs/tags/$prefix.*")"; then
    printf 'error: could not list tags on %q\n' "$REMOTE" >&2
    exit 1
  fi

  while read -r oid ref; do
    ref="${ref#refs/tags/}"

    # The floating tag itself. An annotated one also emits a "^{}" peel line
    # naming the commit, which is the value worth reporting.
    if [[ $ref == "$prefix" ]]; then
      if [[ $remote_current == "(none)" ]]; then
        remote_current="$oid"
      fi
      continue
    fi
    if [[ $ref == "${prefix}^{}" ]]; then
      remote_current="$oid"
      continue
    fi

    # Peel lines for release tags add nothing beyond the name already seen.
    if [[ $ref == *'^{}' ]]; then
      continue
    fi

    # Exact prefix boundary, compared as a literal string rather than a regex
    # built from $prefix: "v1" must be followed by ".", so v12.0.0 is never
    # mistaken for a v1 release.
    if [[ $ref != "${prefix}."* ]]; then
      continue
    fi
    if [[ ! $ref =~ $STABLE_RE ]]; then
      continue
    fi

    remote_releases+=("$ref")
  done <<<"$listing"
}

# Buffer the helper's diagnostics: a non-stable tag is an expected outcome here,
# so its complaint should not surface as an error in the job log.
compute_stderr="$(mktemp)"
trap 'rm -f "$compute_stderr"' EXIT

compute_status=0
floating_tags="$("$script_dir/compute-floating-tags.sh" "$TAG" 2>"$compute_stderr")" || compute_status=$?

if [[ $compute_status -eq $EXIT_NOT_STABLE ]]; then
  # %q, because a TAG carrying a stray control character would otherwise print
  # as a tag that looks perfectly valid.
  printf 'skipping non-stable tag: %q\n' "$TAG"
  exit 0
elif [[ $compute_status -ne 0 ]]; then
  cat "$compute_stderr" >&2
  exit "$compute_status"
fi

major=""
minor=""
while IFS='=' read -r key value; do
  case "$key" in
    major) major="$value" ;;
    minor) minor="$value" ;;
  esac
done <<<"$floating_tags"

if [[ -z $major || -z $minor ]]; then
  printf 'error: could not derive floating tags from %q\n' "$TAG" >&2
  exit 1
fi

# Always refresh from the remote, overwriting any local tag of the same name.
# A tag that is absent upstream is a hard error: there is nothing to float onto.
log "fetching refs/tags/$TAG from $REMOTE"
if ! git fetch --no-tags --end-of-options "$REMOTE" "+refs/tags/$TAG:refs/tags/$TAG"; then
  printf 'error: could not fetch refs/tags/%s from %q\n' "$TAG" "$REMOTE" >&2
  exit 1
fi

target="$(git rev-parse "refs/tags/$TAG^{commit}")"
log "release tag $TAG points at $target"

to_move=()
for floating in "$major" "$minor"; do
  inspect_remote "$floating"

  # TAG is always a candidate: the fetch above proved it exists on the remote.
  highest="$(printf '%s\n' "$TAG" "${remote_releases[@]}" | sort -V | tail -n 1)"

  if [[ $highest != "$TAG" ]]; then
    log "skipping $floating: $highest is newer than $TAG"
    continue
  fi

  if [[ $DRY_RUN == true ]]; then
    log "would move $floating: $remote_current -> $target"
  else
    log "moving $floating: $remote_current -> $target"
  fi
  to_move+=("$floating")
done

if [[ ${#to_move[@]} -eq 0 ]]; then
  log "no floating tags to move; nothing to push"
  exit 0
fi

if [[ $DRY_RUN == true ]]; then
  log "DRY_RUN=true; no local or remote refs were changed"
  exit 0
fi

push_args=()
for floating in "${to_move[@]}"; do
  git tag --force "$floating" "$target" >/dev/null
  push_args+=("+refs/tags/$floating:refs/tags/$floating")
done

# --atomic: either every floating tag moves or none of them does, so a rejected
# ref can never leave the remote advertising a half-updated set.
git push --atomic --end-of-options "$REMOTE" "${push_args[@]}"
log "pushed ${to_move[*]} to $REMOTE"
