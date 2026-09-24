# 4. Ship a reusable workflow and a composite action

Date: 2026-09-24

Status: accepted

## Context

Two audiences want different amounts of this project. Most consumers want the whole pipeline: conventional commits in,
release pull request, tag, GitHub release, floating tags moved. A smaller group already has a release process they are
happy with — a monorepo tool, a hand-rolled tagging job, something internal — and only wants the floating-tag logic
bolted onto it.

Serving only the first group forces the second to copy the shell scripts, which guarantees they drift. Serving only the
second leaves everyone else to wire up release-please themselves, which was rejected in
[ADR 0002](0002-wrap-release-please-for-versioning.md).

Shipping both raises the question of where the logic lives. If the reusable workflow inlines its own copy of the
floating-tag bash, the composite action and the workflow are two implementations of the same behaviour that must be
kept in sync by hand — and only one of them has tests pointed at it.

There is a second, subtler problem specific to reusable workflows. A reusable workflow runs from the ref the consumer
pinned, but if it needs files from its own repository — the scripts — a naive `actions/checkout` inside it checks out
the **consumer's** repository, not this one. Checking out this repository at a hardcoded branch or tag would mean a
consumer pinned to `@v1.0.0` could silently execute scripts from `main`, which defeats the point of pinning.

## Decision

Ship two surfaces backed by one implementation:

- **`.github/workflows/release-management.yml`** — the reusable workflow (`on: workflow_call`). Runs release-please,
  then the floating-tag logic.
- **`action.yml`** at the repository root — a composite action exposing only the floating-tag logic, with inputs
  `tag`, `remote`, and `dry-run`. Usable standalone by any workflow that has the repository checked out with
  push-capable credentials and `permissions: contents: write`.

Both execute the same scripts under `scripts/`, which take their inputs from environment variables and are unit-tested
with bats. Inlining the bash into the workflow was considered and rejected: duplication with the action, and no test
coverage for the duplicate.

For self-consistency, the reusable workflow checks out **its own source** — the repository and commit the running
reusable workflow was loaded from — using the `job.workflow_repository` and `job.workflow_sha` context properties
GitHub added in September 2026. A consumer pinned to `@v1.0.0` therefore runs the scripts as they existed at
`v1.0.0`, and a consumer pinned to a SHA runs exactly that SHA's scripts. The workflow ref and the code it executes
cannot diverge.

Both values are **validated fail-closed** in a step of their own before the checkout: `job.workflow_sha` must match
`^[0-9a-f]{40}$` and `job.workflow_repository` must look like an `owner/repo` slug, or the job errors out. This is the
load-bearing part. `actions/checkout` treats an empty `ref:` as "the default branch" and an empty `repository:` as
"the calling repository", so an unpopulated context would not fail — it would silently execute unpinned code from a
mutable branch on the consumer's runner, with `contents: write`. Refusing to run is the only acceptable response.

Resolving the repository from context rather than hardcoding `tomislacker/gha-wkfl-release-management` also makes the
workflow **fork-safe**: a fork's reusable workflow checks out the fork's own scripts, with nothing to edit and nothing
pointing back at upstream.

## Consequences

- One implementation, one test suite, two entry points. Fixing a bug in `scripts/` fixes it for both surfaces
  simultaneously.
- Pinning means what consumers think it means: the workflow ref determines the script contents, with no hidden
  dependency on a mutable branch.
- The composite action is a supported public interface, so its inputs are subject to the same semver promises as the
  workflow's. Renaming an input is a breaking change.
- The `job.workflow_*` properties are populated inside a called reusable workflow. The workflow cannot usefully be run
  directly via `workflow_dispatch` without a fallback, and this repository's dogfooding workflow must call it rather
  than duplicate it.
- **GitHub Enterprise Server is not supported.** Neither `job.workflow_repository` nor `job.workflow_sha` exists
  there, so the validation step fails and the floating-tag job stops. That failure is deliberate: the alternative
  under a fail-open design is executing whatever is on a branch today. Forks and github.com consumers are unaffected.
- actionlint v1.7.12 predates these properties and reports them as undefined, so `.github/actionlint.yaml` suppresses
  exactly those two messages on exactly this workflow. That suppression has to be revisited when actionlint catches
  up.
- An earlier draft of this ADR and of the workflow used `github.job_workflow_sha`, a context property that does not
  exist — a plausible-looking name that would have evaluated to the empty string and taken the silent
  default-branch path described above. Adversarial review caught it; the fail-closed validation exists so that the
  next such mistake stops the job instead of shipping.
- The extra checkout of this repository costs a few seconds per release run, and consumers see a second repository in
  the job's checkout steps. That is a fair price for the guarantee.
