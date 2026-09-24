# 6. Enforce conventional commits

Date: 2026-09-24

Status: accepted

## Context

Version numbers here are derived, not chosen. release-please reads commit messages and decides from them whether the
next release is a patch, a minor, or a major. That makes commit messages executable input rather than prose: a `feat:`
commit mislabelled `fix:` ships a feature as a patch release to everyone pinned to `@v1`, and a breaking change with no
`!` or `BREAKING CHANGE:` footer breaks them silently.

Conventions that are documented but not enforced decay. "Please use conventional commits" in a CONTRIBUTING file
produces a history that is mostly conventional, and release-please quietly ignores everything that is not — so the
failure mode is a missing changelog entry or a wrong bump, neither of which anyone notices until a consumer complains.

There is also a choice about scope. If a repository only ever squash-merges, enforcing the format on the pull request
title alone is sufficient, because the squash commit takes that title. Enforcing on every commit is stricter and lets
rebase-merge stay available, at the cost of asking contributors to tidy their branches.

This repository does not have to choose between the two merge styles, because it enables both. **Squash-merge is
enabled and is the ordinary path**, configured so the squash commit's subject is the pull request title
(`PR_TITLE`) and its body is the pull request body (`PR_BODY`); **rebase-merge is also enabled** for branches whose
individual commits are worth keeping. Merge commits are disabled, so no unconventional "Merge pull request #12 from …"
subject can ever reach `main`. Enforcing on both the title and every commit is what makes that pair of options safe:
whichever button gets pressed, what lands is something release-please can read.

## Decision

[Conventional Commits 1.0.0](https://www.conventionalcommits.org/en/v1.0.0/) is mandatory for **every commit** and for
**every pull request title**. This is enforced in three places:

- **Locally**: a `conventional-pre-commit` hook on the `commit-msg` stage, installed by a plain `pre-commit install`
  because `default_install_hook_types` lists it. The failure arrives at commit time, where it is cheap to fix.
- **In CI**: `wagoid/commitlint-github-action` runs over every commit in the pull request's range. This is the
  authoritative check; the local hook is a convenience and can be bypassed with `--no-verify`.
- **On the pull request title**: `amannn/action-semantic-pull-request`, so that a squash merge produces a conventional
  subject. Since squash-merge is enabled and routinely used, this check is load-bearing, not a contingency. CI listens
  for the `edited` event so retitling re-runs the check.

Enforcing on every commit rather than only the squash title is deliberate: it keeps rebase-merge available, which
preserves a meaningful history where each commit is an independently described, independently revertable change, and it
means every commit that lands on `main` is one release-please can read.

The allowed type list has one source of truth: `@commitlint/config-conventional`, extended by `commitlint.config.mjs`,
which overrides only `header-max-length` (100 → 120, to match this repository's line policy). Documentation that
enumerates types is a copy of that list, not an independent definition of it.

The consequence for contributors is that fix-up commits must be squashed away before review. `git commit --fixup` plus
`git rebase --autosquash` is the intended workflow, and it is documented in the README.

## Consequences

- Version bumps are correct by construction, and `CHANGELOG.md` is generated from real descriptions rather than from
  "wip" and "address review".
- `git log --oneline` is a usable summary of what changed and why.
- Contributors pay a real cost: messages must be written carefully, and messy branches must be rebased before review.
  Newcomers will bounce off the CI check at least once. The README carries examples of both good and rejected messages
  to shorten that.
- CI rejects pull requests for a formatting reason, which can feel pedantic when the code is fine. The rule is applied
  uniformly, including to maintainers, because an exception is what turns "enforced" back into "documented".
- The three enforcement points must agree on the allowed type list. If they drift, contributors get a local pass and a
  CI failure, which is the worst of both.
