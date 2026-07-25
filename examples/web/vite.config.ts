import { defineConfig } from 'vite';
import { visualizer } from 'rollup-plugin-visualizer';
import { createWebPlugins, moonbitImportIds } from './server/vite/web-plugins';

const analyze = process.env.ANALYZE === '1';

export default defineConfig({
  plugins: [
    ...createWebPlugins({ watchMoonBit: true }),
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
