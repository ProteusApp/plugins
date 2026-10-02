// Checks every plugin and profile folder against the registry's rules, the same ones a
// submission meets. The check workflow runs it on each pull request, so a folder added by
// hand is held to them too. It exits with an error when any folder breaks a rule.
//
// It also keeps taken-down ids with their owners. A folder deleted while index.json still
// lists it needs an entry in removed.json, so nobody else can publish under its id and have
// the marketplace offer their code to everyone who installed the old one.

import { existsSync, lstatSync, readFileSync, readdirSync, statSync } from 'node:fs';
import { join } from 'node:path';
import { kindOf, validate } from './registry.mjs';

const reserved = JSON.parse(readFileSync('reserved.json', 'utf8'));
const removed = existsSync('removed.json') ? JSON.parse(readFileSync('removed.json', 'utf8')) : {};
const index = existsSync('index.json') ? JSON.parse(readFileSync('index.json', 'utf8')) : {};
// A plugin may need one that ships with Proteus, or any plugin in this checkout: one listed
// already, or one that arrives in the same change.
const known = new Set([
  ...(reserved.ids ?? []),
  ...(existsSync('plugins') ? readdirSync('plugins').filter((id) => statSync(join('plugins', id)).isDirectory()) : []),
]);

/** Every file under a folder, as paths from that folder, and the links, which no plugin holds. */
function filesUnder(dir, prefix = '', links = []) {
  const out = [];
  for (const name of readdirSync(dir)) {
    const full = join(dir, name);
    const rel = prefix ? `${prefix}/${name}` : name;
    const stat = lstatSync(full);
    if (stat.isSymbolicLink()) links.push(rel);
    else if (stat.isDirectory()) out.push(...filesUnder(full, rel, links));
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
      const links = [];
      for (const rel of filesUnder(dir, '', links)) {
        // The bytes, so a file that is not UTF-8 text is caught rather than read as mojibake.
        if (rel !== 'proteus.json') files[rel] = readFileSync(join(dir, rel));
      }
      const listed = [...(meta.files ?? [])].sort().join('\n');
      if (listed !== Object.keys(files).sort().join('\n')) {
        problems.push('The files in proteus.json do not match the files in the folder.');
      }
      for (const rel of links) problems.push(`${rel} is a link. A plugin holds plain files only.`);
      const gone = Object.hasOwn(removed[root] ?? {}, id) ? removed[root][id] : null;
      problems.push(
        ...validate({ ...meta, format: 1, files }, { reserved, known, official: reserved.official ?? [], removed: gone, author: meta.author ?? null }),
      );
    }
    if (problems.length > 0) {
      failed++;
      console.log(`${root}/${id}:`);
      for (const p of problems) console.log(`  - ${p}`);
    }
  }
}
// What index.json lists but the checkout no longer holds was taken down, so its id keeps its
// owner in removed.json.
for (const [root, kind] of [
  ['plugins', 'plugin'],
  ['profiles', 'profile'],
]) {
  for (const entry of Array.isArray(index[root]) ? index[root] : []) {
    if (typeof entry?.id !== 'string' || existsSync(join(root, entry.id, 'proteus.json'))) continue;
    const gone = Object.hasOwn(removed[root] ?? {}, entry.id) ? removed[root][entry.id] : null;
    if (!gone || typeof gone.login !== 'string' || typeof gone.id !== 'number') {
      failed++;
      console.log(`${root}/${entry.id}:`);
      console.log(
        `  - The ${kind} is gone, but index.json lists it. Add "${entry.id}": { "login": "${entry.author}", "id": <their GitHub user id> } to ${root} in removed.json, so nobody else takes its id.`,
      );
    } else if (gone.login.toLowerCase() !== String(entry.author).toLowerCase()) {
      failed++;
      console.log(`${root}/${entry.id}:`);
      console.log(`  - removed.json gives it to @${gone.login}, but index.json lists it by @${entry.author}.`);
    }
  }
}

if (failed > 0) {
  console.log(`${failed} folder${failed === 1 ? '' : 's'} broke the rules.`);
  process.exitCode = 1;
} else {
  console.log('Every plugin and profile meets the rules.');
}
