import { defineConfig } from "@playwright/test"
import standalone from "./playwright.standalone.config"

export default defineConfig(standalone, {
  testMatch: "long-document-performance.spec.ts",
  workers: 1,
  retries: 0,
  timeout: 120_000,
  outputDir: "test-results/performance",
  reporter: [["list"], ["json", { outputFile: "test-results/performance.json" }]],
  use: {
    browserName: "chromium",
    viewport: { width: 1280, height: 900 },
  },
})
