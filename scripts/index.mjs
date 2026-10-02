// Writes index.json, the list of approved plugins and profiles the Proteus marketplace reads.
// The index workflow runs it after every merge to main. Each entry names the last commit that
// changed its folder, so the app installs exactly what was approved.
//
//   node scripts/index.mjs           writes index.json from the folders and their history
//   node scripts/index.mjs --verify  checks the index.json there is against the history
//
// The app trusts each entry's commit, files and permissions, so the check workflow runs
// --verify on every pull request: an entry may lag behind its folder until the index
// workflow runs, but it must name a commit of main that changed the folder, and say only
// what the folder's proteus.json said at that commit.

import { execFileSync } from 'node:child_process';
import { existsSync, readFileSync, readdirSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { buildIndex, folderFor, indexProblems } from './registry.mjs';

/** Runs git and returns its output, or null when it fails. */
function git(...args) {
  try {
    return execFileSync('git', args, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] });
  } catch {
    return null;
  }
}

if (process.argv.includes('--verify')) {
  const index = JSON.parse(readFileSync('index.json', 'utf8'));
  const problems = indexProblems(index, (kind, id, commit) => {
    if (git('cat-file', '-e', `${commit}^{commit}`) === null) return null;
    if (git('merge-base', '--is-ancestor', commit, 'HEAD') === null) return null;
    const folder = folderFor(kind, id);
    const [last, updated] = (git('log', '-1', '--format=%H%n%cI', commit, '--', folder) ?? '').trim().split('\n');
    const text = git('show', `${commit}:${folder}/proteus.json`);
    let manifest = null;
    try {
      manifest = text === null ? null : JSON.parse(text);
    } catch {
      manifest = null;
    }
    const files = (git('ls-tree', '-r', '--name-only', commit, '--', `${folder}/`) ?? '')
      .split('\n')
      .filter(Boolean)
      .map((path) => path.slice(folder.length + 1))
      .filter((path) => path !== 'proteus.json');
    return { manifest, files, last, updated };
  });
  if (problems.length > 0) {
    for (const p of problems) console.log(`- ${p}`);
    console.log('index.json does not match the history of main. The index workflow writes it, so leave it out of pull requests.');
    process.exitCode = 1;
  } else {
    console.log('Every entry in index.json names an approved commit and what it held.');
  }
} else {
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
}
