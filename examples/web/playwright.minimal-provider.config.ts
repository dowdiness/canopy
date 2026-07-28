import { realpathSync } from 'node:fs';
import { isAbsolute, join } from 'node:path';
import { defineConfig } from '@playwright/test';

const suppliedRoot = process.env.GENUI_MINIMAL_PROVIDER_RUN_DIR;
if (!suppliedRoot || !isAbsolute(suppliedRoot)) throw new Error('GENUI_MINIMAL_PROVIDER_RUN_DIR must be absolute');
const runRoot = realpathSync(suppliedRoot);

export default defineConfig({
  testDir: './tests',
  testMatch: 'genui-minimal-provider.spec.ts',
  retries: 0,
  fullyParallel: false,
  outputDir: join(runRoot, '.playwright'),
  use: { baseURL: 'http://127.0.0.1:4176', trace: 'off' },
  webServer: {
    command: 'moon build --target js && npm run dev:waku -- --host 127.0.0.1 --port 4176',
    url: 'http://127.0.0.1:4176/genui',
    reuseExistingServer: false,
    timeout: 120_000,
  },
  projects: [{ name: 'chromium', use: { browserName: 'chromium' } }],
});
