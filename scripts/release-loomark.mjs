#!/usr/bin/env node
import { spawnSync } from "node:child_process";
import { mkdtempSync, readFileSync, readdirSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { checkProduction } from "./check-loomark-production.mjs";

const app = fileURLToPath(new URL("../apps/loomark/", import.meta.url));
const config = join(app, "wrangler.jsonc");
const uuid = /^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$/i;

function run(command, args, { capture = false, env = {} } = {}) {
  const result = spawnSync(command, args, {
    cwd: app,
    env: {
      ...process.env,
      CI: "true",
      LOOMARK_LOCAL_BUILD: "0",
      CLOUDFLARE_LOAD_DEV_VARS_FROM_DOT_ENV: "false",
      ...env,
    },
    encoding: "utf8",
    stdio: ["ignore", capture ? "pipe" : "inherit", "inherit"],
  });
  if (result.error || result.status !== 0) {
    throw new Error(`${command} ${args.slice(0, 3).join(" ")} failed${result.signal ? ` (${result.signal})` : ""}`);
  }
  return result.stdout;
}

function wrangler(args, options) {
  // Select production explicitly even when the caller has CLOUDFLARE_ENV set.
  // The pinned npm dependency supplies this executable.
  return run("wrangler", [...args, "--config", config, "--env", "production"], options);
}

let temporary;
let published = false;
try {
  if (process.argv.length !== 2) {
    throw new Error("This production-only command takes no arguments");
  }
  if (process.env.WORKERS_CI === "1") {
    if (process.env.WORKERS_CI_BRANCH !== "main") {
      throw new Error("Only the main Workers Builds branch may release production");
    }
  } else if (run("git", ["status", "--porcelain", "--untracked-files=normal"], { capture: true }).trim()) {
    throw new Error("Release from a clean checkout, including submodules; do not use the development checkout");
  }

  temporary = mkdtempSync(join(tmpdir(), "loomark-release-"));
  const output = join(temporary, "upload.ndjson");
  console.log("Building and uploading an inactive Worker version");
  wrangler(["versions", "upload"], { env: { WRANGLER_OUTPUT_FILE_PATH: output } });
  const uploads = readFileSync(output, "utf8").trim().split("\n")
    .map((line) => JSON.parse(line)).filter((entry) => entry.type === "version-upload");
  if (uploads.length !== 1 || uploads[0].worker_name !== "loomark" ||
      !uuid.test(uploads[0].version_id)) {
    throw new Error("Upload did not identify exactly one Loomark version; refusing to migrate or deploy");
  }
  const version = uploads[0].version_id;

  console.log("Applying migrations to the configured production AUTH_DB");
  wrangler(["d1", "migrations", "apply", "AUTH_DB", "--remote"]);
  const applied = JSON.parse(wrangler([
    "d1", "execute", "AUTH_DB", "--remote", "--json",
    "--command", "SELECT name FROM d1_migrations",
  ], { capture: true }));
  if (applied.length !== 1 || applied[0].success !== true ||
      !Array.isArray(applied[0].results)) {
    throw new Error("Cannot confirm the production migration history");
  }
  const names = new Set(applied[0].results.map((row) => row.name));
  const missing = readdirSync(join(app, "server/migrations"))
    .filter((name) => name.endsWith(".sql") && !names.has(name));
  if (missing.length) {
    throw new Error(`Production migrations are still missing: ${missing.join(", ")}`);
  }

  console.log(`Deploying ${version} to 100% of production traffic`);
  // A deploy command can fail after the remote side accepted it. Do not attempt
  // an automatic rollback: D1 changes are not rolled back with Worker code.
  published = true;
  wrangler(["versions", "deploy", `${version}@100%`, "--yes"]);
  await checkProduction();
  const deployments = JSON.parse(wrangler(["deployments", "list", "--json"], { capture: true }));
  const current = deployments.sort((a, b) => Date.parse(b.created_on) - Date.parse(a.created_on))[0];
  if (current?.versions?.length !== 1 ||
      current.versions[0].version_id !== version || current.versions[0].percentage !== 100) {
    throw new Error("Production is not serving the uploaded version at 100%; check for another deployment");
  }
  console.log(`PASS Loomark production release: ${version}`);
} catch (error) {
  console.error(`Loomark release failed: ${error.message}`);
  if (published) {
    console.error("Production may already have changed. Inspect the deployment and schema before recovery; no automatic rollback was attempted.");
  }
  process.exitCode = 1;
} finally {
  if (temporary) rmSync(temporary, { recursive: true, force: true });
}
