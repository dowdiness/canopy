import { defineConfig, type PluginOption } from 'vite';
import { moonbitPlugin } from '../web/vite-plugin-moonbit';

export default defineConfig({
  plugins: [
    moonbitPlugin({
      modules: [
        {
          name: '@moonbit/canopy',
          path: '../..',
          output: '_build/js/release/build/ffi/ffi.js'
        }
      ]
    }) as PluginOption
  ],
  resolve: {
    // Ensure packages imported by lib/editor-adapter/ (which lives
    // outside this project's node_modules tree) resolve from here.
    dedupe: [
      'prosemirror-commands',
      'prosemirror-keymap',
      'prosemirror-model',
      'prosemirror-state',
      'prosemirror-transform',
      'prosemirror-view',
      '@codemirror/commands',
      '@codemirror/language',
      '@codemirror/state',
      '@codemirror/view',
    ],
  },
  server: {
    fs: {
      // Allow reading MoonBit build output and lib/ from the monorepo root
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
