import { defineConfig } from "@playwright/test"

export default defineConfig({
  testDir: "./tests",
  testMatch: "dev-host.spec.ts",
  timeout: 30_000,
  fullyParallel: true,
  reporter: [["list"]],
  use: {
    launchOptions: {
      args: ["--allow-file-access-from-files"],
    },
  },
})
