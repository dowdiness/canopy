import { defineConfig, type PluginOption } from 'vite';
import { moonbitPlugin } from '../../web/vite-plugin-moonbit';

export default defineConfig({
  plugins: [
    moonbitPlugin({
      modules: [
        {
          // Single module: includes Rabbita app + CRDT FFI exports.
          // No separate @moonbit/canopy needed (saves 7.6MB load).
          name: '@moonbit/ideal-editor',
          path: '..',
          output: '../../_build/js/release/build/dowdiness/ideal-editor/main/main.js'
        }
      ]
    }) as PluginOption
  ],
  server: {
    fs: {
      allow: ['../../..']
    }
  },
  build: {
    target: 'esnext'
  },
  optimizeDeps: {
    exclude: ['@moonbit/ideal-editor']
  }
});
