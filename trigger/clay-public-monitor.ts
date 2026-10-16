import { schedules, logger, AbortTaskRunError } from "@trigger.dev/sdk";
import baseline from "../scripts/upstream-baseline.json" with { type: "json" };
import { assessSnapshot, collectPublicSnapshot } from "../scripts/public-monitor.mjs";

export const clayPublicMonitor = schedules.task({
  id: "clay-windows-public-monitor",
  cron: { pattern: "0 9 * * *", timezone: "Europe/Berlin", environments: ["PRODUCTION"] },
  queue: { concurrencyLimit: 1 },
  run: async (payload) => {
    // Explicit manual test only; the daily schedule does not set an external ID.
    if (payload.externalId === "alert-delivery-test") {
      throw new AbortTaskRunError("TEST ONLY: Clay monitor email delivery check. No compatibility problem was detected by this test.");
    }
    let snapshot;
    try {
      snapshot = await collectPublicSnapshot();
    } catch (error) {
      if (error instanceof Error && "status" in error && [403, 429].includes(Number(error.status))) {
        throw new AbortTaskRunError("GitHub refused the public check (access or rate limit). No immediate retry; check again after the limit resets.");
      }
      throw error;
    }
    const result = assessSnapshot(baseline, snapshot);
    logger.info("Clay public compatibility monitor", result);
    if (result.status === "review_required") {
      // Review findings are deterministic; retrying cannot resolve them.
      throw new AbortTaskRunError("Clay Windows compatibility has findings requiring manual review. See the run log for details and links.");
    }
    return result;
  }
});
