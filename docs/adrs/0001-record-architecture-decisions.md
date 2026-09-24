# 1. Record architecture decisions

Date: 2026-09-24

Status: accepted

## Context

This repository is a small piece of release infrastructure with an unusually large blast radius: consumers pin to it,
let it move tags in their repositories, and inherit its opinions about versioning whether they notice or not. Most of
its design is the product of constraints that are invisible in the code — GitHub's anti-recursion rule for
`GITHUB_TOKEN`, the ecosystem convention around floating tags, the choice to wrap release-please instead of
reimplementing it.

Three audiences keep asking "why is it like this?":

- **Consumers**, who need to decide whether the behaviour is acceptable before they hand over `contents: write`.
- **Contributors**, who will otherwise "simplify" a deliberate decision back into the bug it was written to avoid.
- **AI coding agents**, which read the repository with no institutional memory at all and will happily rewrite a
  constraint they cannot see a reason for.

Commit messages and pull request discussions do hold this information, but it is unfindable six months later, and
comments in YAML are too short to carry the alternatives that were rejected.

## Decision

Record significant architecture decisions as architecture decision records (ADRs) in `docs/adrs/`, in a lightweight
[MADR](https://adr.github.io/madr/)-derived format:

- One file per decision, named `NNNN-kebab-case-title.md`, numbered sequentially from `0001`.
- Header `# <n>. <title>`, followed by `Date:`, `Status:`, then `## Context`, `## Decision`, `## Consequences`.
- Concise — roughly 30 to 60 lines. An ADR that needs more than that is probably two decisions.
- Context states the forces, including the ones that are not obvious; Consequences states the costs honestly, not just
  the benefits.

Records are immutable once accepted. A decision that no longer holds gets a new record that supersedes it, and the old
record's status is updated to point at the replacement. "Significant" means: anything a consumer could notice, anything
that constrains how contributions are written, or anything that will look like a mistake to someone without the
context.

The ADR directory is linked from `README.md` and named in `AGENTS.md` as a required step for significant changes.

## Consequences

- Every non-obvious design choice has a findable, citable answer, and code review can point at a record instead of
  re-arguing it.
- Contributors and agents get an explicit instruction to write a record, which costs a few minutes per significant
  change. Small changes are exempt, and judging what counts as significant stays a matter of taste.
- Keeping records immutable means the directory accumulates history, including decisions that are no longer in force.
  That is the intended trade: superseded records explain why the current design is not the obvious one.
- Consumers auditing this repository before granting it write access can read the reasoning rather than reverse
  engineering it from YAML.
