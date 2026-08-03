import tailwindcss from '@tailwindcss/vite';
import { defineConfig } from 'waku/config';
import { astGrepPlugin } from './server/vite/ast-grep';
import { genUiFeasibilityPlugin } from './server/vite/genui-feasibility';
import { piResumeChatPlugin } from './server/vite/resume-chat';
import {
  createMoonbitArtifactsPlugin,
  moonbitImportIds,
} from './server/vite/moonbit';

export default defineConfig({
  unstable_adapter: 'waku/adapters/cloudflare',
  vite: {
    plugins: [
      tailwindcss(),
      genUiFeasibilityPlugin(),
      piResumeChatPlugin(),
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
