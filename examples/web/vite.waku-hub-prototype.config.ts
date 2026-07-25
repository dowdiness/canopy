import { defineConfig } from 'vite';
import { createWebPlugins, moonbitImportIds } from './server/vite/web-plugins';

/**
 * Isolated delivery shell for the throwaway Demo Hub prototype.
 *
 * Existing demo routes still need their normal Vite capabilities and MoonBit
 * virtual modules. Generated artifacts are built once by the launcher; this
 * config resolves them without starting repository-wide MoonBit watchers.
 */
export default defineConfig({
  plugins: createWebPlugins({ watchMoonBit: false }),
  optimizeDeps: {
    exclude: ['*.wasm', ...moonbitImportIds],
  },
  build: {
    target: 'esnext',
    rollupOptions: {
      input: {
        wakuHubPrototype: 'waku-hub-prototype.html',
      },
    },
  },
});
