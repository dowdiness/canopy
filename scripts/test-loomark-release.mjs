#!/usr/bin/env node
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { copyFileSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, rmSync, writeFileSync } from "node:fs";
import { createServer } from "node:http";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import test from "node:test";
import { checkProduction } from "./check-loomark-production.mjs";

const scripts = fileURLToPath(new URL("./", import.meta.url));
const migrations = fileURLToPath(new URL("../apps/loomark/server/migrations/", import.meta.url));
const version = "11111111-1111-4111-8111-111111111111";

// Exercise the actual release CLI against an isolated control-plane simulator.
// No real Wrangler, credentials, or production HTTP requests are used here.
function releaseScenario(mode) {
  const root = mkdtempSync(join(tmpdir(), "loomark-release-test-"));
  try {
    mkdirSync(join(root, "scripts"));
    mkdirSync(join(root, "bin"));
    mkdirSync(join(root, "apps/loomark/server/migrations"), { recursive: true });
    for (const name of ["release-loomark.mjs", "check-loomark-production.mjs"]) {
      copyFileSync(join(scripts, name), join(root, "scripts", name));
    }
    const names = readdirSync(migrations).filter((name) => name.endsWith(".sql"));
    for (const name of names) writeFileSync(join(root, "apps/loomark/server/migrations", name), "");
    const statePath = join(root, "state.json");
    writeFileSync(statePath, JSON.stringify({ migrated: false, active: "old", calls: 0 }));
    writeFileSync(join(root, "bin/wrangler"), `#!/usr/bin/env node
const fs = require('node:fs');
const args = process.argv.slice(2);
const state = JSON.parse(fs.readFileSync(process.env.TEST_STATE, 'utf8'));
const mode = process.env.TEST_MODE;
const version = ${JSON.stringify(version)};
state.calls++;
const save = () => fs.writeFileSync(process.env.TEST_STATE, JSON.stringify(state));
const fail = () => { save(); process.exit(1); };
if (args[0] === 'versions' && args[1] === 'upload') {
  if (mode === 'build-failure') fail();
  fs.writeFileSync(process.env.WRANGLER_OUTPUT_FILE_PATH, JSON.stringify({
    type: 'version-upload', worker_name: mode === 'wrong-worker' ? 'another-worker' : 'loomark', version_id: version
  }) + '\\n');
} else if (args[0] === 'd1' && args[1] === 'migrations') {
  if (mode === 'migration-failure') fail();
  state.migrated = true;
} else if (args[0] === 'd1' && args[1] === 'execute') {
  console.log(JSON.stringify([{success: true, results: (mode === 'missing-migration' ? [] : ${JSON.stringify(names)}).map(name => ({name}))}]));
} else if (args[0] === 'versions' && args[1] === 'deploy') {
  if (!state.migrated) fail();
  state.active = version;
} else if (args[0] === 'deployments' && args[1] === 'list') {
  console.log(JSON.stringify([{created_on:'2026-09-24T00:00:00Z', versions:[{
    version_id: mode === 'superseded' ? 'another-version' : state.active, percentage:100
  }]}]));
} else fail();
save();
`, { mode: 0o755 });
    const preload = join(root, "http.mjs");
    writeFileSync(preload, `globalThis.fetch = async (url) => {
      if (process.env.TEST_MODE === 'unhealthy') return Response.json({error:'account_unavailable'}, {status:503});
      if (url.pathname === '/api/auth/ok') return Response.json({ok:true});
      if (url.pathname === '/api/account') return Response.json({error:'sign_in_required'}, {status:401});
      throw new Error('Unexpected request');
    };`);
    const result = spawnSync(process.execPath, ["--import", preload, join(root, "scripts/release-loomark.mjs")], {
      encoding: "utf8",
      env: {
        PATH: `${join(root, "bin")}:${process.env.PATH}`,
        WORKERS_CI: "1",
        WORKERS_CI_BRANCH: mode === "preview" ? "feature" : "main",
        TEST_MODE: mode,
        TEST_STATE: statePath,
      },
    });
    assert.ifError(result.error);
    return { ...result, state: JSON.parse(readFileSync(statePath, "utf8")) };
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
}

test("failed preparation never migrates or changes production", () => {
  for (const mode of ["build-failure", "wrong-worker", "preview"]) {
    const result = releaseScenario(mode);
    assert.equal(result.status, 1, result.stdout + result.stderr);
    assert.equal(result.state.migrated, false, mode);
    assert.equal(result.state.active, "old", mode);
    if (mode === "preview") assert.equal(result.state.calls, 0);
  }
});

test("failed or incomplete migrations never promote the uploaded version", () => {
  for (const mode of ["migration-failure", "missing-migration"]) {
    const result = releaseScenario(mode);
    assert.equal(result.status, 1, result.stdout + result.stderr);
    assert.equal(result.state.active, "old", mode);
  }
});

test("unhealthy or superseded deployments fail without an automatic rollback", () => {
  for (const mode of ["unhealthy", "superseded"]) {
    const result = releaseScenario(mode);
    assert.equal(result.status, 1, result.stdout + result.stderr);
    assert.equal(result.state.active, version, mode);
  }
});

test("healthy release promotes only after database preparation", () => {
  const result = releaseScenario("healthy");
  assert.equal(result.status, 0, result.stdout + result.stderr);
  assert.equal(result.state.migrated, true);
  assert.equal(result.state.active, version);
});

test("HTTP verification rejects SPA fallbacks, redirects, and wrong account responses", async (t) => {
  let mode = "healthy";
  const server = createServer((request, response) => {
    assert.equal(request.headers.cookie, undefined);
    if (request.url === "/api/auth/ok") {
      response.writeHead(200, { "Content-Type": "application/json" });
      response.end('{"ok":true}');
    } else if (mode === "redirect") {
      response.writeHead(302, { Location: "/api/auth/ok" });
      response.end();
    } else if (mode === "html") {
      response.writeHead(401, { "Content-Type": "text/html" });
      response.end("<!doctype html><title>Loomark</title>");
    } else if (mode === "invalid-json") {
      response.writeHead(401, { "Content-Type": "application/json" });
      response.end("private-response-content");
    } else {
      response.writeHead(mode === "unavailable" ? 503 : 401, { "Content-Type": "application/json" });
      response.end(JSON.stringify({ error: mode === "healthy" ? "sign_in_required" : "account_unavailable" }));
    }
  });
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  t.after(() => { server.closeAllConnections(); server.close(); });
  const origin = `http://127.0.0.1:${server.address().port}`;
  await checkProduction(origin);
  for (mode of ["html", "redirect", "wrong-body", "unavailable", "invalid-json"]) {
    await assert.rejects(checkProduction(origin), (error) => {
      assert.equal(error.message.includes("private-response-content"), false);
      return true;
    });
  }
});
