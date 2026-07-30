import { defineConfig } from "vite";

export default defineConfig({
  build: {
    outDir: "dist/cm6-test",
    emptyOutDir: true,
    rollupOptions: {
      input: new URL("./test/cm6-diagnostics.html", import.meta.url).pathname,
    },
  },
});
