// Loaded by wagoid/commitlint-github-action in CI. Must be .mjs — the action
// rejects .js config files.
// config-conventional defaults header-max-length to 100; this repo's line policy is 120.
export default {
  extends: ['@commitlint/config-conventional'],
  rules: {
    'header-max-length': [2, 'always', 120],
  },
};
