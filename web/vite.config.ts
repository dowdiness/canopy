import { defineConfig } from 'vite';
import { moonbitPlugin } from './vite-plugin-moonbit';

export default defineConfig({
  plugins: [
    moonbitPlugin({
      modules: [
        {
          name: '@moonbit/crdt',
          path: '..',
          output: 'target/js/release/build/crdt.js'
        },
        {
          name: '@moonbit/graphviz',
          path: '../graphviz',
          output: 'target/js/release/build/browser/browser.js'
        }
      ]
    })
  ],
  server: {
    fs: {
      // Allow serving files from parent directory
      allow: ['..']
    }
  },
  build: {
    target: 'esnext'
  },
  optimizeDeps: {
    exclude: ['*.wasm', '@moonbit/crdt', '@moonbit/graphviz']
  }
});
