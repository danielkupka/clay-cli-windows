# Automatic Clay release maintenance

Routine stable CLI updates are checked automatically. No OpenAI key, personal GitHub token, or Trigger deployment secret is required.

For investigation and reviewed repairs in a published Codex Cloud environment, see [Codex Cloud maintenance](codex-cloud-maintenance.md). Cloud environment publication does not enable automatic repairs or replace the watchdog.

## Daily flow

1. GitHub's `automatic-release` workflow runs at 06:17 UTC (07:17 Berlin in winter, 08:17 in summer).
2. It compares official Clay releases and installation metadata with the accepted baseline.
3. Windows PowerShell/Git Bash fixture tests and Linux forwarding tests run. A separate Linux job downloads the actual official x64 CLI, verifies its GitHub SHA-256 digest, and checks version, help, and forwarding/error exit behavior without Clay credentials.
4. Only a newer release within the same major version, with unchanged monitored metadata and installer, can be accepted. Every required test must pass. A separate privileged job changes only `cliRelease` in the baseline. Source code is never automatically repaired.
5. Failed tests, major upgrades, and metadata changes create one GitHub issue assigned to `danielkupka`. The same open issue is reused without daily comments. Scheduled release tests pause for that exact release/metadata/main revision while its issue is open. A manual workflow run retries; changed metadata or main also resumes testing. Later successful checks close automation-owned review issues. GitHub notification delivery follows your account settings; the issue stays visible without email.
6. Trigger.dev reads the accepted baseline directly from GitHub each run, so version acceptance needs no redeployment. It checks at 09:00 Europe/Berlin within a one-hour scheduling window.

Trigger reports `review_tracked` when a finding already has a matching automation-owned issue, avoiding repeat failure emails. Missing or stale automation evidence (48 hours), network errors, and untracked findings still trigger alerts and can repeat until fixed. GitHub's separate daily platform tests can also notify on persistent failures according to account settings. Monitor code changes still require deployment.

## Limits and safeguards

- Tests provide bounded compatibility evidence, not proof that every Clay command works.
- Windows first-run/WSL behavior uses fixtures. The real binary test runs on Linux x64, not a fresh Windows WSL installation. Personal sign-in, enrichment, ARM64, and new feature behavior are not tested.
- Your laptop's installed CLI is unchanged. Update it separately with `clay update`.
- Only stable releases qualify. Missing or changed asset digests block acceptance.
- Publishing rechecks release metadata, digest, and main revision; concurrent changes abort the run. The baseline file uses optimistic locking.
- Test jobs do not receive publishing credentials. Only the recording job has contents/issue write access using GitHub's short-lived workflow token.
- The existing `test` workflow still runs at 07:17 UTC. Its upstream step records findings without failing just because a release changed; automatic maintenance handles review issues.

## Operations

Enable GitHub Actions and issues. Run **Actions → automatic-release → Run workflow** on `main` to verify. Scheduling requires the workflow on the default branch. Forks must adjust the repository and assignee constants before activation.

For Trigger.dev, run `npm ci`, `npm run trigger:login`, set `TRIGGER_PROJECT_REF` in ignored `.env`, then `npm run trigger:deploy`. Keep the failed-run email alert for infrastructure problems. The production task is `clay-windows-public-monitor`.

Validate changes with `npm test`, `npm run check`, and CI. Disable the GitHub `automatic-release` workflow to stop automatic baseline writes. Pause the Trigger schedule separately to stop monitoring. No AI repairs run.
