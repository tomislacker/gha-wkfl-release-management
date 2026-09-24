# 5. SHA-pin third-party actions

Date: 2026-09-24

Status: accepted

## Context

This project runs with `contents: write` in other people's repositories and force-pushes tags there. Anything it
executes inherits that authority, so every third-party action it calls is a link in its consumers' supply chains.

A `uses:` reference to a tag or a branch is a reference to a mutable pointer. Git tags can be force-moved — this
project does exactly that to `v1` and `v1.2`, see [ADR 0003](0003-floating-refs-are-force-moved-tags.md) — so an
attacker who compromises an upstream maintainer account, or an upstream maintainer having a bad day, can change what
`@v4` means without publishing anything that looks like a release. The `tj-actions/changed-files` compromise in March
2025 was precisely this: existing tags were repointed at malicious code, and every workflow referencing them by tag
executed it on the next run. There is no announcement, no diff in the consumer's repository, and no way to notice by
reading the workflow file.

A full commit SHA is content-addressed. It cannot be repointed by anyone, including the upstream maintainer.

Separately, this project is Apache-2.0 and is intended to be usable inside organisations with licence-compliance
review. Every dependency needs a licence that survives that review.

## Decision

Every third-party action referenced from a workflow `uses:` line in this repository is pinned to a **full 40-character
commit SHA**, with a trailing comment naming the tag that SHA corresponds to:

```yaml
- uses: actions/checkout@<full-40-character-commit-sha> # v7.0.1
```

The comment is not decoration: it is what makes the pin reviewable by a human and what Dependabot updates alongside the
SHA. Short SHAs are not acceptable. Branch and tag references are not acceptable, including for actions published by
GitHub itself.

The mandate is scoped to workflow `uses:` references. It does not extend to `.pre-commit-config.yaml`, for the reason
recorded under "Recorded exceptions" below.

The full current dependency set:

| Action | Where | Licence |
| --- | --- | --- |
| `actions/checkout` | `release-management.yml`, `ci.yml` | MIT |
| `actions/setup-python` | `ci.yml` | MIT |
| `actions/cache` (`/restore`, `/save`) | `ci.yml` | MIT |
| `googleapis/release-please-action` | `release-management.yml` | Apache-2.0 |
| `bats-core/bats-action` | `ci.yml` | MIT |
| `wagoid/commitlint-github-action` | `ci.yml` | MIT |
| `amannn/action-semantic-pull-request` | `ci.yml` | MIT |
| `crazy-max/ghaction-github-labeler` | `labels.yml` | MIT |

Every dependency must carry an OSI-approved free/open-source licence. The actions above are all MIT or Apache-2.0.
That claim is about the `uses:` set only — the development tooling pulled in through `.pre-commit-config.yaml`
includes GPL-3.0 software (`yamllint`, `shellcheck`). All of it is OSI-approved, none of it is distributed as part of
a release or executed in a consumer's workflow, and a copyleft lint tool imposes nothing on this project's Apache-2.0
licensing.

### Recorded exceptions

Three references are not full SHA pins. Each is accepted knowingly rather than overlooked:

1. **`wagoid/commitlint-github-action` is a Docker action.** Its SHA pin fixes the wrapper repository, but the
   `action.yml` at that commit runs `docker://wagoid/commitlint-github-action:6.2.1` — a **mutable Docker Hub tag**.
   Whoever controls that tag controls what executes, and the SHA pin does not prevent it. Accepted because the job
   runs only on `pull_request` with `contents: read` and `pull-requests: read` and holds no write credential, so the
   blast radius is a lying lint result rather than a compromised release.
2. **`pre-commit` hook `rev:` entries are version tags, not SHAs.** That is the pre-commit convention and what
   `pre-commit autoupdate` writes; SHA-pinning them makes updates manual and unreadable for no gain on a tool that
   runs on a developer machine and in a read-only CI job. Hook environments are also cached by config hash, so a
   retagged upstream shows up as a cache miss.
3. **`bats` is pinned by version, not SHA.** `bats-core/bats-action` itself is SHA-pinned, but the interpreter it
   installs is selected by its `bats-version: "1.14.0"` input, which is a version string by design.

Dependabot is configured for the `github-actions` ecosystem and maintains the pins, opening pull requests that update
both the SHA and the comment. Those pull requests are reviewed like any other change: the point of pinning is lost if
updates are merged unread.

The README applies the same rule outward, telling consumers to pin **this** project by SHA rather than by `@v1`.

## Consequences

- An upstream tag rewrite cannot change what this project executes. Compromise requires a merged pull request in this
  repository, which is visible and reviewable.
- `uses:` lines are unreadable without their comments, and the comments are only trustworthy because tooling maintains
  them. A hand-written comment that lies about the tag is a real failure mode; reviewers should verify updates come
  from Dependabot or check the SHA.
- Dependency updates require merged pull requests rather than happening silently, which is more maintenance work and is
  the intended trade.
- Consumers who pin this project by SHA as recommended get the same guarantee, at the cost of not receiving automatic
  updates — Dependabot handles that for them too.
