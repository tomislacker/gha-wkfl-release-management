# 3. Floating refs are force-moved tags

Date: 2026-09-24

Status: accepted

## Context

Consumers want to pin to a major line (`@v1`) and receive compatible updates without editing their workflows. Something
has to make `v1` and `v1.2` follow the newest matching `vX.Y.Z` release.

The proof of concept that preceded this repository implemented that by managing **GitHub releases**: for each floating
version it deleted the existing `v1` release and created a new one pointing at the latest commit. It worked, but it
had a set of costs that only showed up in use:

- The releases list filled with `v1`, `v1.2` and `v1.2.3` entries, three per release, obscuring the actual history.
- Every delete-and-recreate cycle produced watcher notifications for a release that contained nothing new.
- A `v1` release can carry assets, which raises a question with no good answer: are they copies of `v1.2.3`'s assets,
  stale, or absent? Consumers and tooling cannot tell.
- Delete-then-create is not atomic. A failure between the two steps leaves no `v1` at all.

Meanwhile the GitHub Actions ecosystem already has a convention for this. `actions/checkout`, `actions/setup-node`,
`actions/cache` and essentially every widely used action publish a floating major tag that is force-moved on each
release, with no accompanying release object.

## Decision

Floating major and minor refs are plain **lightweight git tags**, force-moved onto the commit that the full release tag
points at, and pushed in one atomic operation:

```sh
git tag --force v1 "$target"
git tag --force v1.2 "$target"
git push --atomic origin +refs/tags/v1:refs/tags/v1 +refs/tags/v1.2:refs/tags/v1.2
```

No GitHub release object is created, deleted, or modified for a floating version. GitHub releases exist only for
immutable `vX.Y.Z` tags, and release-please owns them.

Three properties of that push matter enough to state explicitly:

- **The remote is authoritative.** The release tag is always re-fetched from the remote with a forced refspec before
  anything is computed, and a tag that does not exist upstream is a hard error rather than a silent success. A stale
  local tag left behind on a long-lived self-hosted runner can therefore never decide where a floating tag lands.
- **Highest version wins; floating tags never move backwards.** Each floating tag moves only when the release tag is
  the highest stable release the remote holds under that prefix, compared with `sort -V`. Releasing a backport
  `v1.2.4` after `v1.3.0` already exists moves `v1.2` and deliberately leaves `v1` where it is, pointing at the
  `v1.3.x` line. The comparison is done per floating tag, so the two can disagree, which is exactly the point.
- **The push is atomic.** Both refs travel in a single `git push --atomic` with per-ref force refspecs: either every
  floating tag moves or none of them does. A ref rejected by a branch-protection rule or a push policy cannot leave
  the remote advertising a half-updated set. Nothing is written locally either until every move has been decided.

Only stable releases get floating tags. A tag that is not `X.Y.Z` or `vX.Y.Z` — a prerelease, anything carrying build
metadata, or anything with a leading zero in a numeric field, which semver forbids — is skipped with a log line and a
zero exit, so prerelease pipelines do not fail. The tag's prefix style is preserved: `v1.2.3` yields `v1` and `v1.2`,
while a bare `1.2.3` yields `1` and `1.2`.

`DRY_RUN` is fully read-only: it inspects the remote and logs the moves it would make, creating no local tag and
pushing nothing. It is also normalised fail-closed — `true`/`yes`/`1` enable it, `false`/`no`/`0`/empty disable it,
and any other value is a hard error rather than a value that quietly reads as "go ahead and push".

## Consequences

- The releases page shows one entry per actual release. The changelog is readable.
- No notification churn: force-moving a tag is silent for watchers.
- No question about what assets a floating version carries, because it carries none.
- The operation is idempotent — re-running with the same tag is a no-op success — and both tags move in a single
  atomic push, so there is no window in which `v1` and `v1.2` disagree about the release they name.
- **Consumers see `v1` move under them.** A workflow pinned to `@v1` will run different code tomorrow than it ran
  today. This is the expected, ecosystem-standard behaviour and it is documented in the README's tag policy, but it is
  genuinely a supply-chain trade-off: consumers who want immutability must pin to a full tag or a commit SHA.
- A floating tag never regresses, so a patch released onto an older line does not drag consumers of `@v1` backwards.
  The cost is a maintenance line whose `v1.2` tag is current while `v1` points elsewhere; that is correct, but it does
  mean "the newest release" and "what `v1` points at" are not always the same commit.
- Deciding the move requires a `git ls-remote` per floating tag, so the script needs network access to the remote even
  in a dry run. It cannot answer "should this move?" from a local clone alone, by design.
- Anyone auditing the repository sees force-pushed tags in the reflog, which is normal here and would be alarming
  anywhere else.
