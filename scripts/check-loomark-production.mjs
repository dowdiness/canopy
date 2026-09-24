#!/usr/bin/env node
import { pathToFileURL } from "node:url";

export const productionOrigin = "https://loomark.koji-ishimoto.workers.dev";

// No cookies, redirects, or response bodies in logs. A login page or SPA fallback
// is not a healthy account service. Include body consumption in the deadline.
export async function checkProduction(origin = productionOrigin) {
  for (const [path, status, field, value] of [
    ["/api/auth/ok", 200, "ok", true],
    ["/api/account", 401, "error", "sign_in_required"],
  ]) {
    const response = await fetch(new URL(path, origin), {
      redirect: "error",
      credentials: "omit",
      cache: "no-store",
      signal: AbortSignal.timeout(15_000),
    });
    if (response.status !== status ||
        !response.headers.get("content-type")?.includes("application/json")) {
      await response.body?.cancel();
      throw new Error(`${path}: expected JSON HTTP ${status}, got HTTP ${response.status}`);
    }
    const body = await response.json().catch(() => {
      throw new Error(`${path}: could not read a JSON response`);
    });
    if (body?.[field] !== value) {
      throw new Error(`${path}: unexpected response contract`);
    }
    console.log(`PASS ${path}: HTTP ${status}`);
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    await checkProduction();
  } catch (error) {
    console.error(`Production verification failed: ${error.message}`);
    process.exitCode = 1;
  }
}
