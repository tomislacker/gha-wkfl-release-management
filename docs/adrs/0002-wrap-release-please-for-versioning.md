# 2. Wrap release-please for versioning

Date: 2026-09-24

Status: accepted

## Context

This project began as floating-tag logic: given `v1.2.3`, move `v1` and `v1.2`. That logic is useless on its own —
something has to decide what `v1.2.3` is and create it. The options were to ship only the floating-tag half and leave
consumers to wire up their own release automation, or to wrap a version-decision tool and ship a complete pipeline.

Leaving it to consumers means every consumer repeats the same fiddly integration, and each one gets the sequencing
subtly wrong in its own way.

Candidates for the version-decision half:

- **[release-please](https://github.com/googleapis/release-please-action)** — reads conventional commits, maintains a
  release pull request carrying the version bump and changelog, tags and releases when that pull request merges.
  Language-agnostic, Google-maintained, Apache-2.0, and the release pull request is a natural human checkpoint.
- **[semantic-release](https://github.com/semantic-release/semantic-release)** — heavier, npm-centric (plugin
  ecosystem, `package.json` assumptions), and releases immediately on merge with no review step.
- **Tag-on-every-merge actions** — trivially simple, but every merge to the default branch ships. No checkpoint, no
  batching of a changelog, no way to hold a release back.
- **Manual tagging** — full control, pure toil, and inevitably inconsistent about what counts as a minor bump.

There is also a hard technical constraint that decides the shape of the result. Tags created by release-please using
the default `GITHUB_TOKEN` do **not** trigger further workflow runs; GitHub blocks that to prevent recursion. So a
separate `on: push: tags` workflow that moves the floating tags would simply never fire for the tags this tool
creates. Any design where tagging and floating-tag movement are separate workflows requires a PAT to work at all.

## Decision

Wrap release-please in a reusable workflow, and move the floating tags in the **same workflow run** — a dependent job
gated on release-please reporting `release_created == true`.

Conventional commits drive the bump type: `fix:` → patch, `feat:` → minor, `!` or a `BREAKING CHANGE:` footer → major.
Release-please's configuration (`release-please-config.json`, `.release-please-manifest.json`) stays in the consumer's
repository; this workflow only passes their paths through, so consumers keep full access to release-please's own
options.

This repository's own configuration starts the manifest at `{".": "0.0.0"}` and sets exactly one pre-1.0 option,
`bump-minor-pre-major: true`. The companion option that would demote `feat:` to a patch bump while below `1.0.0` is
deliberately left unset. The result while the version is below `1.0.0`:

- `feat:` → minor, so the first release from the `0.0.0` manifest is `0.1.0`, tagged `v0.1.0`, with floating tags `v0`
  and `v0.1`.
- `fix:` → patch.
- `!` / `BREAKING CHANGE:` → **minor**, not major. The major stays at `0` until the interface is promoted by hand.

Promotion to `1.0.0` is a deliberate act — release-please will not do it on its own — and happens when the input,
output, and tag-movement semantics are stable enough to make a major-version promise about. From `1.0.0` onward the
ordinary semver mapping (`!` → major) applies with no further configuration change.

## Consequences

- Consumers get a complete pipeline from one `uses:` line, and a human checkpoint (the release pull request) before
  anything ships.
- Bundling tag movement into the release run works with the default `GITHUB_TOKEN`, with no PAT required for the core
  behaviour. That is the whole reason it is bundled rather than split across workflows.
- Consumers inherit release-please's conventions and its bugs. Its configuration surface is exposed only as file
  paths, which is enough for now but will need widening if consumers need more.
- The release pull request itself does not run CI under the default token (same anti-recursion rule). That is
  documented, and a fine-grained PAT passed as the `token` secret fixes it.
- Versions below `1.0.0` deliberately do not honour semver's major-bump-on-breaking rule: a breaking change moves the
  minor, and `v0` therefore moves across breaking changes. Consumers on `v0` should pin by minor (`v0.1`) or by SHA.
- **Single-package (root `"."`) configurations only.** The workflow reads release-please's root-component outputs
  (`release_created`, `tag_name`) and passes `tag_name` to the floating-tag job. A monorepo config that releases
  path-prefixed components emits per-component outputs (`packages/foo--release_created` and friends) that this
  workflow does not read, so those packages still get released and tagged by release-please — they simply get no
  floating tags. Supporting monorepos would mean enumerating components and fanning the floating-tag job out over a
  matrix, which is out of scope for now.
