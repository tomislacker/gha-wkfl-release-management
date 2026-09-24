# Contributing

Contributions are welcome. **By contributing you agree that your contribution is licensed under Apache-2.0**, the same
licence as this project (inbound = outbound, per section 5 of the licence). You retain copyright of your work.

## How changes land

`main` is protected by a repository ruleset: every change lands through a pull request, and all four CI checks
(`pre-commit`, `bats tests`, `Commit messages`, `Pull request title`) must pass before merging. There is no bypass —
this applies to the maintainer too.

Both squash-merge and rebase-merge are enabled: under rebase-merge your commits land on `main` exactly as written,
and under squash-merge the pull request title becomes the commit subject and its body becomes the commit body. Either
way the conventional format is enforced, and either way what lands is what release-please reads.

## Development setup

```sh
pip install pre-commit          # or: brew install pre-commit
pre-commit install --install-hooks
bats tests/
```

`pre-commit install` wires up **both** hook types — `pre-commit` and `commit-msg` — because
`.pre-commit-config.yaml` sets `default_install_hook_types`. The `commit-msg` hook is the one that validates your
commit messages locally, which saves you from finding out in CI. You also need
[bats-core](https://bats-core.readthedocs.io/) on your `PATH`; the lint run shells out to it. Run
`pre-commit run --all-files` and `bats tests/` before you push.

## Style rules

- **Markdown and YAML lines wrap at 120 characters**, enforced by `markdownlint` and `yamllint` in pre-commit.
- **Shell follows the same 120 columns by convention**: `.editorconfig` sets `max_line_length = 120` for every file
  type, but no hook enforces it for `*.sh` — your editor is the only thing keeping you honest there.
- **Shell must pass `shellcheck` and `shfmt`** (both run in pre-commit).
- **Never interpolate `${{ }}` expressions into a workflow `run:` body** — pass values through `env:` instead. This
  is script-injection hardening, not a style preference.
- **Significant design changes get an ADR** in [`docs/adrs/`](docs/adrs/), following the existing MADR-lite format.

## Conventional commits are mandatory

**Every commit message and every pull request title must follow
[Conventional Commits 1.0.0](https://www.conventionalcommits.org/en/v1.0.0/). CI rejects violations and the pull
request cannot merge until they are fixed.** This is not a style preference: the commit messages are the input to the
version-bump logic. A commit that lies about its type ships the wrong version number to every consumer.

Good:

```text
feat: add dry-run input to the reusable workflow

fix(scripts): peel annotated tags before comparing commits

feat!: drop support for tags without a v prefix

BREAKING CHANGE: bare 1.2.3 tags are no longer recognised; use v1.2.3.
```

Bad — these will get a pull request rejected:

```text
fixed it, trying again
wip
Update README.md
feat add thing          # no colon
Feat: add thing         # type must be lowercase
misc: cleanup           # not an allowed type
```

The commit **subject line must be at most 120 characters**. `commitlint.config.mjs` raises
`@commitlint/config-conventional`'s default of 100 to match this repository's line policy, and CI enforces it. The
local `commit-msg` hook checks the conventional format but **not** the length, so an over-long subject passes locally
and fails in CI — keep subjects short and put the detail in the body.

Keep the history clean. Fix-up commits ("address review", "lint", "trying again") are fine while you work, but
`git rebase -i` them away — or use `git commit --fixup` plus `git rebase --autosquash` — before you ask for review.
