// Scan web/public/models for creature models and write models/manifest.json
// ({ "<lowercased file name without extension>": "<file name>" }). Runs before dev and build.
import { readdirSync, writeFileSync, existsSync, mkdirSync } from 'node:fs';
import { join, dirname, extname, basename } from 'node:path';
import { fileURLToPath } from 'node:url';

const dir = join(dirname(fileURLToPath(import.meta.url)), '..', 'public', 'models');
if (!existsSync(dir)) mkdirSync(dir, { recursive: true });
const manifest = {};
for (const f of readdirSync(dir).sort()) {
  const ext = extname(f).toLowerCase();
  if (ext !== '.glb' && ext !== '.gltf') continue;
  manifest[basename(f, extname(f)).toLowerCase()] = f;
}
writeFileSync(join(dir, 'manifest.json'), JSON.stringify(manifest, null, 1) + '\n');
console.log(`models manifest: ${Object.keys(manifest).length} model(s)`);
