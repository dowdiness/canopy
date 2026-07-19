import { defineConfig } from 'vite';
import { visualizer } from 'rollup-plugin-visualizer';
import { moonbitPlugin } from './vite-plugin-moonbit';
import tailwindcss from '@tailwindcss/vite';
import { genUiFeasibilityPlugin } from './vite-plugin-genui-feasibility';

const analyze = process.env.ANALYZE === '1';

export default defineConfig({
  plugins: [
    tailwindcss(),
    genUiFeasibilityPlugin(),
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
          name: '@moonbit/crdt-jsx',
          path: '../..',
          output: '_build/js/release/build/dowdiness/canopy/ffi/jsx/jsx.js'
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
        genui: 'genui.html',
        genuiPossibilities: 'genui-possibilities.html',
      },
    },
  },
  optimizeDeps: {
    exclude: ['*.wasm', '@moonbit/crdt-lambda', '@moonbit/crdt-json', '@moonbit/crdt-markdown', '@moonbit/crdt-jsx', '@moonbit/graphviz']
  }
});
