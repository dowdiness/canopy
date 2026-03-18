import { defineConfig } from 'vite';
import { moonbitPlugin } from '../web/vite-plugin-moonbit';

export default defineConfig({
  plugins: [
    moonbitPlugin({
      modules: [
        {
          name: '@moonbit/crdt',
          path: '../..',
          output: '_build/js/release/build/crdt.js'
        }
      ]
    })
  ],
  server: {
    fs: {
      // Allow reading MoonBit build output from the monorepo root
      allow: ['../..']
    }
  },
  build: {
    target: 'esnext'
  },
  optimizeDeps: {
    exclude: ['@moonbit/crdt']
  }
});
