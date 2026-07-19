import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

export default defineConfig({
  plugins: [react()],
  server: {
    // Local dev only (npm run dev) — proxies API calls so you
    // don't need Nginx running during development.
    proxy: {
      "/auth":   "http://localhost:5001",
      "/books":  "http://localhost:5002",
      "/borrow": "http://localhost:5003",
    },
  },
  build: {
    outDir: "dist",
    sourcemap: false,   // disable in production to reduce bundle size
  },
});
