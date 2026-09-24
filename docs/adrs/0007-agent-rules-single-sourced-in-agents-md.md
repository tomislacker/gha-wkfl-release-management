# 7. Agent rules are single-sourced in AGENTS.md

Date: 2026-09-24

Status: accepted

## Context

AI coding tools each discover project rules from their own location: Claude Code auto-loads `CLAUDE.md`, Cursor loads
`.cursor/rules/*.mdc`, GitHub Copilot reads `.github/copilot-instructions.md`. This repository has rules that agents
must not miss — the SHA-pinning policy (ADR 0005), the lint gates, the tag-handling rules (ADR 0003), and the
conventional-commit requirements (ADR 0006). Maintaining a full copy of those rules per tool guarantees drift: a rule
updated in one file and not the others silently teaches different tools different behavior.

## Decision

[`AGENTS.md`](../../AGENTS.md) is the single authoritative rule set for AI agents. Every tool-specific entry point is
a **thin pointer** that imports or references it and adds nothing of its own:

- `CLAUDE.md` imports `AGENTS.md` via Claude Code's `@` include syntax.
- `.cursor/rules/agents-md.mdc` is an `alwaysApply` rule referencing `@AGENTS.md`, with a five-bullet digest whose
  entries name their ADR rather than restating it.
- `.github/copilot-instructions.md` links to `AGENTS.md`.

New rules are added to `AGENTS.md` (with an ADR when the rule reflects a design decision). A new tool gets a new
pointer file, never a new copy of the rules.

## Consequences

- A rule change is a one-file edit that reaches every tool at once.
- The pointer files must stay thin. Content accumulating in them is drift by another name; reviewers should push such
  additions into `AGENTS.md`.
- The Cursor digest is the one deliberate exception (Cursor weighs rule text directly); it names ADR numbers so a
  reader is pulled to the authoritative text rather than trusting the summary.
- Agents that read none of these files still hit the same rules the hard way: CI enforces commits, titles, and lint
  regardless of what the agent knew.
