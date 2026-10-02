// Writes index.json, the list of approved plugins and profiles the Proteus marketplace reads.
// The index workflow runs it after every merge to main. Each entry names the last commit that
// changed its folder, so the app installs exactly what was approved. It also keeps the past
// versions of each folder's history, each at the last commit that had it, so the app can
// install an older version exactly as it was approved, and the number of the issue that first
// submitted it, whose reactions the marketplace shows.
//
//   node scripts/index.mjs           writes index.json from the folders and their history
//   node scripts/index.mjs --verify  checks the index.json there is against the history
//
// The app trusts each entry's commit, files and permissions, past versions included, so the
// check workflow runs --verify on every pull request: an entry may lag behind its folder until
// the index workflow runs, but it must name a commit of main that changed the folder, and say
// only what the folder's proteus.json said at that commit.

import { execFileSync } from 'node:child_process';
import { existsSync, readFileSync, readdirSync, writeFileSync } from 'node:fs';
import { buildIndex, folderFor, historyOf, indexProblems, MAX_VERSIONS } from './registry.mjs';

/** Runs git and returns its output, or null when it fails. */
function git(...args) {
  try {
    return execFileSync('git', args, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'], maxBuffer: 64 * 1024 * 1024 });
  } catch {
    return null;
  }
}

/** A folder's proteus.json at a commit, or null. */
function manifestAt(commit, folder) {
  const text = git('show', `${commit}:${folder}/proteus.json`);
  try {
    return text === null ? null : JSON.parse(text);
  } catch {
    return null;
  }
}

/** The paths in a folder at a commit, apart from proteus.json. */
function filesAt(commit, folder) {
  return (git('ls-tree', '-r', '--name-only', commit, '--', `${folder}/`) ?? '')
    .split('\n')
    .filter(Boolean)
    .map((path) => path.slice(folder.length + 1))
    .filter((path) => path !== 'proteus.json');
}

/**
 * The commits that changed a folder, newest first, from `from` back, each with its date, its
 * proteus.json and its files: what historyOf reads. It stops after the first commit where the
 * folder had no proteus.json, since historyOf stops there too.
 */
function folderLog(kind, id, from) {
  const folder = folderFor(kind, id);
  const lines = (git('log', '--format=%H %cI', from, '--', folder) ?? '').split('\n').filter(Boolean);
  const log = [];
  for (const line of lines) {
    const [commit, updated] = line.split(' ');
    const manifest = manifestAt(commit, folder);
    log.push({ commit, updated, manifest, files: manifest ? filesAt(commit, folder) : [] });
    if (!manifest) break;
  }
  return log;
}

if (process.argv.includes('--verify')) {
  const index = JSON.parse(readFileSync('index.json', 'utf8'));
  const problems = indexProblems(index, (kind, id, commit) => {
    if (git('cat-file', '-e', `${commit}^{commit}`) === null) return null;
    if (git('merge-base', '--is-ancestor', commit, 'HEAD') === null) return null;
    const folder = folderFor(kind, id);
    const history = folderLog(kind, id, commit);
    const top = history[0];
    if (!top) return { manifest: null, files: [], last: null, updated: null, history };
    return { manifest: top.commit === commit ? top.manifest : manifestAt(commit, folder), files: filesAt(commit, folder), last: top.commit, updated: top.updated, history };
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
  for (const [root, kind] of [
    ['plugins', 'plugin'],
    ['profiles', 'profile'],
  ]) {
    for (const id of existsSync(root) ? readdirSync(root) : []) {
      if (!existsSync(`${root}/${id}/proteus.json`)) continue;
      const log = folderLog(kind, id, 'HEAD');
      if (!log[0]?.manifest) continue;
      const { versions, issue } = historyOf(log);
      entries.push({ manifest: log[0].manifest, commit: log[0].commit, updated: log[0].updated, versions: versions.slice(0, MAX_VERSIONS), issue });
    }
  }

  const index = buildIndex(entries);
  writeFileSync('index.json', JSON.stringify(index, null, 2) + '\n');
  const count = (n, word) => `${n} ${word}${n === 1 ? '' : 's'}`;
  const past = [...index.plugins, ...index.profiles].reduce((n, e) => n + (e.versions?.length ?? 0), 0);
  console.log(`index.json lists ${count(index.plugins.length, 'plugin')} and ${count(index.profiles.length, 'profile')}, with ${count(past, 'past version')}.`);
}
