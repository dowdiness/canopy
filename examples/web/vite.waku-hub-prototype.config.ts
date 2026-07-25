import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

/**
 * Isolated delivery shell for the throwaway Demo Hub prototype.
 *
 * The Hub does not import generated MoonBit modules, so loading the main web
 * config would wastefully start five repository-wide MoonBit watch processes.
 */
export default defineConfig({
  plugins: [react()],
  build: {
    target: 'esnext',
    rollupOptions: {
      input: {
        wakuHubPrototype: 'waku-hub-prototype.html',
      },
    },
  },
});
