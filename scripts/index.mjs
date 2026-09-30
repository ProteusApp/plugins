// Writes index.json, the list of approved plugins the Proteus store reads. The index
// workflow runs it after every merge to main. Each entry names the last commit that changed
// the plugin's folder, so the app installs exactly what was approved.

import { execFileSync } from 'node:child_process';
import { existsSync, readFileSync, readdirSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { buildIndex } from './registry.mjs';

const entries = [];
for (const id of existsSync('plugins') ? readdirSync('plugins') : []) {
  const path = join('plugins', id, 'proteus.json');
  if (!existsSync(path)) continue;
  const manifest = JSON.parse(readFileSync(path, 'utf8'));
  const [commit, updated] = execFileSync('git', ['log', '-1', '--format=%H%n%cI', '--', join('plugins', id)], {
    encoding: 'utf8',
  })
    .trim()
    .split('\n');
  entries.push({ manifest, commit, updated });
}

writeFileSync('index.json', JSON.stringify(buildIndex(entries), null, 2) + '\n');
console.log(`index.json lists ${entries.length} plugin${entries.length === 1 ? '' : 's'}.`);
