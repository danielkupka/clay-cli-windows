import { schedules, logger, wait } from "@trigger.dev/sdk";
import { githubRequest, findRun } from "../scripts/maintenance-core.mjs";

export const clayMaintenance = schedules.task({
  id: "clay-windows-daily-maintenance",
  cron: { pattern: "0 9 * * *", timezone: "Europe/Berlin", environments: ["PRODUCTION"] },
  queue: { concurrencyLimit: 1 },
  run: async (payload, { ctx }) => {
    const token = process.env.BRIDGE_GITHUB_TOKEN;
    if (!token) throw new Error("Set the BRIDGE_GITHUB_TOKEN secret in Trigger.dev Production.");
    const correlation = `trigger-${ctx.run.id}`;
    const path = "repos/danielkupka/clay-cli-windows/actions/workflows/maintenance.yml";
    // Reuse the same GitHub run after a Trigger.dev retry/replay.
    let run = await findRun(token, path, correlation);
    if (!run) {
      await githubRequest(token, `${path}/dispatches`, { method: "POST", body: { ref: "main", inputs: { correlation } } });
    }
    for (let attempt = 0; attempt < 120; attempt++) {
      await wait.for({ seconds: 30 });
      run = await findRun(token, path, correlation);
      if (!run || run.status !== "completed") continue;
      logger.info("Clay maintenance finished", { url: run.html_url, conclusion: run.conclusion, scheduledAt: payload.timestamp });
      if (run.conclusion !== "success") {
        // Configure Trigger.dev task-failure alerts to receive this link by email.
        throw new Error(`Clay compatibility needs attention. Open the linked GitHub run for findings, repair PRs, or setup errors: ${run.html_url}`);
      }
      return { status: "checked", url: run.html_url };
    }
    throw new Error("GitHub maintenance has not completed within one hour. Check GitHub Actions before replaying this task.");
  }
});
