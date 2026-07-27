const assert = require('node:assert/strict');
const test = require('node:test');
const { parseSlackAllowedUserIds } = require('../allowlist');

test('accepts a comma-separated Slack allowlist', () => {
  assert.deepEqual(
    parseSlackAllowedUserIds('U111AAA, W222BBB, U111AAA'),
    ['U111AAA', 'W222BBB'],
  );
});

test('rejects an empty allowlist', () => {
  assert.throws(() => parseSlackAllowedUserIds(''), /required/);
});

test('rejects malformed member IDs', () => {
  assert.throws(() => parseSlackAllowedUserIds('U111AAA,not-a-member'), /member IDs/);
});
