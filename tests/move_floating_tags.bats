#!/usr/bin/env bats
#
# Integration tests for scripts/move-floating-tags.sh
#
# Every test runs against a throwaway bare "remote" and a clone of it, both
# created under $BATS_TEST_TMPDIR (fresh per test). Git identity and signing are
# configured *locally inside those sandboxes only* -- the developer's global git
# configuration is never read for identity and never written.
#
# Contract under test:
#   * TAG is required; REMOTE defaults to origin; DRY_RUN defaults to false
#   * REMOTE may not look like a git option, and DRY_RUN fails closed
#   * the remote is authoritative: the release tag is always re-fetched, and a
#     tag missing upstream is a hard error
#   * a floating tag only moves when TAG is the highest stable release the
#     remote holds under that floating prefix
#   * surviving floating tags are force-pushed atomically
#   * DRY_RUN=true writes nothing, locally or remotely
#   * a non-stable TAG is a graceful skip (exit 0, no tags)
#   * re-running is idempotent

bats_require_minimum_version 1.5.0

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../scripts/move-floating-tags.sh"
  REMOTE_REPO="${BATS_TEST_TMPDIR}/remote.git"
  CLONE="${BATS_TEST_TMPDIR}/clone"

  unset TAG REMOTE DRY_RUN

  git init --quiet --bare --initial-branch=main "$REMOTE_REPO"
  git clone --quiet "$REMOTE_REPO" "$CLONE" 2>/dev/null
  sandbox_identity "$CLONE"
  git -C "$CLONE" symbolic-ref HEAD refs/heads/main

  make_commit "$CLONE" "initial commit"
  make_tag "$CLONE" "v1.2.3" "release v1.2.3"
  git -C "$CLONE" push --quiet origin main
  git -C "$CLONE" push --quiet origin v1.2.3

  cd "$CLONE" || return 1
}

# Sandbox-only git identity: written into <repo>/.git/config, nowhere else.
sandbox_identity() {
  git -C "$1" config user.name "Bats Sandbox"
  git -C "$1" config user.email "bats-sandbox@example.invalid"
  git -C "$1" config commit.gpgsign false
  git -C "$1" config tag.gpgsign false
}

make_commit() {
  local repo="$1" message="$2"
  printf '%s\n' "$message" >>"${repo}/log.txt"
  git -C "$repo" add log.txt
  git -C "$repo" commit --quiet --no-gpg-sign --message "$message"
}

make_tag() {
  local repo="$1" tag="$2" message="$3"
  git -C "$repo" tag --annotate --message "$message" "$tag"
}

# Commit, tag and publish in one step, from the clone under test.
release() {
  local tag="$1"
  make_commit "$CLONE" "commit for $tag"
  make_tag "$CLONE" "$tag" "release $tag"
  git -C "$CLONE" push --quiet origin main
  git -C "$CLONE" push --quiet origin "$tag"
}

# Commit a tag ref resolves to, in whichever repository is named.
commit_of() {
  git -C "$1" rev-list --max-count=1 "$2"
}

remote_commit_of() {
  commit_of "$REMOTE_REPO" "$1"
}

remote_has_tag() {
  git -C "$REMOTE_REPO" rev-parse --quiet --verify "refs/tags/$1" >/dev/null
}

local_has_tag() {
  git -C "$CLONE" rev-parse --quiet --verify "refs/tags/$1" >/dev/null
}

# Make the bare remote reject exactly one ref, so an atomic push has one good
# ref and one bad one.
reject_ref_on_remote() {
  local hook="${REMOTE_REPO}/hooks/update"

  cat >"$hook" <<HOOK
#!/usr/bin/env bash
if [ "\$1" = "$1" ]; then
  printf 'rejected by the test hook\n' >&2
  exit 1
fi
exit 0
HOOK

  chmod +x "$hook"
}

@test "script exists and is executable" {
  [ -f "$SCRIPT" ]
  [ -x "$SCRIPT" ]
}

