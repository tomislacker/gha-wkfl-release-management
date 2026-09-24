# Security Policy

## Supported versions

Only the latest release receives security fixes. Consumers pinned to a floating tag (`v1`, `v1.2`)
receive fixes automatically when the tag moves; consumers pinned to a commit SHA must bump their pin.

## Reporting a vulnerability

Please report vulnerabilities privately via [GitHub private vulnerability reporting][gpvr].
Do **not** open a public issue for a security problem.

[gpvr]: https://github.com/tomislacker/gha-wkfl-release-management/security/advisories/new

You can expect an acknowledgement within a few days. Once a fix ships, an advisory will be published
describing the impact and the fixed versions.

## Tag integrity

Full semver tags (`vX.Y.Z`) are immutable and are never deleted or re-pointed **except** in response
to a confirmed security incident, in which case a security advisory will document exactly what was
yanked and why. Floating tags (`vX`, `vX.Y`) move by design; if you need supply-chain immutability,
pin by commit SHA.

## Trust boundaries for consumers

- The composite action's `remote` input must be a trusted, static value. Never wire it to
  untrusted input (PR titles, issue bodies, `workflow_dispatch` inputs from untrusted users).
- Grant the calling workflow only `contents: write` and `pull-requests: write`.
- If you pass a personal access token as the `token` secret, use a fine-grained PAT scoped to the
  releasing repository with only Contents and Pull requests read/write.
