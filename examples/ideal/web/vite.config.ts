import { defineConfig, type PluginOption } from 'vite';
import { moonbitPlugin } from '../../web/vite-plugin-moonbit';

// Workspace builds emit namespaced artifacts at the repo root; MOON_WORK=off
// builds the standalone ideal module under examples/ideal/_build.
const idealEditorOutput = process.env.MOON_WORK === 'off'
  ? '_build/js/release/build/main/main.js'
  : '../../_build/js/release/build/dowdiness/ideal-editor/main/main.js';

export default defineConfig({
  plugins: [
    moonbitPlugin({
      modules: [
        {
          // Single module: includes Rabbita app + CRDT FFI exports.
          // No separate @moonbit/canopy needed (saves 7.6MB load).
          name: '@moonbit/ideal-editor',
          path: '..',
          output: idealEditorOutput
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
