import { defineConfig } from "@playwright/test"
import standalone from "./playwright.standalone.config"

export default defineConfig({
  ...standalone,
  testMatch: "sidebar.spec.ts",
})
