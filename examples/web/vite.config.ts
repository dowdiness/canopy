import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import { visualizer } from 'rollup-plugin-visualizer';
import tailwindcss from '@tailwindcss/vite';
import { genUiFeasibilityPlugin } from './server/vite/genui-feasibility';
import { piResumeChatPlugin } from './server/vite/resume-chat';
import { astGrepPlugin } from './server/vite/ast-grep';
import {
  createMoonbitArtifactsPlugin,
  moonbitImportIds,
} from './server/vite/moonbit';

const analyze = process.env.ANALYZE === '1';

export default defineConfig({
  plugins: [
    react(),
    tailwindcss(),
    genUiFeasibilityPlugin(),
    piResumeChatPlugin(),
    astGrepPlugin(),
    createMoonbitArtifactsPlugin({ watch: true }),
    ...(analyze
      ? [
          visualizer({
            filename: 'dist/bundle-stats.html',
            template: 'treemap',
            gzipSize: true,
            brotliSize: true,
          }),
        ]
      : []),
  ],
  server: {
    fs: {
      allow: ['../..']
    }
  },
  build: {
    target: 'esnext',
    rollupOptions: {
      input: {
        main: 'index.html',
        json: 'json.html',
        memo: 'memo.html',
        markdown: 'markdown.html',
        posts: 'posts.html',
        resume: 'resume.html',
        genui: 'genui.html',
        genuiPossibilities: 'genui-possibilities.html',
      },
    },
  },
  optimizeDeps: {
    exclude: ['*.wasm', ...moonbitImportIds]
  }
});
