import { defineConfig } from "@playwright/test"

const environment = (globalThis as {
  process?: { env?: Record<string, string | undefined> }
}).process?.env
const port = Number.parseInt(environment?.LOOMARK_FIXTURE_PORT ?? "4326", 10)

export default defineConfig({
  testDir: "./tests",
  testMatch: "worker-lifecycle.spec.ts",
  timeout: 30_000,
  fullyParallel: false,
  reporter: [["list"]],
  use: { baseURL: `http://127.0.0.1:${port}` },
})
