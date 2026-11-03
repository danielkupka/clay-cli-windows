# Codex Cloud maintenance

Use the published `clay-cli-windows` environment for investigation and repairs. GitHub Actions remains responsible for daily release checks and Windows acceptance tests. Publishing a Cloud environment does not schedule tasks or connect failed workflows to an agent.

## Validate a new Cloud task

Start from current main, inspect repository instructions and dirty state, and run:

```sh
npm ci
npm run cloud:check
pwsh -NoProfile -File tests/Test-Installer.ps1
pwsh -NoProfile -File tests/Test-Installer.ps1 -ExportScripts .test-output/cloud -FixtureExecutable "/tmp/clay cloud/user's cli"
bash tests/Test-Forwarder.sh .test-output/cloud "/tmp/clay cloud/user's cli"
npm run monitor:check
```

`cloud:check` runs TypeScript and unit tests only; the following commands supply installer, Linux forwarding and public-state evidence. `monitor:check` reads the accepted baseline from GitHub main, not the Cloud workspace's potentially older copy. Exit 0 means healthy, 1 means findings or a failed request, and 2 means pending CI evidence. Pending is not a full acceptance pass. Public requests require access to api.github.com and raw.githubusercontent.com. Real release smoke tests additionally require github.com and its release download hosts.

Do not copy personal `.env` files, Clay credentials, or subscription login files into this environment. Routine checks use public information. Keep GitHub publishing actions separate from validation.

## Reusable repair request

> Inspect the latest failed Clay maintenance checks and any existing maintenance issue or PR before changing files. Verify current main, the accepted baseline, upstream release notes, installer metadata, and the advertised installer version. Prepare only evidence-backed fixes on a separate branch, add regression coverage, and run the repository checks. Do not relax tests or advance the baseline merely to silence an alert. Report the exact revision, tests and skipped checks. Do not merge, deploy, publish releases, change schedules, or use Clay credentials. Leave the fix ready for review.

Linux PowerShell 7 tests do not establish Windows PowerShell 5.1, Git Bash, or WSL first-run compatibility. Require the GitHub Windows job for the exact proposed commit before merging. Installer changes also need a release and updated advertised pin before users receive them.

## Automation and cutover

The existing `automatic-release` GitHub workflow runs without the laptop and accepts only bounded, tested stable version updates. Codex Cloud repairs currently require starting a task. No automatic failed-check-to-Cloud handoff is configured by this document.

Keep Trigger.dev's watchdog until a replacement has demonstrated stale-run/failure detection and delivery of actionable findings. Removing it loses that independent watchdog even though GitHub checks continue. Do not introduce a local desktop schedule as a substitute for offline Cloud execution.

Before calling the full flow unattended, demonstrate: a failure starts a Cloud task, repeated failures do not create duplicate repairs, the task uses current source, Windows CI validates the fix, and publication still requires review. Record the schedule/event configuration and first successful run. A manual Cloud validation only proves the environment works.
