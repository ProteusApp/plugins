// Writes the proteus.json of a plugin or profile folder added by hand, from what its init.lua
// or profile.lua declares, the way the submission workflow writes it for a published one.
//
//   node scripts/manifest.mjs plugins/my.plugin --author login:id [--issue 12]
//
// The author is the GitHub account that owns the plugin, and only it can update it later.

import { readdirSync, statSync, writeFileSync } from 'node:fs';
import { basename, join } from 'node:path';
import { declaredOf } from './lua.mjs';
import { manifestFor } from './registry.mjs';

const [dir, ...rest] = process.argv.slice(2);
const flag = (name) => {
  const i = rest.indexOf(name);
  return i >= 0 ? rest[i + 1] : undefined;
};
const [login, id] = String(flag('--author') ?? '').split(':');
if (!dir || !login || !id) {
  console.error('Usage: node scripts/manifest.mjs <plugins/id|profiles/id> --author login:id [--issue n]');
  process.exit(1);
}

/** Every file under a folder, as paths from that folder. */
function filesUnder(root, prefix = '') {
  const out = [];
  for (const name of readdirSync(root)) {
    const full = join(root, name);
    const rel = prefix ? `${prefix}/${name}` : name;
    if (statSync(full).isDirectory()) out.push(...filesUnder(full, rel));
    else if (rel !== 'proteus.json') out.push(rel);
  }
  return out;
}

const kind = dir.replace(/\\/g, '/').startsWith('profiles/') ? 'profile' : 'plugin';
const declared = await declaredOf(dir, kind === 'profile' ? 'profile.lua' : 'init.lua');
if (declared.error) {
  console.error(declared.error);
  process.exit(1);
}
const files = Object.fromEntries(filesUnder(dir).map((f) => [f, '']));
const sub = { ...declared, id: basename(dir), kind: kind === 'profile' ? 'profile' : undefined, files };
const issue = flag('--issue') ? Number(flag('--issue')) : null;
const manifest = manifestFor(sub, { login, id: Number(id) }, issue);
writeFileSync(join(dir, 'proteus.json'), JSON.stringify(manifest, null, 2) + '\n');
console.log(`wrote ${join(dir, 'proteus.json')}`);