@test "creates floating tags locally and on the remote" {
  local released
  released="$(commit_of "$CLONE" v1.2.3)"

  TAG=v1.2.3 run "$SCRIPT"
  [ "$status" -eq 0 ]

  local_has_tag v1
  local_has_tag v1.2
  [ "$(commit_of "$CLONE" v1)" = "$released" ]
  [ "$(commit_of "$CLONE" v1.2)" = "$released" ]

  remote_has_tag v1
  remote_has_tag v1.2
  [ "$(remote_commit_of v1)" = "$released" ]
  [ "$(remote_commit_of v1.2)" = "$released" ]
}

@test "floating tags point at the commit an annotated tag peels to" {
  TAG=v1.2.3 run "$SCRIPT"
  [ "$status" -eq 0 ]

  # v1.2.3 is an annotated tag: its own object id differs from the commit id.
  [ "$(git -C "$CLONE" rev-parse v1.2.3)" != "$(git -C "$CLONE" rev-parse 'v1.2.3^{commit}')" ]
  [ "$(remote_commit_of v1)" = "$(git -C "$CLONE" rev-parse 'v1.2.3^{commit}')" ]
}

@test "a bare (unprefixed) release tag yields bare floating tags" {
  release "1.2.3"

  TAG=1.2.3 run "$SCRIPT"
  [ "$status" -eq 0 ]

  remote_has_tag 1
  remote_has_tag 1.2
  [ "$(remote_commit_of 1)" = "$(commit_of "$CLONE" 1.2.3)" ]
  [ "$(remote_commit_of 1.2)" = "$(commit_of "$CLONE" 1.2.3)" ]

  # The v-prefixed family is a different namespace and must be untouched.
  run remote_has_tag v1
  [ "$status" -ne 0 ]
}

@test "re-running with the same tag is idempotent" {
  local released
  released="$(commit_of "$CLONE" v1.2.3)"

  TAG=v1.2.3 run "$SCRIPT"
  [ "$status" -eq 0 ]

  TAG=v1.2.3 run "$SCRIPT"
  [ "$status" -eq 0 ]

  [ "$(remote_commit_of v1)" = "$released" ]
  [ "$(remote_commit_of v1.2)" = "$released" ]
}

@test "a later patch release moves both floating tags on the remote" {
  TAG=v1.2.3 run "$SCRIPT"
  [ "$status" -eq 0 ]

  release "v1.2.4"

  local patched
  patched="$(commit_of "$CLONE" v1.2.4)"
  [ "$patched" != "$(commit_of "$CLONE" v1.2.3)" ]

  TAG=v1.2.4 run "$SCRIPT"
  [ "$status" -eq 0 ]

  [ "$(remote_commit_of v1)" = "$patched" ]
  [ "$(remote_commit_of v1.2)" = "$patched" ]
}

@test "a minor release moves v1 but leaves the older minor tag alone" {
  TAG=v1.2.3 run "$SCRIPT"
  [ "$status" -eq 0 ]

  local old_minor
  old_minor="$(remote_commit_of v1.2)"

  release "v1.3.0"

  TAG=v1.3.0 run "$SCRIPT"
  [ "$status" -eq 0 ]

  [ "$(remote_commit_of v1)" = "$(commit_of "$CLONE" v1.3.0)" ]
  [ "$(remote_commit_of v1.3)" = "$(commit_of "$CLONE" v1.3.0)" ]
  [ "$(remote_commit_of v1.2)" = "$old_minor" ]
}

@test "a new major release does not disturb the previous major" {
  TAG=v1.2.3 run "$SCRIPT"
  [ "$status" -eq 0 ]

  local v1_commit
  v1_commit="$(remote_commit_of v1)"

  release "v2.0.0"

  TAG=v2.0.0 run "$SCRIPT"
  [ "$status" -eq 0 ]

  remote_has_tag v2
  remote_has_tag v2.0
  [ "$(remote_commit_of v2)" = "$(commit_of "$CLONE" v2.0.0)" ]
  [ "$(remote_commit_of v1)" = "$v1_commit" ]
  [ "$(remote_commit_of v1.2)" = "$v1_commit" ]
}

