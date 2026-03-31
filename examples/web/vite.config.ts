import { defineConfig } from 'vite';
import { moonbitPlugin } from './vite-plugin-moonbit';

export default defineConfig({
  plugins: [
    moonbitPlugin({
      modules: [
        {
          name: '@moonbit/crdt',
          path: '../..',
          output: '_build/js/release/build/canopy.js'
        },
        {
          name: '@moonbit/graphviz',
          path: '../../graphviz',
          output: '_build/js/release/build/browser/browser.js'
        }
      ]
    })
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
      },
    },
  },
  optimizeDeps: {
    exclude: ['*.wasm', '@moonbit/crdt', '@moonbit/graphviz']
  }
});
