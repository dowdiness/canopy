import { defineConfig } from '@playwright/test';

const port = Number(process.env.CANOPY_WAKU_PREVIEW_PORT ?? '4193');
if (!Number.isInteger(port) || port < 1 || port > 65_535) {
  throw new Error('CANOPY_WAKU_PREVIEW_PORT must be a valid TCP port.');
}

process.env.GENUI_PREVIEW_URL = '/genui';

export default defineConfig({
  testDir: './preview-tests',
  testMatch: 'genui-preview.spec.ts',
  timeout: 30_000,
  retries: 0,
  use: {
    baseURL: `http://127.0.0.1:${port}`,
  },
  webServer: {
    command: `CANOPY_WAKU_PREVIEW_PORT=${port} bash scripts/serve-waku-preview.sh`,
    url: `http://127.0.0.1:${port}/genui`,
    reuseExistingServer: false,
    timeout: 240_000,
  },
  projects: [
    { name: 'chromium', use: { browserName: 'chromium' } },
  ],
});
