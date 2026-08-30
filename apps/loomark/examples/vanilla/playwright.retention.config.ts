import { defineConfig } from "@playwright/test"

const portText = process.env.LOOMARK_STANDALONE_PORT ?? "4317"
const port = Number(portText)
if (!/^\d+$/.test(portText) || !Number.isInteger(port) || port < 1 || port > 65_535) {
  throw new Error("LOOMARK_STANDALONE_PORT must be an integer from 1 through 65535")
}

export default defineConfig({
  testDir: "./tests",
  testMatch: "retention.spec.ts",
  timeout: 600_000,
  fullyParallel: false,
  reporter: [["list"]],
  use: {
    baseURL: `http://127.0.0.1:${port}`,
    launchOptions: {
      args: ["--js-flags=--expose-gc", "--enable-precise-memory-info"],
    },
  },
})
