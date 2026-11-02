import { githubRequest } from "./maintenance-core.mjs";
import { createHash } from "node:crypto";

export function reviewKey(snapshot) {
  return createHash('sha256').update(JSON.stringify({release:snapshot.cliRelease,files:Object.entries(snapshot.files).sort(),installer:snapshot.installerMatches,bridge:snapshot.bridgeCommit})).digest('hex');
}

const upstream = "clay-run/agent-plugins";
const bridge = "danielkupka/clay-cli-windows";
const monitored = /(^GETTING_STARTED\.md$|^README\.md$|^clay\/(scripts\/|skills\/(setup|update|cli)\/|cli-min-version$|\.claude-plugin\/plugin\.json$))/;
const normalize = text => text.replace(/\r\n/g, "\n");
async function rawText(url) {
  const response = await fetch(url, { signal: AbortSignal.timeout(30000) });
  if (!response.ok) throw new Error(`Public file request failed (${response.status}).`);
  return response.text();
}

export function assessSnapshot(baseline, current, now = Date.now()) {
  const findings = [];
  let pending = Boolean(current.pendingRun);
  if (current.pendingRun) {
    const age = now - Date.parse(current.pendingCreatedAt);
    if (!Number.isFinite(age) || age < -300000 || age > 48 * 60 * 60 * 1000) findings.push("The queued GitHub check is missing a valid timestamp or has waited over 48 hours.");
  }
  for (const path of [...new Set([...Object.keys(baseline.files), ...Object.keys(current.files)])].sort()) {
    if (baseline.files[path] !== current.files[path]) findings.push(`Upstream file changed: ${path}`);
  }
  if (baseline.cliRelease !== current.cliRelease) findings.push(`New stable CLI: ${baseline.cliRelease} -> ${current.cliRelease}`);
  if (!current.installerMatches) findings.push("The README's published installer differs from main.");
  if (!current.run) {
    if (!current.pendingRun) findings.push("No scheduled GitHub test run was found.");
  } else {
    const age = now - Date.parse(current.run.created_at);
    if (!Number.isFinite(age) || age < -300000 || age > 48 * 60 * 60 * 1000) findings.push("The latest completed GitHub check is over 48 hours old or has an invalid timestamp.");
    if (current.bridgeCommit && current.run.head_sha !== current.bridgeCommit) {
      pending = true;
      const headAge = now - Date.parse(current.bridgeCommittedAt);
      if (!Number.isFinite(headAge) || headAge > 48 * 60 * 60 * 1000) findings.push("Current bridge main has no recent scheduled test evidence.");
    }
    // The upstream job deliberately fails on metadata changes. Assess real platform tests separately.
    for (const name of ["powershell", "linux-forwarder"]) {
      const job = current.jobs.find(job => job.name === name);
      if (!job || job.conclusion !== "success") findings.push(`GitHub platform test needs review: ${name}`);
    }
  }
  for (const job of current.jobs.filter(job => job.name !== "upstream")) {
    if (job.conclusion !== "success" && !findings.includes(`GitHub platform test needs review: ${job.name}`)) findings.push(`GitHub check needs review: ${job.name}`);
  }
  return {
    status: findings.length ? "review_required" : pending ? "pending" : "healthy",
    findings,
    platformTestsUrl: current.run?.html_url,
    githubChangeAlert: current.jobs.some(job => job.name === "upstream" && job.conclusion === "failure"),
    upstreamCompareUrl: `https://github.com/${upstream}/compare/${baseline.reviewedCommit}...${current.upstreamCommit}`,
    releaseUrl: current.releaseUrl,
    installerUrl: current.installerUrl
  };
}

export async function collectPublicSnapshot() {
  const [head, bridgeHead, releases, runs] = await Promise.all([
    githubRequest(undefined, `repos/${upstream}/commits/main`),
    githubRequest(undefined, `repos/${bridge}/commits/main`),
    githubRequest(undefined, `repos/${upstream}/releases?per_page=100`),
    githubRequest(undefined, `repos/${bridge}/actions/workflows/test.yml/runs?event=schedule&per_page=5`)
  ]);
  const tree = await githubRequest(undefined, `repos/${upstream}/git/trees/${head.sha}?recursive=1`);
  if (tree.truncated) throw new Error("Upstream tree was truncated; a complete comparison is unavailable.");
  const files = Object.fromEntries(tree.tree.filter(item => item.type === "blob" && monitored.test(item.path)).map(item => [item.path, item.sha]));
  const stable = releases.filter(item => !item.draft && !item.prerelease && /^clay-cli-v\d+\.\d+\.\d+$/.test(item.tag_name));
  stable.sort((a, b) => {
    const aa = a.tag_name.replace("clay-cli-v", "").split(".").map(Number);
    const bb = b.tag_name.replace("clay-cli-v", "").split(".").map(Number);
    return bb[0] - aa[0] || bb[1] - aa[1] || bb[2] - aa[2];
  });
  if (!stable.length) throw new Error("No stable Clay CLI release could be verified.");
  const base = `https://raw.githubusercontent.com/${bridge}/${bridgeHead.sha}`;
  const [readme, installer, baselineText] = await Promise.all([rawText(`${base}/README.md`), rawText(`${base}/install.ps1`), rawText(`${base}/scripts/upstream-baseline.json`)]);
  const acceptedBaseline = JSON.parse(baselineText);
  if (!/^clay-cli-v\d+\.\d+\.\d+$/.test(acceptedBaseline.cliRelease) || !acceptedBaseline.files || !/^[a-f0-9]{40}$/.test(acceptedBaseline.reviewedCommit)) throw new Error('Invalid published baseline');
  const links = [...new Set(readme.match(/https:\/\/raw\.githubusercontent\.com\/danielkupka\/clay-cli-windows\/v\d+\.\d+\.\d+\/install\.ps1/g) ?? [])];
  if (links.length !== 1) throw new Error("README must advertise exactly one pinned installer URL.");
  const advertised = await rawText(links[0]);
  const run = runs.workflow_runs.find(item => item.status === "completed");
  const pendingRun = runs.workflow_runs[0]?.status !== "completed" && runs.workflow_runs.length > 0;
  const jobs = run ? (await githubRequest(undefined, `repos/${bridge}/actions/runs/${run.id}/jobs?per_page=100`)).jobs : [];
  return { acceptedBaseline, release: stable[0], files, upstreamCommit: head.sha, cliRelease: stable[0].tag_name, releaseUrl: stable[0].html_url,
    bridgeCommit: bridgeHead.sha, bridgeCommittedAt: bridgeHead.commit.committer.date,
    pendingCreatedAt: pendingRun ? runs.workflow_runs[0].created_at : undefined,
    installerUrl: links[0], installerMatches: normalize(installer) === normalize(advertised), run, pendingRun, jobs };
}
