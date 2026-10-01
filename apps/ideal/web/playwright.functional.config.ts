import { defineConfig } from '@playwright/test';
import config from './playwright.config';

export default defineConfig(config, {
  testIgnore: '**/editor-response.perf.spec.ts',
});
