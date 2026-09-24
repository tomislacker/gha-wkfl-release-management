# AGENTS.md

Guidance for AI coding agents working in this repository. Humans should read [README.md](README.md) first; everything
here is additive to it, not a replacement for it.

## What this repository is

A reusable GitHub Actions workflow that runs [release-please](https://github.com/googleapis/release-please-action) to
turn conventional commits into releases, then force-moves the floating `v1` / `v1.2` tags onto the new `vX.Y.Z` tag in
the same workflow run. The floating-tag half is also published standalone as a composite action at the repository root.

## Repository map

| Path | Role |
| --- | --- |
| `action.yml` | Composite action: the standalone floating-tag surface. Inputs `tag`, `remote`, `dry-run`. |
| `.github/workflows/release-management.yml` | The reusable workflow (`on: workflow_call`). The main product. |
| `.github/workflows/release.yml` | Dogfooding: push to `main` calls the local reusable workflow. |
| `.github/workflows/ci.yml` | `pre-commit`, bats, commitlint, and the pull-request-title check. |
| `.github/workflows/labels.yml`, `.github/labels.yml` | Declarative label sync. |
| `.github/dependabot.yml`, `.github/CODEOWNERS` | Action pin updates; review ownership. |
| `.github/PULL_REQUEST_TEMPLATE.md` | Pull request checklist. |
| `.github/actionlint.yaml` | actionlint suppressions, currently the `job.workflow_*` properties it does not know. |
| `.pre-commit-config.yaml` | The authoritative lint set. `.markdownlint.yaml`, `.yamllint.yaml` configure it. |
| `commitlint.config.mjs` | CI commit linting: `@commitlint/config-conventional` with `header-max-length` at 120. |
| `.editorconfig` | Editor defaults; `max_line_length = 120` repository-wide. |
| `scripts/compute-floating-tags.sh` | Pure string logic: `v1.2.3` → `major=v1`, `minor=v1.2`. No git, no network. |
| `scripts/move-floating-tags.sh` | Fetches the release tag, force-moves both floating tags, pushes them atomically. |
| `tests/` | [bats](https://bats-core.readthedocs.io/) unit tests for `scripts/` — 63 of them across two files. |
| `docs/adrs/` | Architecture decision records, MADR-lite, numbered. |
| `release-please-config.json`, `.release-please-manifest.json` | This repository's own release-please config. |
| `SECURITY.md` | Vulnerability reporting, tag-yank policy, consumer trust boundaries. |
| `LICENSE` | Apache-2.0. Inbound = outbound; do not add dependencies under an incompatible licence. |

## Conventions you MUST follow

- **Conventional commits on every commit**, not just the pull request title. The allowed type list is whatever
  [`@commitlint/config-conventional`][config-conventional] allows — `build`, `chore`, `ci`, `docs`, `feat`, `fix`,
  `perf`, `refactor`, `revert`, `style`, `test` — extended by `commitlint.config.mjs`. Treat that package as the
  single source of truth rather than any list in documentation, including this one.
  `!` or a `BREAKING CHANGE:` footer marks a breaking change. These messages are the input to the version-bump logic,
  so a wrong type ships a wrong version. CI rejects violations on both commits and the pull request title. See
  [ADR 0006](docs/adrs/0006-conventional-commits-enforced.md).
- **Commit subjects are capped at 120 characters** (`header-max-length` in `commitlint.config.mjs`, raised from the
  config-conventional default of 100). The local `commit-msg` hook does not check length, so an over-long subject
  passes locally and fails in CI.
- **120-character lines** in markdown and YAML, where `markdownlint` and `yamllint` enforce it. The same limit is a
  convention for shell via `.editorconfig`; nothing enforces it there, so respect it by hand.
- **SHA-pin every third-party action** referenced from a workflow `uses:` line, to a full 40-character commit SHA with
  a trailing comment naming the tag: `uses: actions/checkout@<40-char-sha> # v7.0.1`. Never a bare tag or branch.
  `.pre-commit-config.yaml` `rev:` entries are the deliberate exception — they stay version tags, per pre-commit
  convention. See [ADR 0005](docs/adrs/0005-sha-pin-third-party-actions.md).
- **Never interpolate `${{ }}` into a `run:` body.** Pass every dynamic value through `env:` and reference it as a
  shell variable. This is a script-injection boundary, and it is enforced by review.
- **Shell must pass `shellcheck` and `shfmt`.** `.pre-commit-config.yaml` is authoritative for the `shfmt` flags —
  read it rather than guessing, and let the hook rewrite formatting. Scripts use `set -euo pipefail` and take their
  inputs from environment variables so they are testable outside Actions.
- **Run `pre-commit run --all-files` and `bats tests/` before committing.** Do not commit work you have not run these
  against.
- **Record significant design decisions as a new ADR** in `docs/adrs/`, numbered sequentially, using the same
  MADR-lite shape as the existing ones (`# <n>. <title>`, Date, Status, Context, Decision, Consequences). Add a new
  record rather than rewriting an accepted one; supersede it explicitly if it no longer holds.
- **Do not hand-edit `CHANGELOG.md`, `.release-please-manifest.json`, or version strings.** release-please owns them.

[config-conventional]: https://www.npmjs.com/package/@commitlint/config-conventional

## Testing

```sh
pre-commit install --install-hooks   # installs both pre-commit and commit-msg hooks
pre-commit run --all-files
bats tests/
```

`bats` must be on `PATH`: `.pre-commit-config.yaml` has a local hook that shells out to it.

`scripts/compute-floating-tags.sh` is pure and directly unit-testable — cover new parsing behaviour there. Exit code
`2` from it means "this tag is not a stable release, skip", not "failure"; `scripts/move-floating-tags.sh` translates
that into a zero exit with a log line, and tests must keep that distinction intact.

`scripts/move-floating-tags.sh` touches git, so test it against a throwaway repository created in the test's temporary
directory (a local bare repo makes a fine `origin`). Never point a test at a real remote. Use `DRY_RUN=true` to assert
on the moves the script *would* make: it is fully read-only, so a dry-run test should also assert that no local tag
was created and that the remote is unchanged.

Changes to workflow YAML cannot be fully unit-tested. Validate them with `actionlint` (wired into pre-commit) and,
where behaviour matters, by exercising the dogfooding workflow on a branch.

## Release process

1. Conventional commits merge to `main`.
2. `.github/workflows/release.yml` runs the reusable workflow, which runs release-please.
3. release-please opens or updates a release pull request containing the version bump and the changelog.
4. A maintainer merges that pull request. The run triggered by that merge creates the `vX.Y.Z` tag and the GitHub
   release, and a dependent job in the same run force-moves `v1` and `v1.2` onto it.

**The bootstrap release needs at least one `feat:` commit.** The manifest starts at `0.0.0`, and a history of only
`chore:` / `ci:` / `docs:` commits produces no release pull request at all — release-please has nothing to bump. If
the first release never appears, check for a releasable commit type before suspecting the workflow. With
`bump-minor-pre-major` set — and nothing demoting `feat:` to a patch — that first release is `0.1.0` (tag `v0.1.0`,
floating tags `v0` and `v0.1`), and while the version is below `1.0.0` a breaking change bumps the minor rather than
the major.

How the tags move, in `scripts/move-floating-tags.sh`:

- **The remote is authoritative.** The release tag is always force-fetched from the remote before anything is
  computed, so a stale local tag cannot shadow it; a tag missing upstream is a hard error, not a skip.
- **Highest version wins.** Each floating tag moves only if the release tag is the highest stable version the remote
  holds under that prefix. A backport `v1.2.4` published after `v1.3.0` moves `v1.2` and leaves `v1` alone. Floating
  tags never move backwards.
- **The push is atomic.** One `git push --atomic` with per-ref force refspecs: all the floating tags move or none do.
- **`DRY_RUN` is fully read-only** — no local tag is created and nothing is pushed — and is normalised fail-closed,
  so an unrecognised value errors instead of being read as "push".

**Never create, move, or delete tags by hand**, and never push a tag from a local checkout. The workflow owns all tags.
If the floating tags look wrong, fix the workflow and re-run it; do not paper over it with `git push --force`. Full
`vX.Y.Z` tags are immutable and are never deleted except in response to a security incident; see
[SECURITY.md](SECURITY.md).

Note that the release pull request opened with the default `github.token` does not trigger CI — a GitHub anti-recursion
rule, not a bug here. Do not "fix" it by adding `workflow_run` hacks; the documented answer is a fine-grained PAT
supplied as the `token` secret.