@test "fetches the release tag when it is only present on the remote" {
  local other="${BATS_TEST_TMPDIR}/other"
  git clone --quiet "$REMOTE_REPO" "$other"
  sandbox_identity "$other"
  make_commit "$other" "commit from elsewhere"
  make_tag "$other" "v1.4.0" "release v1.4.0"
  git -C "$other" push --quiet origin main
  git -C "$other" push --quiet origin v1.4.0

  # The clone under test has never seen v1.4.0.
  run git -C "$CLONE" rev-parse --quiet --verify refs/tags/v1.4.0
  [ "$status" -ne 0 ]

  TAG=v1.4.0 run "$SCRIPT"
  [ "$status" -eq 0 ]

  [ "$(remote_commit_of v1)" = "$(commit_of "$other" v1.4.0)" ]
  [ "$(remote_commit_of v1.4)" = "$(commit_of "$other" v1.4.0)" ]
}

@test "a stale local tag is refreshed from the remote rather than trusted" {
  local other="${BATS_TEST_TMPDIR}/other"
  git clone --quiet "$REMOTE_REPO" "$other"
  sandbox_identity "$other"
  make_commit "$other" "the real v1.5.0"
  make_tag "$other" "v1.5.0" "release v1.5.0"
  git -C "$other" push --quiet origin main
  git -C "$other" push --quiet origin v1.5.0

  # A long-lived runner could still be holding a v1.5.0 that means something
  # else entirely; the remote's version is the one that counts.
  make_commit "$CLONE" "a different v1.5.0"
  make_tag "$CLONE" "v1.5.0" "stale local v1.5.0"
  [ "$(commit_of "$CLONE" v1.5.0)" != "$(commit_of "$other" v1.5.0)" ]

  TAG=v1.5.0 run "$SCRIPT"
  [ "$status" -eq 0 ]

  [ "$(remote_commit_of v1)" = "$(commit_of "$other" v1.5.0)" ]
  [ "$(remote_commit_of v1.5)" = "$(commit_of "$other" v1.5.0)" ]
}

@test "a tag that exists only locally is a hard failure" {
  make_commit "$CLONE" "never published"
  make_tag "$CLONE" "v1.9.0" "local-only release"
  run git -C "$REMOTE_REPO" rev-parse --quiet --verify refs/tags/v1.9.0
  [ "$status" -ne 0 ]

  TAG=v1.9.0 run "$SCRIPT"
  [ "$status" -ne 0 ]

  run remote_has_tag v1
  [ "$status" -ne 0 ]
  run remote_has_tag v1.9
  [ "$status" -ne 0 ]
}

# --- highest-version-wins guard ---------------------------------------------
# Commit ancestry is irrelevant to the script; only the version ordering of the
# tags the remote already publishes decides whether a floating tag may move.

@test "a backported patch moves its minor tag but not the major tag" {
  release "v1.3.0"
  TAG=v1.3.0 run "$SCRIPT"
  [ "$status" -eq 0 ]

  local v1_commit
  v1_commit="$(remote_commit_of v1)"
  [ "$v1_commit" = "$(commit_of "$CLONE" v1.3.0)" ]

  release "v1.2.4"

  TAG=v1.2.4 run "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"skipping v1: v1.3.0 is newer than v1.2.4"* ]]

  [ "$(remote_commit_of v1.2)" = "$(commit_of "$CLONE" v1.2.4)" ]
  [ "$(remote_commit_of v1)" = "$v1_commit" ]
}

@test "re-running an out-of-order release still leaves the major tag alone" {
  release "v1.3.0"
  TAG=v1.3.0 run "$SCRIPT"
  [ "$status" -eq 0 ]

  local v1_commit
  v1_commit="$(remote_commit_of v1)"

  release "v1.2.4"

  TAG=v1.2.4 run "$SCRIPT"
  [ "$status" -eq 0 ]
  TAG=v1.2.4 run "$SCRIPT"
  [ "$status" -eq 0 ]

  [ "$(remote_commit_of v1)" = "$v1_commit" ]
  [ "$(remote_commit_of v1.2)" = "$(commit_of "$CLONE" v1.2.4)" ]
  [ "$(remote_commit_of v1.3)" = "$v1_commit" ]
}

