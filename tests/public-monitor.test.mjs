import test from "node:test";
import assert from "node:assert/strict";
import { assessSnapshot } from "../scripts/public-monitor.mjs";
const now = Date.parse("2026-10-16T09:00:00Z");
const baseline = { reviewedCommit: "old", cliRelease: "clay-cli-v1.10.0", files: { "clay/cli-min-version": "minimum" } };
const snapshot = { files: { ...baseline.files }, upstreamCommit: "new", cliRelease: baseline.cliRelease, installerMatches: true,
  pendingRun: false, run: { created_at: "2026-10-15T12:30:00Z", html_url: "https://example.invalid/run" },
  jobs: [{ name: "powershell", conclusion: "success" }, { name: "linux-forwarder", conclusion: "success" }] };
test("unchanged public metadata and recent platform checks are healthy", () => {
  assert.equal(assessSnapshot(baseline, snapshot, now).status, "healthy");
});
test("a review-only upstream alert is not misreported as broken Windows/Linux tests", () => {
  const result = assessSnapshot(baseline, { ...snapshot, jobs: [...snapshot.jobs, { name: "upstream", conclusion: "failure" }] }, now);
  assert.equal(result.status, "healthy"); assert.equal(result.githubChangeAlert, true);
});
test("new releases, changed files, and unpublished installers are flagged", () => {
  const result = assessSnapshot(baseline, { ...snapshot, cliRelease: "clay-cli-v1.11.0", files: {}, installerMatches: false }, now);
  assert.equal(result.status, "review_required"); assert.equal(result.findings.length, 3);
});
test("failed, missing, or stale platform tests require review", () => {
  for (const change of [{ jobs: [] }, { run: { ...snapshot.run, created_at: "2026-10-12T09:00:00Z" } }, { run: undefined }]) {
    assert.equal(assessSnapshot(baseline, { ...snapshot, ...change }, now).status, "review_required");
  }
});
test("a queued run without completed results is pending rather than a failure", () => {
  assert.equal(assessSnapshot(baseline, { ...snapshot, run: undefined, pendingRun: true, pendingCreatedAt: new Date(now).toISOString() }, now).status, "pending");
});

test("stuck queue, future timestamps and failed monitor tests require review", () => {
  for (const change of [
    {run: undefined, pendingRun: true, pendingCreatedAt: '2026-10-01T00:00:00Z'},
    {run: {...snapshot.run, created_at: '2026-11-01T00:00:00Z'}},
    {jobs: [...snapshot.jobs, {name: 'maintenance-tools', conclusion: 'failure'}]}
  ]) assert.equal(assessSnapshot(baseline, {...snapshot,...change},now).status,'review_required');
});

test("old commit evidence waits for fresh tests, then escalates after 48 hours", () => {
  const changed={...snapshot,bridgeCommit:'latest',bridgeCommittedAt:new Date(now).toISOString()};
  assert.equal(assessSnapshot(baseline,changed,now).status,'pending');
  assert.equal(assessSnapshot(baseline,changed,now+49*3600000).status,'review_required');
});
