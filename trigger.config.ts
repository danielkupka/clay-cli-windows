import { defineConfig } from "@trigger.dev/sdk";

// Set via .env when deploying; a missing project stops deployment.
const project = process.env.TRIGGER_PROJECT_REF;
if (!project || !/^proj_[a-zA-Z0-9]+$/.test(project)) {
  throw new Error("Fill TRIGGER_PROJECT_REF in .env with your Trigger.dev project reference.");
}
export default defineConfig({ project, runtime: "node", dirs: ["./trigger"], maxDuration: 120,
  retries: { enabledInDev: false, default: { maxAttempts: 2, minTimeoutInMs: 5000, maxTimeoutInMs: 15000, factor: 2, randomize: true } }
});