@test "an older minor release does not drag the major tag backwards" {
  release "v2.0.0"
  TAG=v2.0.0 run "$SCRIPT"
  [ "$status" -eq 0 ]

  release "v2.1.0"
  TAG=v2.1.0 run "$SCRIPT"
  [ "$status" -eq 0 ]

  local v2_commit
  v2_commit="$(remote_commit_of v2)"

  # v2.0.1 lands late; v2.0 is its floating home, v2 belongs to v2.1.0.
  release "v2.0.1"
  TAG=v2.0.1 run "$SCRIPT"
  [ "$status" -eq 0 ]

  [ "$(remote_commit_of v2)" = "$v2_commit" ]
  [ "$(remote_commit_of v2.0)" = "$(commit_of "$CLONE" v2.0.1)" ]
}

@test "a numerically larger sibling major is not mistaken for a newer release" {
  # v12.0.0 sorts above v1.2.3 but shares no floating prefix with it.
  release "v12.0.0"

  TAG=v1.2.3 run "$SCRIPT"
  [ "$status" -eq 0 ]

  [ "$(remote_commit_of v1)" = "$(commit_of "$CLONE" v1.2.3)" ]
  [ "$(remote_commit_of v1.2)" = "$(commit_of "$CLONE" v1.2.3)" ]

  run remote_has_tag v12
  [ "$status" -ne 0 ]
}

# --- atomicity ---------------------------------------------------------------

@test "a rejected ref leaves neither floating tag moved" {
  reject_ref_on_remote refs/tags/v1.2

  TAG=v1.2.3 run "$SCRIPT"
  [ "$status" -ne 0 ]

  run remote_has_tag v1
  [ "$status" -ne 0 ]
  run remote_has_tag v1.2
  [ "$status" -ne 0 ]
}

@test "a rejected ref does not undo an already-correct floating tag" {
  TAG=v1.2.3 run "$SCRIPT"
  [ "$status" -eq 0 ]

  local released
  released="$(commit_of "$CLONE" v1.2.3)"

  reject_ref_on_remote refs/tags/v1.2
  release "v1.2.4"

  TAG=v1.2.4 run "$SCRIPT"
  [ "$status" -ne 0 ]

  [ "$(remote_commit_of v1)" = "$released" ]
  [ "$(remote_commit_of v1.2)" = "$released" ]
}

# --- DRY_RUN -----------------------------------------------------------------

@test "DRY_RUN=true changes neither the remote nor the local repository" {
  TAG=v1.2.3 DRY_RUN=true run "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"would move v1:"* ]]

  run remote_has_tag v1
  [ "$status" -ne 0 ]
  run remote_has_tag v1.2
  [ "$status" -ne 0 ]
  run local_has_tag v1
  [ "$status" -ne 0 ]
  run local_has_tag v1.2
  [ "$status" -ne 0 ]
}

@test "DRY_RUN=TRUE is recognised regardless of case" {
  TAG=v1.2.3 DRY_RUN=TRUE run "$SCRIPT"
  [ "$status" -eq 0 ]

  run remote_has_tag v1
  [ "$status" -ne 0 ]
  run local_has_tag v1
  [ "$status" -ne 0 ]
}

@test "DRY_RUN=Yes is treated as a dry run" {
  TAG=v1.2.3 DRY_RUN=Yes run "$SCRIPT"
  [ "$status" -eq 0 ]

  run remote_has_tag v1
  [ "$status" -ne 0 ]
  run local_has_tag v1
  [ "$status" -ne 0 ]
}

@test "DRY_RUN=1 is treated as a dry run" {
  TAG=v1.2.3 DRY_RUN=1 run "$SCRIPT"
  [ "$status" -eq 0 ]

  run remote_has_tag v1
  [ "$status" -ne 0 ]
  run local_has_tag v1
  [ "$status" -ne 0 ]
}

@test "DRY_RUN=false still pushes" {
  TAG=v1.2.3 DRY_RUN=false run "$SCRIPT"
  [ "$status" -eq 0 ]

  remote_has_tag v1
  remote_has_tag v1.2
}

