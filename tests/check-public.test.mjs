import test from 'node:test';
import assert from 'node:assert/strict';
import { checkPublic } from '../scripts/check-public.mjs';

test('Cloud check uses the baseline accepted on remote main', async () => {
  const now = Date.now();
  const snapshot = {
    acceptedBaseline: { cliRelease: 'clay-cli-v1.13.0', files: {}, reviewedCommit: 'reviewed' },
    cliRelease: 'clay-cli-v1.13.0', files: {}, installerMatches: true,
    run: { created_at: new Date(now).toISOString() },
    jobs: ['powershell', 'linux-forwarder'].map(name => ({ name, conclusion: 'success' }))
  };
  assert.equal((await checkPublic(async () => snapshot, now)).status, 'healthy');
  assert.equal((await checkPublic(async () => ({ ...snapshot, cliRelease: 'clay-cli-v1.14.0' }), now)).status, 'review_required');
});

test('failed collection is not treated as a healthy check', async () => {
  await assert.rejects(checkPublic(async () => { throw new Error('unavailable'); }), /unavailable/);
});
