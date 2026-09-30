// Writes index.json, the list of approved plugins and profiles the Proteus marketplace reads.
// The index workflow runs it after every merge to main. Each entry names the last commit that
// changed its folder, so the app installs exactly what was approved.

import { execFileSync } from 'node:child_process';
import { existsSync, readFileSync, readdirSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { buildIndex } from './registry.mjs';

const entries = [];
for (const root of ['plugins', 'profiles']) {
  for (const id of existsSync(root) ? readdirSync(root) : []) {
    const path = join(root, id, 'proteus.json');
    if (!existsSync(path)) continue;
    const manifest = JSON.parse(readFileSync(path, 'utf8'));
    const [commit, updated] = execFileSync('git', ['log', '-1', '--format=%H%n%cI', '--', join(root, id)], {
      encoding: 'utf8',
    })
      .trim()
      .split('\n');
    entries.push({ manifest, commit, updated });
  }
}

const index = buildIndex(entries);
writeFileSync('index.json', JSON.stringify(index, null, 2) + '\n');
const count = (n, word) => `${n} ${word}${n === 1 ? '' : 's'}`;
console.log(`index.json lists ${count(index.plugins.length, 'plugin')} and ${count(index.profiles.length, 'profile')}.`);
