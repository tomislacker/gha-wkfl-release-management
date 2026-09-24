# gha-wkfl-release-management

[![CI][ci-badge]][ci]
[![Latest release][release-badge]][release]
[![License: Apache 2.0][license-badge]][license]
[![Conventional Commits][cc-badge]][cc]

[ci-badge]: https://github.com/tomislacker/gha-wkfl-release-management/actions/workflows/ci.yml/badge.svg
[ci]: https://github.com/tomislacker/gha-wkfl-release-management/actions/workflows/ci.yml
[release-badge]: https://img.shields.io/github/v/release/tomislacker/gha-wkfl-release-management?sort=semver
[release]: https://github.com/tomislacker/gha-wkfl-release-management/releases/latest
[license-badge]: https://img.shields.io/badge/License-Apache_2.0-blue.svg
[license]: LICENSE
[cc-badge]: https://img.shields.io/badge/Conventional%20Commits-1.0.0-yellow.svg
[cc]: https://www.conventionalcommits.org/en/v1.0.0/

A reusable GitHub Actions workflow that turns conventional commits into releases and keeps floating version tags
pointing at them. It wraps [release-please](https://github.com/googleapis/release-please-action) to maintain a release
pull request and a changelog, and — in the same run, as soon as that pull request merges and the `vX.Y.Z` tag exists —
force-moves the matching `v1` and `v1.2` tags so consumers who pin to a major or minor line get the new release without
doing anything. The floating-tag half is also published on its own as a composite action for repositories that already
have a release process they like.

## How it works

Commit messages decide the version. Once a project is at `1.0.0` or above, `fix:` bumps the patch, `feat:` bumps the
minor, and a `!` marker or a `BREAKING CHANGE:` footer bumps the major. (Below `1.0.0`, release-please's
`bump-minor-pre-major` option changes that mapping — see [Versioning & tag policy](#versioning--tag-policy) for how it
applies to *this* project.) release-please accumulates those commits into a release pull request that carries the
version bump and the changelog entries; nothing is released until a human merges it.

```text
  conventional commits on main
              |
              v
    release-please opens/updates
      the release pull request         <-- human review checkpoint
              |
         (you merge it)
              v
    tag v1.2.3 + GitHub release
              |
              v
    floating tags force-moved:
      v1   -> v1.2.3
      v1.2 -> v1.2.3
```

1. You merge conventional commits into the default branch.
2. The reusable workflow runs release-please, which opens or updates a release pull request for the pending version.
3. You review and merge that pull request when you want to ship.
4. The next run of the workflow sees `release_created == true`, creates the `vX.Y.Z` tag and the GitHub release.
5. A dependent job in that **same workflow run** force-moves `v1` and `v1.2` onto the release commit and force-pushes
   them.

Steps 4 and 5 happen in one workflow run on purpose: a tag created with the default `GITHUB_TOKEN` does not trigger
another workflow, so a separate `on: push: tags` workflow would never fire. See
[ADR 0002](docs/adrs/0002-wrap-release-please-for-versioning.md).

## Usage

> **The snippets below are pinned to the [latest release][latest] for you** — after each release, the release
> workflow rewrites them with that release's literal commit SHA (`scripts/update-readme-pins.sh`), so they are
> copy-paste ready. Keep the trailing comment naming the tag when you take them: the reference stays readable and
> auditable, and Dependabot understands the format and will bump both the SHA and the comment.

[latest]: https://github.com/tomislacker/gha-wkfl-release-management/releases/latest

### Reusable workflow

```yaml
name: Release
on:
  push:
    branches: [main]
permissions:
  contents: write
  pull-requests: write
concurrency:
  group: release-${{ github.ref }}
  cancel-in-progress: false
jobs:
  release:
    uses: tomislacker/gha-wkfl-release-management/.github/workflows/release-management.yml@93c3b6b615219c9a1588a643af62b2f63e7695ad # v0.1.0
```

The reusable workflow deliberately sets no `concurrency` of its own — serialising release runs is the caller's
decision, so declare it in your workflow as above. `cancel-in-progress: false` matters: cancelling a run midway can
leave a release tagged with its floating tags unmoved.

Two things must be true in the calling repository:

- The job (or the workflow) grants `permissions: contents: write` and `permissions: pull-requests: write`.
- **Settings → Actions → General → "Allow GitHub Actions to create and approve pull requests" is enabled.** Without it
  release-please cannot open its release pull request and the run fails. On an organisation-owned repository this may
  have to be enabled at the organisation level first.

You also need release-please's own configuration committed to the calling repository — by default
`release-please-config.json` and `.release-please-manifest.json` at the repository root. See the
[release-please configuration reference][rp-config].

[rp-config]: https://github.com/googleapis/release-please/blob/main/docs/manifest-releaser.md

### Supported setups

- **Single-package release-please configurations only.** The workflow reads release-please's root-component outputs
  (`release_created`, `tag_name`), so a config whose `packages` map is just `"."` works. In a monorepo config that
  releases path-prefixed components, release-please still releases and tags every component normally — but the
  per-component outputs are not read, so **no floating tags are moved** for them. The run succeeds; the floating tags
  are silently skipped.
- **github.com only; GitHub Enterprise Server is not supported.** The floating-tag job identifies the reusable
  workflow's own source commit through the `job.workflow_repository` and `job.workflow_sha` contexts, which GHES does
  not provide. Rather than falling back to whatever is on a branch, the job validates them and **fails closed** on
  GHES. See [ADR 0004](docs/adrs/0004-reusable-workflow-plus-composite-action.md).
- **Forks work out of the box.** Nothing about the source repository is hardcoded: the tools checkout follows whatever
  repository the calling workflow's `uses:` line points at, so a fork runs its own scripts with no edits.

### Standalone composite action

Use this when you already create `vX.Y.Z` tags some other way and only want the floating tags maintained.

```yaml
jobs:
  float:
    runs-on: ubuntu-latest
    permissions:
      contents: write
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
      - uses: tomislacker/gha-wkfl-release-management@93c3b6b615219c9a1588a643af62b2f63e7695ad # v0.1.0
        with:
          tag: ${{ github.ref_name }}
```

The action runs `git` in the current working directory, so the repository that owns the tags must already be checked
out there with push-capable credentials — `actions/checkout` with its default `persist-credentials: true`, or an
explicitly configured token or deploy key. A tag that is not a stable `X.Y.Z` / `vX.Y.Z` release — a prerelease,
anything carrying build metadata, or anything with a leading zero in a numeric field, which semver forbids — is
skipped with a log line rather than failing the job.

### Reusable workflow reference

Inputs:

| Name | Type | Default | Description |
| --- | --- | --- | --- |
| `config-file` | string | `release-please-config.json` | Path to the release-please config. |
| `manifest-file` | string | `.release-please-manifest.json` | Path to the release-please manifest. |
| `target-branch` | string | `""` | Branch to release from. Empty lets release-please detect the default branch. |
| `dry-run` | boolean | `false` | Inspect and log the floating-tag moves without making any change. |

`dry-run` applies **only to the floating tags**, and for that step it is fully read-only: the remote is inspected, the
moves that would happen are logged, and nothing is written locally or pushed. release-please itself still runs for
real, so the release pull request, the `vX.Y.Z` tag, and the GitHub release are all created as normal. This is not a
way to rehearse a release; it is a way to watch the tag arithmetic.

Secrets:

| Name | Required | Description |
| --- | --- | --- |
| `token` | no | Token for the release pull request, the release, and the tag pushes. Defaults to `github.token`. |

Outputs:

| Name | Description |
| --- | --- |
| `release_created` | `true` when this run cut a release (the release pull request had just been merged). |
| `tag_name` | The full release tag, e.g. `v1.2.3`. Empty when no release was created. |
| `version` | The released version without the `v` prefix, e.g. `1.2.3`. Empty when no release was created. |

### Composite action reference

| Input | Required | Default | Description |
| --- | --- | --- | --- |
| `tag` | yes | — | Full release tag to derive the floating tags from, e.g. `v1.2.3`. |
| `remote` | no | `origin` | Git remote to fetch the release tag from and push the floating tags to. |
| `dry-run` | no | `"false"` | When `"true"`, inspect and log the moves, changing nothing locally or remotely. |

The action has no outputs. It is idempotent: re-running it with the same `tag` is a no-op success.

`remote` **must be a trusted, static value.** It is passed to `git`, and a remote string an untrusted contributor can
influence is a code-execution vector — never wire it to a pull request title, an issue body, or a
`workflow_dispatch` input. The script rejects option-shaped remotes and passes `--end-of-options` as defence in depth,
but that is a backstop, not a licence to pass through untrusted data. See [SECURITY.md](SECURITY.md).

`dry-run` accepts `"true"` and `"false"`. `"yes"`/`"1"` and `"no"`/`"0"`/`""` are tolerated as case-insensitive
synonyms; **any other value is a hard error** rather than being quietly read as "not a dry run". The same
normalisation applies to the reusable workflow's boolean input.

## Versioning & tag policy

This repository is versioned with [semantic versioning](https://semver.org/) and publishes three kinds of ref:

- **Full tags — `v1.2.3`.** Immutable. Once pushed, a full release tag never changes what it points at.
- **Floating minor tags — `v1.2`.** Force-moved to the newest patch release in that minor line on every release.
- **Floating major tags — `v1`.** Force-moved to the newest release in that major line on every release.

Pinning to `@v1` therefore means "give me the latest backwards-compatible release", and that ref *will* change under
you — that is the point, and it is the same convention `actions/checkout` and the rest of the ecosystem use. If you do
not want that, pin to `@v1.2.3` or, better, to a commit SHA.

**Floating tags never move backwards.** A floating tag only moves when the release being published is the highest
stable version the remote holds under that prefix. So if `v1.3.0` already exists and a backport `v1.2.4` is released
afterwards, `v1.2` moves to the backport and `v1` stays on the `v1.3.x` line — consumers pinned to `@v1` are never
dragged back to older code. Both tags are pushed with a single atomic push, so they are never left half-updated.

### While this project is below 1.0.0

Its own version is currently in the `0.x` range, where the usual semver promises do not apply and this repository's
release-please config bends the rules to match:

- `feat:` bumps the **minor** (`0.1.0` → `0.2.0`); the first release from the initial `0.0.0` manifest is `0.1.0`.
- `fix:` bumps the patch.
- A breaking change bumps the **minor, not the major**. The major stays at `0` until the interface is promoted to
  `1.0.0` by hand.

The practical consequence: **`v0` moves across breaking changes.** Until `1.0.0` ships, pin to `v0.x` (e.g. `@v0.1`)
or to a commit SHA, not to `@v0`. See
[ADR 0002](docs/adrs/0002-wrap-release-please-for-versioning.md).

**Tags are never yanked or deleted.** The only exception is a security incident: if a published release is found to be
actively dangerous, tags may be moved or removed, and a
[GitHub security advisory](https://github.com/tomislacker/gha-wkfl-release-management/security/advisories) will explain
what happened and what to do. Nothing else — not a bad release, not an embarrassing bug — will cause a tag to
disappear; those get a new patch release instead. The full policy, including how to report a vulnerability privately,
is in [SECURITY.md](SECURITY.md).

**Recommendation: pin by commit SHA.** A SHA cannot be repointed at different code by anyone, including this
repository's maintainers. Tags can. See [ADR 0005](docs/adrs/0005-sha-pin-third-party-actions.md) for why we apply the
same rule to our own dependencies.

## The `GITHUB_TOKEN` limitation

By design, GitHub does not let events created with the default `GITHUB_TOKEN` trigger further workflow runs. That
anti-recursion rule has one consequence you will notice immediately and one you will not:

- **You will notice:** the release pull request that release-please opens does **not** run your CI workflows. It sits
  there with no checks. If you have required status checks, it cannot be merged without an administrator override.
- **You will not notice:** the `vX.Y.Z` tag push does not trigger `on: push: tags` workflows either. This workflow
  works around that by moving the floating tags in the same workflow run rather than in a tag-triggered workflow, so
  you do not have to care.

To get CI on release pull requests, pass a token that is not `GITHUB_TOKEN`:

1. Create a [fine-grained personal access token](https://github.com/settings/personal-access-tokens) scoped to the
   repository (or repositories) you release, with **Contents: read & write** and **Pull requests: read & write**
   repository permissions.
2. Store it as a repository or organisation secret, e.g. `RELEASE_PLEASE_TOKEN`.
3. Pass it through to the reusable workflow:

```yaml
jobs:
  release:
    uses: tomislacker/gha-wkfl-release-management/.github/workflows/release-management.yml@93c3b6b615219c9a1588a643af62b2f63e7695ad # v0.1.0
    secrets:
      token: ${{ secrets.RELEASE_PLEASE_TOKEN }}
```

A token belonging to a machine account is preferable to one belonging to a human: it survives people leaving, and it
keeps the release pull request's authorship honest. Remember that fine-grained tokens expire — put the expiry in your
calendar.

## Security

[SECURITY.md](SECURITY.md) is the authority: how to report a vulnerability privately, which versions get fixes, the
tag-yank policy, and the trust boundaries this workflow assumes of its consumers. In short — report privately through
[GitHub's private vulnerability reporting][pvr] rather than in a public issue; grant the calling workflow no more than
`contents: write` and `pull-requests: write`; and treat the composite action's `remote` input as a trusted, static
value.

[pvr]: https://github.com/tomislacker/gha-wkfl-release-management/security/advisories/new

## Contributing

Contributions are welcome — see [CONTRIBUTING.md](CONTRIBUTING.md) for the full guide (development setup, style
rules, and clean-history expectations). The short version:

- **By contributing you agree your contribution is licensed under Apache-2.0** (inbound = outbound). You retain
  copyright of your work.
- Every commit message and pull request title **must** follow
  [Conventional Commits 1.0.0](https://www.conventionalcommits.org/en/v1.0.0/) — they drive the version-bump logic,
  and CI rejects violations.
- `main` only accepts pull requests whose CI checks pass. There is no bypass, including for the maintainer.
- Set up once with `pre-commit install --install-hooks`; run `pre-commit run --all-files` and `bats tests/` before
  you push.

## Architecture decisions

Significant design decisions are recorded openly as MADR-style architecture decision records in
[`docs/adrs/`](docs/adrs/). If you are wondering why something works the way it does, the answer is probably there —
and if you are changing something significant, add a new ADR rather than editing the old one.

| ADR | Decision |
| --- | --- |
| [0001](docs/adrs/0001-record-architecture-decisions.md) | Record architecture decisions |
| [0002](docs/adrs/0002-wrap-release-please-for-versioning.md) | Wrap release-please for versioning |
| [0003](docs/adrs/0003-floating-refs-are-force-moved-tags.md) | Floating refs are force-moved tags |
| [0004](docs/adrs/0004-reusable-workflow-plus-composite-action.md) | Ship a reusable workflow and a composite action |
| [0005](docs/adrs/0005-sha-pin-third-party-actions.md) | SHA-pin third-party actions |
| [0006](docs/adrs/0006-conventional-commits-enforced.md) | Enforce conventional commits |
| [0007](docs/adrs/0007-agent-rules-single-sourced-in-agents-md.md) | Agent rules are single-sourced in AGENTS.md |

## Donations

Please do not send money here. If this project saved you enough time that you feel like paying for it, donate on our
behalf to an organisation that defends free and open-source software:

- [Electronic Frontier Foundation](https://www.eff.org/donate)
- [Software Freedom Conservancy](https://sfconservancy.org/donate/)
- [Free Software Foundation](https://www.fsf.org/about/ways-to-donate/)

Tell them what it was for, or do not — either way it is worth more there than it would be here.

## Contributors

[![Contributors][contributors-badge]][contributors]

[contributors-badge]: https://contrib.rocks/image?repo=tomislacker/gha-wkfl-release-management
[contributors]: https://github.com/tomislacker/gha-wkfl-release-management/graphs/contributors

![Repobeats analytics][repobeats]

[repobeats]: https://repobeats.axiom.co/api/embed/1cd41dfdb700f91bdd3ff1cd6902e404c2ed7357.svg

## License

Apache License 2.0 — see [LICENSE](LICENSE).
