import { defineConfig } from 'vite';
import { visualizer } from 'rollup-plugin-visualizer';
import { moonbitPlugin } from './vite-plugin-moonbit';

const analyze = process.env.ANALYZE === '1';

export default defineConfig({
  plugins: [
    moonbitPlugin({
      modules: [
        {
          name: '@moonbit/crdt-lambda',
          path: '../..',
          output: '_build/js/release/build/dowdiness/canopy/ffi/lambda/lambda.js'
        },
        {
          name: '@moonbit/crdt-json',
          path: '../..',
          output: '_build/js/release/build/dowdiness/canopy/ffi/json/json.js'
        },
        {
          name: '@moonbit/crdt-markdown',
          path: '../..',
          output: '_build/js/release/build/dowdiness/canopy/ffi/markdown/markdown.js'
        },
        {
          name: '@moonbit/graphviz',
          path: '../../graphviz',
          output: '../_build/js/release/build/dowdiness/graphviz/browser/browser.js'
        }
      ]
    }),
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
      // Allow the example app to read MoonBit build output from the repo root
      // and sibling submodules above `examples/web/`.
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
      },
    },
  },
  optimizeDeps: {
    exclude: ['*.wasm', '@moonbit/crdt-lambda', '@moonbit/crdt-json', '@moonbit/crdt-markdown', '@moonbit/graphviz']
  }
});
