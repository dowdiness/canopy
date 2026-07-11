import { defineConfig } from 'vitest/config';
import react from '@vitejs/plugin-react';
import path from 'path';
import fs from 'fs';

// Check if the MoonBit build output exists
const moonbitBuildPath = path.resolve(__dirname, '../../_build/js/release/build/dowdiness/canopy/ffi/lambda/lambda.js');
const hasMoonbitBuild = fs.existsSync(moonbitBuildPath);

export default defineConfig({
  plugins: [react()],
  test: {
    environment: 'jsdom',
    globals: true,
    setupFiles: ['./src/test/setup.ts'],
    include: ['src/**/*.test.{ts,tsx}'],
  },
  resolve: {
    alias: {
      '@moonbit/crdt': hasMoonbitBuild
        ? moonbitBuildPath
        : path.resolve(__dirname, 'src/features/editor/crdt-stub-module.ts'),
    },
  },
});
