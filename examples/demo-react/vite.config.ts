import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import path from 'path';
import fs from 'fs';

// Check if the MoonBit build output exists
const moonbitBuildPath = path.resolve(__dirname, '../../_build/js/release/build/dowdiness/canopy/ffi/lambda/lambda.js');
const hasMoonbitBuild = fs.existsSync(moonbitBuildPath);

if (!hasMoonbitBuild) {
  console.info('[vite] MoonBit build not found at', moonbitBuildPath);
  console.info('[vite] Will use stub CRDT module. Run `moon build --target js` for real CRDT.');
}

export default defineConfig({
  plugins: [react()],
  resolve: {
    alias: {
      // Point to real MoonBit build if available, otherwise stub
      '@moonbit/crdt': hasMoonbitBuild
        ? moonbitBuildPath
        : path.resolve(__dirname, 'src/features/editor/crdt-stub-module.ts'),
    },
  },
  server: {
    port: 5174,
  },
});
