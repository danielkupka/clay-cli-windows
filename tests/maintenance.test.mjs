import test from "node:test";
import assert from "node:assert/strict";
import { fingerprint, findRun } from "../scripts/maintenance-core.mjs";
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { execFileSync, spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const report = { changedFiles: { b: "2", a: "1" }, releaseChanged: false, cliRelease: "clay-cli-v1.9.1", installerChanged: false, installerHash: "x", bridgeCommit: "abc" };
test("same finding deduplicates across unrelated commits and property ordering", () => {
  assert.equal(fingerprint(report, "success"), fingerprint({ ...report, bridgeCommit: "def", changedFiles: { a: "1", b: "2" } }, "success"));
});
test("new file changes, deletions, releases, and installer differences are distinct", () => {
  const key = fingerprint(report, "success");
  for (const change of [{ changedFiles: { a: null, b: "2" } }, { releaseChanged: true }, { installerChanged: true }]) {
    assert.notEqual(key, fingerprint({ ...report, ...change }, "success"));
  }
});
test("test failures stay distinct from passing checks and can be reconsidered after code changes", () => {
  assert.notEqual(fingerprint(report, "success"), fingerprint(report, "failure"));
  assert.notEqual(fingerprint(report, "failure"), fingerprint({ ...report, bridgeCommit: "def" }, "failure"));
});
test("workflow retries find the existing correlated run", async () => {
  const previous = globalThis.fetch;
  globalThis.fetch = async () => new Response(JSON.stringify({ workflow_runs: [{ display_title: "Clay maintenance trigger-123", id: 42 }] }));
  try { assert.equal((await findRun("fixture", "fixture/workflow", "trigger-123")).id, 42); }
  finally { globalThis.fetch = previous; }
});

function withFixture(run) {
  const root = mkdtempSync(join(tmpdir(), "clay-maintenance-test-"));
  const git = (...args) => execFileSync("git", args, { cwd: root, stdio: "pipe" });
  try {
    mkdirSync(join(root, ".github/workflows"), { recursive: true });
    writeFileSync(join(root, ".github/workflows/test.yml"), "original workflow\n");
    writeFileSync(join(root, "install.ps1"), "original installer\n");
    writeFileSync(join(root, ".gitignore"), ".maintenance/\n");
    git("init"); git("config", "user.email", "fixture@example.invalid"); git("config", "user.name", "Fixture");
    git("add", "."); git("commit", "-m", "fixture");
    mkdirSync(join(root, ".maintenance"));
    writeFileSync(join(root, ".maintenance/report.json"), "{}");
    writeFileSync(join(root, ".maintenance/codex-report.md"), "Fixture review.");
    const helper = mode => spawnSync(process.execPath, [fileURLToPath(new URL("../scripts/maintenance-patch.mjs", import.meta.url)), mode], {
      cwd: root, env: { ...process.env, FINDING_KEY: "a".repeat(64) }, encoding: "utf8"
    });
    run({ root, git, helper });
  } finally { rmSync(root, { recursive: true, force: true }); }
}
test("repair packaging includes a review and an allowed installer change", () => withFixture(({ root, helper }) => {
  writeFileSync(join(root, "install.ps1"), "fixed installer\n");
  const result = helper("capture");
  assert.equal(result.status, 0, result.stderr);
  const patch = readFileSync(join(root, ".maintenance/repair.patch"), "utf8");
  assert.match(patch, /fixed installer/); assert.match(patch, /docs\/compatibility/);
}));
test("repair packaging rejects workflow changes", () => withFixture(({ root, helper }) => {
  writeFileSync(join(root, ".github/workflows/test.yml"), "unsafe workflow\n");
  const result = helper("capture");
  assert.notEqual(result.status, 0); assert.match(result.stderr, /outside maintenance scope/);
}));
test("publisher independently rejects a patch modifying workflows", () => withFixture(({ root, git, helper }) => {
  writeFileSync(join(root, ".github/workflows/test.yml"), "unsafe workflow\n");
  writeFileSync(join(root, ".maintenance/repair.patch"), git("diff", "--binary"));
  writeFileSync(join(root, ".github/workflows/test.yml"), "original workflow\n");
  git("add", ".github/workflows/test.yml");
  const result = helper("apply");
  assert.notEqual(result.status, 0); assert.match(result.stderr, /outside maintenance scope/);
}));
