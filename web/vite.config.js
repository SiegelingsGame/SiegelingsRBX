import { defineConfig } from 'vite';

export default defineConfig({
  base: process.env.SG_BASE || './', // '/swarm/' when built into the TCG site
  server: { host: true, port: 5173 },
  build: { chunkSizeWarningLimit: 1500 },
});
