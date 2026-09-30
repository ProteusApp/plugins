// Checks every plugin and profile folder against the registry's rules, the same ones a
// submission meets. The check workflow runs it on each pull request, so a folder added by
// hand is held to them too. It exits with an error when any folder breaks a rule.

import { existsSync, readFileSync, readdirSync, statSync } from 'node:fs';
import { join } from 'node:path';
import { kindOf, validate } from './registry.mjs';

const reserved = JSON.parse(readFileSync('reserved.json', 'utf8'));

/** Every file under a folder, as paths from that folder. */
function filesUnder(dir, prefix = '') {
  const out = [];
  for (const name of readdirSync(dir)) {
    const full = join(dir, name);
    const rel = prefix ? `${prefix}/${name}` : name;
    if (statSync(full).isDirectory()) out.push(...filesUnder(full, rel));
    else out.push(rel);
  }
  return out;
}

let failed = 0;
for (const [root, kind] of [
  ['plugins', 'plugin'],
  ['profiles', 'profile'],
]) {
  for (const id of existsSync(root) ? readdirSync(root) : []) {
    const dir = join(root, id);
    if (!statSync(dir).isDirectory()) continue;
    const problems = [];
    const metaPath = join(dir, 'proteus.json');
    if (!existsSync(metaPath)) {
      problems.push('proteus.json is missing.');
    } else {
      const meta = JSON.parse(readFileSync(metaPath, 'utf8'));
      if (meta.id !== id) problems.push(`proteus.json names the id ${meta.id}, but the folder is ${id}.`);
      if (kindOf(meta) !== kind) problems.push(`proteus.json holds a ${kindOf(meta)}, but the folder is in ${root}/.`);
      const files = {};
      for (const rel of filesUnder(dir)) {
        if (rel !== 'proteus.json') files[rel] = readFileSync(join(dir, rel), 'utf8');
      }
      const listed = [...(meta.files ?? [])].sort().join('\n');
      if (listed !== Object.keys(files).sort().join('\n')) {
        problems.push('The files in proteus.json do not match the files in the folder.');
      }
      problems.push(...validate({ ...meta, format: 1, files }, { reserved }));
    }
    if (problems.length > 0) {
      failed++;
      console.log(`${root}/${id}:`);
      for (const p of problems) console.log(`  - ${p}`);
    }
  }
}
if (failed > 0) {
  console.log(`${failed} folder${failed === 1 ? '' : 's'} broke the rules.`);
  process.exitCode = 1;
} else {
  console.log('Every plugin and profile meets the rules.');
}
