import { defineConfig, type PluginOption } from 'vite';
import { moonbitPlugin } from '../../web/vite-plugin-moonbit';

export default defineConfig({
  plugins: [
    moonbitPlugin({
      modules: [
        {
          name: '@moonbit/ideal-editor',
          path: '..',
          output: '_build/js/release/build/main/main.js'
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
