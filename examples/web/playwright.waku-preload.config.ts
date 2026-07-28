import { defineConfig } from '@playwright/test';

const port = Number(process.env.CANOPY_WAKU_PRELOAD_PORT ?? '4194');
if (!Number.isInteger(port) || port < 1 || port > 65_535) {
  throw new Error('CANOPY_WAKU_PRELOAD_PORT must be a valid TCP port.');
}

export default defineConfig({
  testDir: './preview-tests',
  testMatch: 'preload-recovery.spec.ts',
  timeout: 30_000,
  retries: 0,
  workers: 1,
  use: {
    baseURL: `http://127.0.0.1:${port}`,
  },
  webServer: {
    command: `CANOPY_SKIP_WAKU_BUILD=1 CANOPY_WAKU_PREVIEW_PORT=${port} bash scripts/serve-waku-preview.sh`,
    url: `http://127.0.0.1:${port}/ml`,
    reuseExistingServer: false,
    timeout: 120_000,
  },
  projects: [
    { name: 'chromium', use: { browserName: 'chromium' } },
  ],
});
