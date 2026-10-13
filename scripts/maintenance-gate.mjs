import { readFileSync, appendFileSync } from "node:fs";
import { fingerprint, githubRequest } from "./maintenance-core.mjs";

const report = JSON.parse(readFileSync(".maintenance/report.json", "utf8"));
const testsResult = process.env.TESTS_RESULT;
if (!["success", "failure", "cancelled", "skipped"].includes(testsResult)) throw new Error("Missing test conclusion.");
const key = fingerprint(report, testsResult);
const branch = `maintenance/review-${key.slice(0, 32)}`;
let pending = report.findings.length > 0 || testsResult !== "success";
if (pending) {
  try {
    await githubRequest(process.env.GH_TOKEN, `repos/danielkupka/clay-cli-windows/git/ref/heads/${branch}`);
    console.log(`Already investigated. Review branch: ${branch}`);
    pending = false;
  } catch (error) { if (error.status !== 404) throw error; }
}
appendFileSync(process.env.GITHUB_OUTPUT, `pending=${pending}\nbranch=${branch}\nfingerprint=${key}\nbase=${report.bridgeCommit}\n`);
appendFileSync(process.env.GITHUB_STEP_SUMMARY, `\n### Maintenance decision\nNew investigation: ${pending}\nExisting tests: ${testsResult}\nFindings: ${report.findings.length}\nReview branch: ${branch}\n`);
