import { readFileSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';

import react from '@vitejs/plugin-react';
import { defineConfig, loadEnv } from 'vite';

// `npm run build:prod` (mode "prod", .env.prod) builds production's pages.
// Their assetlinks.json comes from assetlinks.prod.json instead of public/,
// so the development app's debug certificate never reaches production.
function productionAssetLinks() {
  let outDir;
  return {
    name: 'production-assetlinks',
    apply: 'build',
    configResolved(config) {
      outDir = resolve(config.root, config.build.outDir);
    },
    closeBundle() {
      const links = readFileSync('assetlinks.prod.json', 'utf8');
      JSON.parse(links);
      writeFileSync(resolve(outDir, '.well-known/assetlinks.json'), links);
    },
  };
}

export default defineConfig(({ command, mode }) => {
  // A production build fixes this address in the pages, so a missing or example
  // value must stop the build, not reach a deployment.
  if (command === 'build') {
    const url = loadEnv(mode, process.cwd(), 'VITE_').VITE_NEON_AUTH_URL ?? '';
    if (!url.startsWith('https://') || url.includes('ep-example')) {
      throw new Error('Set VITE_NEON_AUTH_URL in .env.local. See README.md.');
    }
  }
  return {
    plugins: [react(), ...(mode === 'prod' ? [productionAssetLinks()] : [])],
  };
});
