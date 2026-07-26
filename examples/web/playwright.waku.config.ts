import { defineConfig } from '@playwright/test';

const port = Number(process.env.CANOPY_WAKU_TEST_PORT ?? '5183');
if (!Number.isInteger(port) || port < 1 || port > 65_535) {
  throw new Error('CANOPY_WAKU_TEST_PORT must be a valid TCP port.');
}

process.env.GENUI_POSSIBILITIES_URL = '/journey';

export default defineConfig({
  testDir: '.',
  testMatch: [
    'waku-tests/**/*.spec.ts',
    'tests/genui-possibilities.spec.ts',
  ],
  timeout: 30_000,
  retries: 0,
  use: {
    baseURL: `http://localhost:${port}`,
  },
  webServer: {
    command: `CANOPY_SKIP_MOON_BUILD=1 npm run dev:waku -- --port ${port}`,
    port,
    reuseExistingServer: false,
    timeout: 120_000,
  },
  projects: [
    { name: 'chromium', use: { browserName: 'chromium' } },
  ],
});
