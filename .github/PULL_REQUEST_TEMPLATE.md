# Summary

<!-- What changes and why. Link any related issue. -->

## Type of change

<!--
Tick the conventional-commit type(s) this pull request uses. The authoritative list is whatever
@commitlint/config-conventional accepts (extended by commitlint.config.mjs); the types below are that list, grouped.
-->

- [ ] `feat:` — new functionality (minor bump)
- [ ] `fix:` — bug fix (patch bump)
- [ ] `feat!:` / `fix!:` / `BREAKING CHANGE:` footer — breaking change (major bump once at 1.0.0; minor while 0.x)
- [ ] `docs:` — documentation only
- [ ] `test:` — tests only
- [ ] `refactor:` / `perf:` / `style:` — no behaviour change
- [ ] `revert:` — reverts an earlier commit
- [ ] `ci:` / `build:` / `chore:` — tooling, workflows, dependencies

## Checklist

- [ ] Every commit message and this pull request's title follow
      [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/), with subjects of 120 characters or
      fewer; fix-up commits have been squashed away
- [ ] `pre-commit run --all-files` passes
- [ ] `bats tests/` passes, and tests were added or updated for the change
- [ ] Documentation is updated if behaviour changed, and a new ADR was added to `docs/adrs/` if a design decision
      changed
- [ ] Any new third-party action is pinned to a full commit SHA with a tag comment
