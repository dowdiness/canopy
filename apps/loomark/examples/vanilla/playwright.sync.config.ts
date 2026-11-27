import { defineConfig } from "@playwright/test"

export default defineConfig({
  testDir: "./tests",
  testMatch: "sync.spec.ts",
  timeout: 120_000,
  fullyParallel: false,
  workers: 1,
  reporter: [["list"]],
  // CI uploads test-results when this suite fails; keep only failures there.
  preserveOutput: "failures-only",
  // Bound actions and request waits so a hang names its step instead of
  // surfacing only as the test timeout.
  use: { actionTimeout: 15_000 },
})
