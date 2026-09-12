import { defineConfig } from "@playwright/test"

const port = Number.parseInt(process.env.LOOMARK_STANDALONE_PORT ?? "4317", 10)
export default defineConfig({
  testDir: "./tests",
  testMatch: "demand.spec.ts",
  timeout: 30_000,
  fullyParallel: false,
  reporter: [["list"]],
  use: { baseURL: `http://127.0.0.1:${port}` },
})
