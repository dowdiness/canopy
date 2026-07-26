import { defineConfig } from 'waku/config';
import {
  createMoonbitArtifactsPlugin,
  moonbitImportIds,
} from './server/vite/moonbit';

export default defineConfig({
  unstable_adapter: 'waku/adapters/cloudflare',
  vite: {
    plugins: [createMoonbitArtifactsPlugin({ watch: true })],
    server: {
      fs: {
        allow: ['../..'],
      },
    },
    optimizeDeps: {
      exclude: ['*.wasm', ...moonbitImportIds],
    },
  },
});