@test "DRY_RUN=No still pushes" {
  TAG=v1.2.3 DRY_RUN=No run "$SCRIPT"
  [ "$status" -eq 0 ]

  remote_has_tag v1
  remote_has_tag v1.2
}

@test "an empty DRY_RUN still pushes" {
  TAG=v1.2.3 DRY_RUN='' run "$SCRIPT"
  [ "$status" -eq 0 ]

  remote_has_tag v1
  remote_has_tag v1.2
}

@test "an unrecognised DRY_RUN fails closed without pushing" {
  TAG=v1.2.3 DRY_RUN=banana run "$SCRIPT"
  [ "$status" -eq 1 ]

  run remote_has_tag v1
  [ "$status" -ne 0 ]
  run remote_has_tag v1.2
  [ "$status" -ne 0 ]
  run local_has_tag v1
  [ "$status" -ne 0 ]
}

# --- REMOTE validation -------------------------------------------------------

@test "an option-shaped REMOTE is refused before git is ever invoked" {
  # git would otherwise parse this as an option and execute the command.
  TAG=v1.2.3 REMOTE='--upload-pack=touch pwned' run "$SCRIPT"
  [ "$status" -eq 1 ]

  [ ! -e "${CLONE}/pwned" ]
  [ ! -e "${BATS_TEST_TMPDIR}/pwned" ]
  run remote_has_tag v1
  [ "$status" -ne 0 ]
  run local_has_tag v1
  [ "$status" -ne 0 ]
}

@test "a single dash REMOTE is refused" {
  TAG=v1.2.3 REMOTE=- run "$SCRIPT"
  [ "$status" -eq 1 ]

  run remote_has_tag v1
  [ "$status" -ne 0 ]
}

@test "honours a non-default REMOTE" {
  local mirror="${BATS_TEST_TMPDIR}/mirror.git"
  git init --quiet --bare --initial-branch=main "$mirror"
  git -C "$CLONE" remote add upstream "$mirror"
  git -C "$CLONE" push --quiet upstream main
  git -C "$CLONE" push --quiet upstream v1.2.3

  TAG=v1.2.3 REMOTE=upstream run "$SCRIPT"
  [ "$status" -eq 0 ]

  run git -C "$mirror" rev-parse --quiet --verify refs/tags/v1
  [ "$status" -eq 0 ]
  [ "$(commit_of "$mirror" v1)" = "$(commit_of "$CLONE" v1.2.3)" ]

  # origin was never named, so it must be untouched.
  run remote_has_tag v1
  [ "$status" -ne 0 ]
}

# --- non-stable and missing tags ---------------------------------------------

@test "a prerelease tag is a graceful skip" {
  release "v1.2.3-rc.1"

  TAG=v1.2.3-rc.1 run "$SCRIPT"
  [ "$status" -eq 0 ]

  run remote_has_tag v1
  [ "$status" -ne 0 ]
  run remote_has_tag v1.2
  [ "$status" -ne 0 ]
  run local_has_tag v1
  [ "$status" -ne 0 ]
}

@test "a tag with leading zeros is a graceful skip" {
  TAG=v01.2.3 run "$SCRIPT"
  [ "$status" -eq 0 ]

  run remote_has_tag v01
  [ "$status" -ne 0 ]
  run remote_has_tag v1
  [ "$status" -ne 0 ]
}

@test "an unparseable tag is a graceful skip" {
  TAG=banana run "$SCRIPT"
  [ "$status" -eq 0 ]

  run remote_has_tag v1
  [ "$status" -ne 0 ]
}

@test "the skip message quotes a tag carrying control characters" {
  TAG="$(printf 'v1.2.3\r')" run "$SCRIPT"
  [ "$status" -eq 0 ]

  # Printed as an escape, never as a bare "v1.2.3" that looks perfectly valid.
  [[ "$output" != *"skipping non-stable tag: v1.2.3" ]]
  [[ "$output" == *'\r'* ]]
}

@test "a missing TAG fails" {
  run "$SCRIPT"
  [ "$status" -ne 0 ]

  run remote_has_tag v1
  [ "$status" -ne 0 ]
}

@test "an empty TAG fails" {
  run env TAG= "$SCRIPT"
  [ "$status" -ne 0 ]
}
