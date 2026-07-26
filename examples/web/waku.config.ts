import { defineConfig } from 'waku/config';
import { astGrepPlugin } from './server/vite/ast-grep';
import {
  createMoonbitArtifactsPlugin,
  moonbitImportIds,
} from './server/vite/moonbit';

export default defineConfig({
  unstable_adapter: 'waku/adapters/cloudflare',
  vite: {
    plugins: [
      astGrepPlugin(),
      createMoonbitArtifactsPlugin({ watch: true }),
    ],
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
