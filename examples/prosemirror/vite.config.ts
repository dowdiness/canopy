import { defineConfig, type PluginOption } from 'vite';
import { moonbitPlugin } from '../web/vite-plugin-moonbit';

export default defineConfig({
  plugins: [
    moonbitPlugin({
      modules: [
        {
          name: '@moonbit/canopy',
          path: '../..',
          output: '_build/js/release/build/canopy.js'
        }
      ]
    }) as PluginOption
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
    exclude: ['@moonbit/canopy']
  }
});
