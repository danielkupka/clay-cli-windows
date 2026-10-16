import { spawnSync } from "node:child_process";
import { configure, envvars } from "@trigger.dev/sdk";

for (const name of ["TRIGGER_PROJECT_REF", "TRIGGER_SECRET_KEY", "BRIDGE_GITHUB_TOKEN"]) {
  if (!process.env[name]) throw new Error(`Fill ${name} in .env first.`);
}
const githubSecrets = ["BRIDGE_GITHUB_TOKEN"];
if (process.env.OPENAI_API_KEY) githubSecrets.push("OPENAI_API_KEY");
for (const name of githubSecrets) {
  const result = spawnSync("gh", ["secret", "set", name, "--repo", "danielkupka/clay-cli-windows"], {
    input: process.env[name], stdio: ["pipe", "pipe", "pipe"], encoding: "utf8"
  });
  if (result.error || result.status !== 0) throw new Error(`Could not save GitHub secret ${name}; check gh authentication and repository permissions.`);
  console.log(`Saved GitHub secret ${name}.`);
}
configure({ secretKey: process.env.TRIGGER_SECRET_KEY });
await envvars.upload(process.env.TRIGGER_PROJECT_REF, "prod", {
  variables: { BRIDGE_GITHUB_TOKEN: process.env.BRIDGE_GITHUB_TOKEN }, override: true, isSecret: true
});
console.log("Saved the coordinator token in Trigger.dev Production. OpenAI key stays in GitHub.");
if (!process.env.OPENAI_API_KEY) console.log("OpenAI key omitted: paid investigations remain disabled.");
