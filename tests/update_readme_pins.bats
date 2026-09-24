#!/usr/bin/env bats
# Tests for scripts/update-readme-pins.sh -- README pin publishing.

SCRIPT="$BATS_TEST_DIRNAME/../scripts/update-readme-pins.sh"

REAL_SHA="93c3b6b615219c9a1588a643af62b2f63e7695ad"
OTHER_SHA="1111111111111111111111111111111111111111"
CHECKOUT_SHA="3d3c42e5aac5ba805825da76410c181273ba90b1"

setup() {
  cd "$BATS_TEST_TMPDIR" || exit 1
  cat >README.md <<'EOF'
# Fixture

```yaml
jobs:
  release:
    uses: tomislacker/gha-wkfl-release-management/.github/workflows/release-management.yml@<commit-sha> # vX.Y.Z
```

```yaml
    steps:
      - uses: actions/checkout@<commit-sha> # v7.0.1
      - uses: tomislacker/gha-wkfl-release-management@<commit-sha> # vX.Y.Z
      - uses: some-other/action@deadbeef # v9
```
EOF
  mkdir -p .github/workflows
  cat >.github/workflows/release-management.yml <<EOF
      - uses: actions/checkout@${CHECKOUT_SHA} # v7.0.1
EOF
}

@test "placeholders are replaced with the literal SHA and tag" {
  TAG=v0.1.0 SHA="$REAL_SHA" run "$SCRIPT"
  [ "$status" -eq 0 ]

  run grep -c "gha-wkfl-release-management/.github/workflows/release-management.yml@${REAL_SHA} # v0.1.0" README.md
  [ "$output" = "1" ]
  run grep -c "uses: tomislacker/gha-wkfl-release-management@${REAL_SHA} # v0.1.0" README.md
  [ "$output" = "1" ]
  run grep -q '<commit-sha>' README.md
  [ "$status" -ne 0 ]
}

@test "the checkout example is synced from the workflow's real pin" {
  TAG=v0.1.0 SHA="$REAL_SHA" run "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -q "uses: actions/checkout@${CHECKOUT_SHA} # v7.0.1" README.md
}

@test "unrelated uses: lines are untouched" {
  TAG=v0.1.0 SHA="$REAL_SHA" run "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -q "uses: some-other/action@deadbeef # v9" README.md
}

@test "already-pinned references are re-pinned to the new release" {
  TAG=v0.1.0 SHA="$REAL_SHA" run "$SCRIPT"
  [ "$status" -eq 0 ]
  TAG=v0.2.0 SHA="$OTHER_SHA" run "$SCRIPT"
  [ "$status" -eq 0 ]
  run grep -c "gha-wkfl-release-management@${OTHER_SHA} # v0.2.0" README.md
  [ "$output" = "1" ]
  run grep -q "$REAL_SHA" README.md
  [ "$status" -ne 0 ]
}

@test "a second run with the same inputs is a no-op" {
  TAG=v0.1.0 SHA="$REAL_SHA" run "$SCRIPT"
  [ "$status" -eq 0 ]
  first="$(cat README.md)"
  TAG=v0.1.0 SHA="$REAL_SHA" run "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ $output == *"already current"* ]]
  [ "$first" = "$(cat README.md)" ]
}

@test "a missing workflow file leaves the checkout example alone" {
  rm .github/workflows/release-management.yml
  TAG=v0.1.0 SHA="$REAL_SHA" run "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -q 'uses: actions/checkout@<commit-sha> # v7.0.1' README.md
}

@test "a prerelease TAG is rejected" {
  TAG=v0.1.0-rc.1 SHA="$REAL_SHA" run "$SCRIPT"
  [ "$status" -eq 1 ]
  grep -q '<commit-sha>' README.md
}

@test "a short or non-hex SHA is rejected" {
  TAG=v0.1.0 SHA=deadbeef run "$SCRIPT"
  [ "$status" -eq 1 ]
  TAG=v0.1.0 SHA="ZZ11111111111111111111111111111111111111" run "$SCRIPT"
  [ "$status" -eq 1 ]
}

@test "a missing README is a hard error" {
  rm README.md
  TAG=v0.1.0 SHA="$REAL_SHA" run "$SCRIPT"
  [ "$status" -eq 1 ]
}

@test "a hostile REPO_SLUG is rejected" {
  TAG=v0.1.0 SHA="$REAL_SHA" REPO_SLUG='a|b/c' run "$SCRIPT"
  [ "$status" -eq 1 ]
}
