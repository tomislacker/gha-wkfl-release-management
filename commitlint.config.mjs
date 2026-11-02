// Loaded by wagoid/commitlint-github-action in CI. Must be .mjs — the action
// rejects .js config files.
// config-conventional defaults header-max-length to 100; this repo's line policy is 120.
// Dependabot-generated dependency update bodies include long URLs and release-note text,
// so allow longer body lines than the default commitlint rules.
export default {
  extends: ['@commitlint/config-conventional'],
  rules: {
    'header-max-length': [2, 'always', 120],
    'body-max-line-length': [2, 'always', 200],
  },
};
