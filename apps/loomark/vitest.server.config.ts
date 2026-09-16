import { cloudflareTest, readD1Migrations } from "@cloudflare/vitest-plugin";
import { defineConfig } from "vitest/config";

export default defineConfig({
  plugins: [cloudflareTest({
    // No deployment build or remote resources in the server test suite.
    miniflare: {
      compatibilityDate: "2026-09-16",
      compatibilityFlags: ["nodejs_compat"],
      d1Databases: ["AUTH_DB"],
      bindings: {
        TEST_MIGRATIONS: await readD1Migrations("./server/migrations"),
        BETTER_AUTH_URL: "https://loomark.test",
        BETTER_AUTH_SECRET: "test-only-secret-with-more-than-32-characters",
        GOOGLE_CLIENT_ID: "test-google-client",
        GOOGLE_CLIENT_SECRET: "test-google-secret",
      },
    },
  })],
  test: { include: ["server/**/*.test.ts"], setupFiles: ["./server/test-setup.ts"] },
});
