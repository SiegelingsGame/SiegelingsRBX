// Build the game as the TCG site's "Swarm" test mode and copy it into a SiegelingTCG checkout.
// Usage: npm run build:tcg -- /path/to/SiegelingTCG
import { execSync } from 'node:child_process';
import { cpSync, rmSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const tcg = process.argv[2];
if (!tcg || !existsSync(join(tcg, 'src/main/resources/static'))) {
  console.error('Pass the path to a SiegelingTCG checkout.');
  process.exit(1);
}
execSync('node scripts/build-model-manifest.mjs && npx vite build --outDir dist-tcg', {
  cwd: root, stdio: 'inherit', env: { ...process.env, SG_BASE: '/swarm/', VITE_TCG: '1' },
});
rmSync(join(root, 'dist-tcg/models/README.md'), { force: true });
const dest = join(tcg, 'src/main/resources/static/swarm');
rmSync(dest, { recursive: true, force: true });
cpSync(join(root, 'dist-tcg'), dest, { recursive: true });
console.log(`copied build to ${dest}`);
