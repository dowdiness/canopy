import { defineConfig } from '@playwright/test';

const port = Number(process.env.CANOPY_WAKU_TEST_PORT ?? '5183');
if (!Number.isInteger(port) || port < 1 || port > 65_535) {
  throw new Error('CANOPY_WAKU_TEST_PORT must be a valid TCP port.');
}

process.env.GENUI_POSSIBILITIES_URL = '/journey';
process.env.POSTS_URL = '/posts';
process.env.LAMBDA_EDITOR_URL = '/ml';
process.env.MEMO_EDITOR_URL = '/memo';
process.env.JSON_EDITOR_URL = '/json';
process.env.MARKDOWN_EDITOR_URL = '/markdown';
process.env.PI_RESUME_URL = '/resume';

export default defineConfig({
  testDir: '.',
  testMatch: [
    'waku-tests/**/*.spec.ts',
    'tests/genui-possibilities.spec.ts',
    'tests/lambda-editor.spec.ts',
    'tests/memo-editor.spec.ts',
    'tests/json-editor.spec.ts',
    'tests/markdown-editor.spec.ts',
    'tests/post-app.spec.ts',
    'tests/pi-resume.spec.ts',
  ],
  timeout: 30_000,
  retries: 0,
  use: {
    baseURL: `http://localhost:${port}`,
  },
  webServer: {
    command: `PI_RESUME_CHAT_FAKE=1 PI_RESUME_CHAT_FAKE_DELAY_MS=400 CANOPY_SKIP_MOON_BUILD=1 npm run dev:waku -- --port ${port}`,
    port,
    reuseExistingServer: false,
    timeout: 120_000,
  },
  projects: [
    { name: 'chromium', use: { browserName: 'chromium' } },
  ],
});
