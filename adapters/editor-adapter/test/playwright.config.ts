import { fileURLToPath } from "node:url";
import { defineConfig, devices } from "@playwright/test";

const adapterDir = fileURLToPath(new URL("..", import.meta.url));

export default defineConfig({
  testDir: ".",
  testMatch: "cm6-diagnostics.spec.ts",
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 2 : 0,
  workers: process.env.CI ? 1 : undefined,
  reporter: process.env.CI ? "line" : "list",
  use: {
    baseURL: "http://127.0.0.1:5197",
    trace: "on-first-retry",
  },
  projects: [
    {
      name: "chromium",
      use: { ...devices["Desktop Chrome"] },
    },
  ],
  webServer: {
    cwd: adapterDir,
    command: "node ./node_modules/vite/bin/vite.js --config vite.config.cm6-test.ts --host 127.0.0.1 --port 5197 --strictPort",
    url: "http://127.0.0.1:5197/test/cm6-diagnostics.html",
    reuseExistingServer: false,
    timeout: 120_000,
  },
});
