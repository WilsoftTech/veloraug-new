import react from '@vitejs/plugin-react';
import { defineConfig, loadEnv } from 'vite';

export default defineConfig(({ command, mode }) => {
  // A production build fixes this address in the pages, so a missing or example
  // value must stop the build, not reach a deployment.
  if (command === 'build') {
    const url = loadEnv(mode, process.cwd(), 'VITE_').VITE_NEON_AUTH_URL ?? '';
    if (!url.startsWith('https://') || url.includes('ep-example')) {
      throw new Error('Set VITE_NEON_AUTH_URL in .env.local. See README.md.');
    }
  }
  return { plugins: [react()] };
});
