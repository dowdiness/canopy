import { defineConfig, type PluginOption } from 'vite';
import { moonbitPlugin } from '../web/vite-plugin-moonbit';

export default defineConfig({
  plugins: [
    moonbitPlugin({
      modules: [
        {
          name: '@moonbit/canopy',
          path: '../..',
          output: '_build/js/release/build/dowdiness/canopy/ffi/lambda/lambda.js'
        }
      ]
    }) as PluginOption
  ],
  resolve: {
    // @canopy/editor-adapter is symlinked into node_modules; vite realpaths
    // through the symlink, so dedupe is still needed to pin prosemirror/*
    // and @codemirror/* to this project's copies rather than the adapter's
    // (nonexistent) node_modules.
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
      // Allow reading MoonBit build output and adapters/ from the monorepo root
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
