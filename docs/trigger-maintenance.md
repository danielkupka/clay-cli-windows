# Daily monitoring in Trigger.dev

The public monitor is scheduled daily at **09:00 Europe/Berlin**, including while your computer is off. Trigger.dev currently applies a one-hour scheduling window, so execution is between 09:00 and 10:00. GitHub continues running Windows and Linux tests. Trigger.dev watches their results, Clay releases, setup scripts, CLI minimum versions, and the published installer.

## Setup

1. Run `npm ci`, then `npm run trigger:login` and complete browser sign-in.
2. Put your project reference in the ignored `.env` file: `TRIGGER_PROJECT_REF=proj_your_project`.
3. Run `npm run check`, `npm test`, and `npm run monitor:check`.
4. Run `npm run trigger:deploy`. The Production task `clay-windows-public-monitor` registers its schedule.
5. In **Production > Alerts**, create a failed-run email alert. Run a manual test with External ID `alert-delivery-test` to deliberately fail with a clearly labelled test message. Confirm the email arrives. Clear External ID and run a normal check before retiring another monitor.

No GitHub token, Trigger secret key, or OpenAI key is needed. Deployment uses the CLI browser sign-in. The task reads public GitHub data; it cannot repair code, push changes, or start workflows.

## Results and limitations

- Healthy means reviewed metadata matches, the published installer matches main, and recent scheduled platform tests passed for current main.
- Pending means a recent run is queued, or main awaits scheduled tests. Missing evidence becomes a finding after 48 hours.
- Review required means upstream changes, installer differences, missing/stale tests, or failed checks. Changes alone do not prove incompatibility.
- Network failures retry once. Access/rate-limit failures do not retry immediately.
- The reviewed baseline is bundled at deployment. Review changes, update the baseline, and redeploy to acknowledge them. Unresolved findings can alert again on later days; identical error text does not guarantee notification deduplication.

Cloud monitoring cannot verify your personal Clay sign-in, update an offline laptop, or prove a fresh Windows installation works. GitHub tests use fixtures; important installer changes still need manual installation checks.

Pause monitoring on Trigger.dev's Schedules page. Removing the Codex reminder does not disable GitHub's separate daily test schedule.
