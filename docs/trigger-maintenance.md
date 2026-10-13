# Connect the Clay maintenance pilot to Trigger.dev

The pilot checks the bridge daily at 09:00 Europe/Berlin. Trigger.dev coordinates a GitHub run. Windows and Linux tests run on GitHub. Codex runs only when new upstream findings or failing tests need investigation. It opens a draft pull request with the assessment and any proposed repair; the proposed branch is tested and you decide whether to merge it.

The existing GitHub daily schedule stays enabled as a fallback. Its checks do not invoke Codex, so it cannot duplicate paid investigations. Trigger.dev must be deployed to Production to run while your laptop is offline. It cannot update the CLI on your switched-off computer or check your personal Clay sign-in.

## One-time connection

1. Open [Trigger.dev](https://cloud.trigger.dev) and create a project named **Clay Windows maintenance**, or select an existing project. Copy its project reference from **Settings** (starts with `proj_`).
2. In this repository's PowerShell terminal run `npm run trigger:login`. Complete the browser sign-in yourself. This connects the deployment CLI to your Trigger.dev account.
3. Open the local `.env` file and fill in these four values:

   | Field | Where to get it |
   | --- | --- |
   | `TRIGGER_PROJECT_REF` | Trigger.dev project Settings |
   | `TRIGGER_SECRET_KEY` | The project's **Production** API key |
   | `BRIDGE_GITHUB_TOKEN` | A GitHub fine-grained token for **only** `danielkupka/clay-cli-windows`, with Actions, Contents and Pull requests read/write permissions |
   | `OPENAI_API_KEY` | An OpenAI project API key with API billing enabled |

   `.env` is ignored by Git. Keep it on your machine; never paste it into chat or a pull request. Use a dedicated OpenAI project and set its billing alerts. The investigation job has a 15-minute timeout; that limits runtime, not dollars, and an OpenAI project budget is not necessarily a hard spending cap.
4. Run `npm run maintenance:secrets`. It transfers the GitHub token and OpenAI key to GitHub repository secrets. It transfers only the GitHub coordinator token to Trigger.dev Production. It does not print the keys. The deployment CLI itself keeps using its browser sign-in.
5. Run `npm run trigger:deploy`. This deploys the Production task and registers its daily schedule. The script loads `.env`; it does not commit that file.
6. In Trigger.dev, open the task **clay-windows-daily-maintenance**, run a manual test in **Production**, and verify the linked GitHub run. Configure a **task-failure email alert** for this task in the project's Alerts settings. Findings with a new draft PR deliberately mark the GitHub run as requiring attention, triggering the configured alert. Open its summary for the PR link and test results.

No OpenAI call is made by ordinary checks or by this setup script. A manual Production test can incur API usage if new findings exist. The latest baseline currently has no findings; recheck before testing.

## How duplicates and failures are handled

- Trigger retries reuse a correlated GitHub run. Maintenance runs are serialized on GitHub; the Trigger task also has concurrency one.
- Each distinct finding gets a fingerprint and a deterministic review branch. A retained branch prevents the same finding from invoking Codex again, even if its PR was closed. Keep these branches to preserve that record.
- Codex cannot publish changes directly. A separate job validates the patch's allowed paths, uses a GitHub token to open a draft PR, and runs Windows/Linux checks on it. No automatic merge or release happens.
- The review includes the agent's assessment and observed metadata, including when no repair is warranted. Upstream changes alone do not prove incompatibility.
- Failed investigation or publishing attempts that did not leave a review branch may be retried on a later day. The coordinator retries at most twice; each investigation has a 15-minute timeout.
- If a pushed review branch exists but PR creation failed, create its PR manually from GitHub. The run summary includes the branch. If main changed during investigation, rerun against current main.
- Without the required secrets, new findings produce an explicit setup error instead of an API call. Ordinary tests remain available.

## After approving a review

Review the proposed patch and Windows/Linux results, then merge if appropriate. An installer change still needs a new release and updated pinned README links. The automated agent does not publish releases. If the reviewed upstream change is harmless, the review may contain only an assessment and a reviewed baseline update.

To pause the pilot, disable the schedule on the task's Schedules tab in Trigger.dev. The GitHub fallback remains active. Your local Codex schedule independently maintains the CLI installed on your computer when it is available.
