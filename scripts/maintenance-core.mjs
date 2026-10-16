import { createHash } from "node:crypto";

export function fingerprint(report, testsResult) {
  return createHash("sha256").update(JSON.stringify({
    files: Object.entries(report.changedFiles).sort(([a], [b]) => a.localeCompare(b)),
    release: report.releaseChanged ? report.cliRelease : null,
    installer: report.installerChanged ? report.installerHash : null,
    tests: testsResult === "success" ? "success" : `${testsResult}:${report.bridgeCommit}`
  })).digest("hex");
}
export async function githubRequest(token, path, options = {}) {
  const response = await fetch(`https://api.github.com/${path}`, {
    method: options.method ?? "GET",
    headers: { Authorization: `Bearer ${token}`, Accept: "application/vnd.github+json", "X-GitHub-Api-Version": "2022-11-28", "Content-Type": "application/json" },
    body: options.body ? JSON.stringify(options.body) : undefined,
    signal: AbortSignal.timeout(30000)
  });
  if (!response.ok) {
    const error = new Error(`GitHub request failed (${response.status}) for ${path}`);
    error.status = response.status;
    throw error;
  }
  return response.status === 204 ? null : response.json();
}
export async function findRun(token, workflowPath, correlation) {
  const result = await githubRequest(token, `${workflowPath}/runs?event=workflow_dispatch&per_page=100`);
  return result.workflow_runs.find(run => run.display_title === `Clay maintenance ${correlation}`);
}
