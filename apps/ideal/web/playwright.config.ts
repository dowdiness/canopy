import { defineConfig, devices } from '@playwright/test';

const webServer = [
  {
    // CANOPY_SKIP_MOON_BUILD=1 (CI Playwright container, no MoonBit
    // toolchain) skips the prebuild and relies on pre-built artifacts
    // downloaded by the build-js job.
    command: process.env.CANOPY_SKIP_MOON_BUILD === '1'
      ? 'npx vite --port 5190 --strictPort'
      : 'npm run prebuild:moonbit && npx vite --port 5190 --strictPort',
    url: 'http://localhost:5190',
    reuseExistingServer: !process.env.CI,
    timeout: 120000,
  },
  ...(
    process.env.CANOPY_SKIP_RELAY_SERVER
      ? []
      : [{
          command: 'npm run server',
          port: 8787,
          reuseExistingServer: !process.env.CI,
          timeout: 15000,
        }]
  ),
];

export default defineConfig({
  testDir: './e2e',
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 2 : 0,
  workers: process.env.CI ? 1 : undefined,
  reporter: process.env.CI ? 'line' : 'html',
  use: {
    baseURL: 'http://localhost:5190',
    trace: 'on-first-retry',
  },
  projects: [
    {
      name: 'chromium',
      use: { ...devices['Desktop Chrome'] },
    },
  ],
  webServer,
});
