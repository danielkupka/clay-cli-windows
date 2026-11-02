import { schedules, logger, AbortTaskRunError } from "@trigger.dev/sdk";
import { assessSnapshot, collectPublicSnapshot, reviewKey } from "../scripts/public-monitor.mjs";
import { githubRequest } from "../scripts/maintenance-core.mjs";

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
    const result = assessSnapshot(snapshot.acceptedBaseline, snapshot);
    const history = await githubRequest(undefined, 'repos/danielkupka/clay-cli-windows/actions/workflows/auto-release.yml/runs?branch=main&per_page=20');
    const latest = history.workflow_runs.find((r: any) => r.status === 'completed');
    if (!latest || !Number.isFinite(Date.parse(latest.created_at)) || Date.now() - Date.parse(latest.created_at) > 48 * 3600000) {
      throw new AbortTaskRunError('Automatic release maintenance is failing or has no successful run within 48 hours. Check GitHub Actions.');
    }
    if (latest.conclusion !== 'success') {
      const details = await githubRequest(undefined, `repos/danielkupka/clay-cli-windows/actions/runs/${latest.id}/jobs?per_page=100`);
      if (!details.jobs.some((j: any) => j.name === 'record' && j.conclusion === 'success')) {
        throw new AbortTaskRunError('Automatic maintenance could not record its result. Check the GitHub workflow before suppressing alerts.');
      }
      result.status = 'review_required';
      result.findings.push('Automatic release tests need review.');
    }
    logger.info("Clay public compatibility monitor", result);
    if (result.status === "review_required") {
      // GitHub assigns one issue to the owner. Keep the finding visible without
      // generating another daily failure email for the same unresolved review.
      const marker = `<!-- clay-auto-review:${reviewKey(snapshot)} -->`;
      for (let page = 1; page <= 20; page++) {
        const issues = await githubRequest(undefined, `repos/danielkupka/clay-cli-windows/issues?state=open&per_page=100&page=${page}`);
        const tracked = issues.find((i: any) => !i.pull_request && i.user?.login === 'github-actions[bot]' && i.body?.includes(marker));
        if (tracked) return { ...result, status: 'review_tracked', issueUrl: tracked.html_url };
        if (issues.length < 100) break;
      }
      // Review findings are deterministic; retrying cannot resolve them.
      throw new AbortTaskRunError("Clay Windows compatibility has findings requiring manual review. See the run log for details and links.");
    }
    return result;
  }
});
