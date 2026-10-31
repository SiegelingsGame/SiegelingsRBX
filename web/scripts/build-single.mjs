// Inline the Vite build into one self-contained HTML file (used for the hosted artifact page).
// Usage: npm run build && node scripts/build-single.mjs [outFile]
import { readFileSync, writeFileSync, readdirSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const assets = join(root, 'dist', 'assets');
const files = readdirSync(assets);
const js = readFileSync(join(assets, files.find((f) => f.endsWith('.js'))), 'utf8').replace(/<\/script/gi, '<\\/script');
const css = readFileSync(join(assets, files.find((f) => f.endsWith('.css'))), 'utf8');
const html = readFileSync(join(root, 'index.html'), 'utf8');
const body = html.slice(html.indexOf('<body>') + 6, html.indexOf('<script type="module"')).trim();
const out = process.argv[2] || join(root, 'dist', 'siegelings.html');
writeFileSync(out, `<title>Siegelings</title>\n<style>\n${css}\n</style>\n${body}\n<script type="module">\n${js}\n</script>\n`);
console.log(`wrote ${out} (${(Buffer.byteLength(readFileSync(out)) / 1024).toFixed(0)} KB)`);
