import { defineConfig } from '@playwright/test';

const port = Number(process.env.PI_RESUME_TEST_PORT ?? '5173');
if (!Number.isInteger(port) || port < 1 || port > 65_535) {
  throw new Error('PI_RESUME_TEST_PORT must be a valid TCP port.');
}

export default defineConfig({
  testDir: './tests',
  timeout: 30_000,
  retries: 0,
  use: {
    baseURL: `http://localhost:${port}`,
  },
  webServer: {
    command: `PI_RESUME_CHAT_FAKE=1 PI_RESUME_CHAT_FAKE_DELAY_MS=400 npx vite --port ${port}`,
    port,
    reuseExistingServer: process.env.PI_RESUME_REUSE_SERVER === '1',
    timeout: 120_000,
  },
  projects: [
    { name: 'chromium', use: { browserName: 'chromium' } },
  ],
});
