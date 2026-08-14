#!/usr/bin/env node
// Verify the parsed release workflow passes the changelog generator's exact argv.

import { readFileSync } from "node:fs";
import { createRequire } from "node:module";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const require = createRequire(import.meta.url);
const yaml = require("js-yaml");
const repoRoot = join(dirname(fileURLToPath(import.meta.url)), "..");
const workflowPath = join(repoRoot, ".github/workflows/release.yml");
const workflow = yaml.load(readFileSync(workflowPath, "utf8"));

function fail(message) {
  console.error(`FAIL release workflow wiring: ${message}`);
  process.exit(1);
}

function findStep(job, name) {
  const step = job?.steps?.find((candidate) => candidate.name === name);
  if (!step) {
    fail(`missing ${name} step`);
  }
  return step;
}

const build = workflow.jobs?.["build-release"];
if (!build) {
  fail("missing build-release job");
}

const checkout = findStep(build, "Checkout code");
if (checkout.with?.["fetch-depth"] !== 0) {
  fail(`Checkout code must use fetch-depth 0, got ${JSON.stringify(checkout.with?.["fetch-depth"])}`);
}

const changelog = findStep(build, "Generate changelog");
const expectedRun =
  'nu scripts/generate-release-changelog.nu "$VERSION" "$SOURCE_SHA" "$REPOSITORY" "$OUTPUT_PATH"';
if (changelog.run !== expectedRun) {
  fail(`Generate changelog run mismatch: ${JSON.stringify(changelog.run)}`);
}

const expectedEnv = {
  VERSION: "${{ steps.resolve-version.outputs.version }}",
  SOURCE_SHA: "${{ github.sha }}",
  REPOSITORY: "${{ github.repository }}",
  OUTPUT_PATH: "CHANGELOG.txt",
};
for (const [name, expected] of Object.entries(expectedEnv)) {
  if (changelog.env?.[name] !== expected) {
    fail(`Generate changelog env ${name} mismatch: ${JSON.stringify(changelog.env?.[name])}`);
  }
}

const release = findStep(build, "Create GitHub Release");
if (release.with?.body_path !== "CHANGELOG.txt") {
  fail(`Create GitHub Release must use body_path CHANGELOG.txt, got ${JSON.stringify(release.with?.body_path)}`);
}
if (Object.hasOwn(release.with ?? {}, "generate_release_notes")) {
  fail("Create GitHub Release must not enable generated release notes");
}

console.log("PASS release workflow parsed wiring");
