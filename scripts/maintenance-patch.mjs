import { execFileSync } from "node:child_process";
import { readFileSync, writeFileSync, existsSync, lstatSync, mkdirSync } from "node:fs";

const git = (...args) => execFileSync("git", args, { encoding: "utf8" }).trim();
const allowed = /^(install\.ps1|README\.md|CHANGELOG\.md|scripts\/(upstream-baseline\.json|Check-Upstream\.ps1)|tests\/[a-zA-Z0-9_.-]+|docs\/compatibility\/[a-f0-9]{64}\.md)$/;
const mode = process.argv[2];
if (!/^[a-f0-9]{64}$/.test(process.env.FINDING_KEY ?? "")) throw new Error("Invalid finding fingerprint.");
if (mode === "capture") {
  const report = readFileSync(".maintenance/report.json", "utf8");
  const answer = readFileSync(".maintenance/codex-report.md", "utf8");
  const path = `docs/compatibility/${process.env.FINDING_KEY}.md`;
  mkdirSync("docs/compatibility", { recursive: true });
  writeFileSync(path, `# Clay compatibility review\n\n${answer}\n\n## Observed findings\n\n\`\`\`json\n${report}\n\`\`\`\n`);
  const paths = execFileSync("git", ["ls-files", "--modified", "--others", "--exclude-standard", "-z"], { encoding: "utf8" }).split("\0").filter(Boolean);
  for (const path of paths) {
    if (!allowed.test(path) || (existsSync(path) && !lstatSync(path).isFile())) throw new Error(`Proposed change outside maintenance scope: ${path}`);
  }
  if (paths.length) git("add", "--", ...paths);
  writeFileSync(".maintenance/repair.patch", execFileSync("git", ["diff", "--cached", "--binary", "HEAD"]));
} else if (mode === "apply") {
  git("apply", "--index", ".maintenance/repair.patch");
  const paths = execFileSync("git", ["diff", "--cached", "--name-only", "-z"], { encoding: "utf8" }).split("\0").filter(Boolean);
  for (const path of paths) {
    if (!allowed.test(path) || (existsSync(path) && !lstatSync(path).isFile())) throw new Error(`Patch outside maintenance scope: ${path}`);
  }
  if (!paths.length) throw new Error("Empty review patch.");
} else { throw new Error("Expected capture or apply mode."); }
