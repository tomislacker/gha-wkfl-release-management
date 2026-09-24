#!/usr/bin/env bats
#
# Unit tests for scripts/compute-floating-tags.sh
#
# Contract under test:
#   * the tag is read from $1, falling back to $TAG
#   * stable tags matching ^v?(0|[1-9][0-9]*)(\.(0|[1-9][0-9]*)){2}$ are accepted,
#     i.e. semver's no-leading-zeros rule is enforced
#   * stdout is exactly two lines, in order: `major=<tag>` then `minor=<tag>`
#   * the `v` prefix style of the input is preserved in the output
#   * anything else exits 2 and explains itself on stderr

bats_require_minimum_version 1.5.0

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../scripts/compute-floating-tags.sh"
  # Never inherit a TAG from the environment running the suite.
  unset TAG
}

# Asserts the script accepted $1 and printed exactly the expected two lines.
assert_computes() {
  local input="$1" expected_major="$2" expected_minor="$3"

  run --separate-stderr "$SCRIPT" "$input"

  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 2 ]
  [ "${lines[0]}" = "major=${expected_major}" ]
  [ "${lines[1]}" = "minor=${expected_minor}" ]
}

# Asserts the script rejected $1 with exit 2 and a non-empty stderr message.
assert_rejects() {
  run --separate-stderr "$SCRIPT" "$1"

  [ "$status" -eq 2 ]
  [ -z "$output" ]
  [ -n "$stderr" ]
}

@test "script exists and is executable" {
  [ -f "$SCRIPT" ]
  [ -x "$SCRIPT" ]
}

@test "v-prefixed release yields v-prefixed floating tags" {
  assert_computes "v1.2.3" "v1" "v1.2"
}

@test "bare release yields bare floating tags" {
  assert_computes "0.3.7" "0" "0.3"
}

@test "zero major and zero minor are preserved" {
  assert_computes "v0.1.0" "v0" "v0.1"
}

@test "multi-digit components are not truncated" {
  assert_computes "v10.20.30" "v10" "v10.20"
}

@test "large bare version components are handled" {
  assert_computes "123.456.789" "123" "123.456"
}

@test "tag may be supplied positionally" {
  run --separate-stderr "$SCRIPT" "v2.5.9"

  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "major=v2" ]
  [ "${lines[1]}" = "minor=v2.5" ]
}

@test "tag may be supplied through the TAG environment variable" {
  TAG="v2.5.9" run --separate-stderr "$SCRIPT"

  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 2 ]
  [ "${lines[0]}" = "major=v2" ]
  [ "${lines[1]}" = "minor=v2.5" ]
}

@test "positional tag takes precedence over the TAG environment variable" {
  TAG="v9.9.9" run --separate-stderr "$SCRIPT" "v1.2.3"

  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "major=v1" ]
  [ "${lines[1]}" = "minor=v1.2" ]
}

@test "stdout is exactly two lines in major-then-minor order" {
  run --separate-stderr "$SCRIPT" "v4.5.6"

  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 2 ]
  [[ "${lines[0]}" == major=* ]]
  [[ "${lines[1]}" == minor=* ]]
}

@test "a successful run writes nothing to stderr" {
  run --separate-stderr "$SCRIPT" "v1.2.3"

  [ "$status" -eq 0 ]
  [ -z "$stderr" ]
}

@test "rejects a prerelease tag" {
  assert_rejects "v1.2.3-rc.1"
}

@test "rejects a bare prerelease tag" {
  assert_rejects "1.0.0-alpha"
}

@test "rejects build metadata" {
  assert_rejects "v1.2.3+build.5"
}

@test "rejects a two-component version" {
  assert_rejects "v1.2"
}

@test "rejects a four-component version" {
  assert_rejects "1.2.3.4"
}

@test "rejects a non-numeric version" {
  assert_rejects "banana"
}

@test "rejects a tag with a leading space" {
  assert_rejects " v1.2.3"
}

@test "rejects a tag with a trailing space" {
  assert_rejects "v1.2.3 "
}

# Semver 2.0.0 section 2: numeric identifiers must not carry a leading zero.

@test "rejects a leading zero in the major component" {
  assert_rejects "v01.2.3"
}

@test "rejects leading zeros in every component" {
  assert_rejects "00.00.00"
}

@test "rejects padded components on a v-prefixed tag" {
  assert_rejects "v0008.0009.0010"
}

@test "rejects a leading zero in the minor component" {
  assert_rejects "v1.02.3"
}

@test "rejects a leading zero in the patch component" {
  assert_rejects "1.2.03"
}

@test "a plain zero component is still accepted" {
  assert_computes "v0.0.0" "v0" "v0.0"
}

@test "rejects an uppercase V prefix" {
  assert_rejects "V1.2.3"
}

@test "rejects an empty positional argument" {
  assert_rejects ""
}

@test "rejects an empty TAG environment variable" {
  run --separate-stderr env TAG= "$SCRIPT"

  [ "$status" -eq 2 ]
  [ -z "$output" ]
  [ -n "$stderr" ]
}

@test "rejects a missing tag entirely" {
  run --separate-stderr "$SCRIPT"

  [ "$status" -eq 2 ]
  [ -z "$output" ]
  [ -n "$stderr" ]
}
