// Type-checks each plugin with lua-language-server, the way ProteusApp/app checks its own.
//
//   node scripts/luals.mjs            checks every plugin
//   node scripts/luals.mjs shader     only the plugins whose id contains "shader"
//
// Each plugin is checked on its own, as Proteus runs it: its folder is the workspace, and the
// library is the app's types, the tests' globals in types/tests.lua, and the plugins it
// depends on, directly or not. Checked together, plugins would share one set of class names,
// and two plugins that each define `Viewer.State` would report each other's fields.
//
// The app's types are the copies in types/, which is all the check workflow has, since the
// app's repository is private. With a ProteusApp/app checkout (PROTEUS_APP, or ../app) it
// reads that checkout's lua/types and lua/lib/ modules instead, which knows the classes of
// modules such as disk_paths and lsp.client too.
//
// It reports problems of Warning level and up, LuaLS's default diagnostics. The plugins that
// were here before the check came in had some, and luals-baseline.json lists them by file, kind
// and message, with how many of each: under `types` those found with types/, and under `app`
// those found with an app checkout. The check fails on any problem beyond those, so a new
// plugin, or a change to one, brings in none. A problem that is fixed is reported, and
//
//   node scripts/luals.mjs --update   writes luals-baseline.json again from what LuaLS finds
//
// takes it off the list, for the way it ran. A pull request that adds to the list needs a
// reason a reviewer accepts.
//
// The pinned lua-language-server must be on the PATH, or named by LUALS. The check workflow
// installs it from its release, checked against its SHA-256.

import { spawn, execFileSync } from 'node:child_process';
import { existsSync, mkdtempSync, readdirSync, readFileSync, rmSync, statSync, writeFileSync } from 'node:fs';
import { availableParallelism, tmpdir } from 'node:os';
import { join, relative, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { APP } from './lua.mjs';

export const VERSION = '3.19.1';
const ROOT = resolve(import.meta.dirname, '..');
const PLUGINS = join(ROOT, 'plugins');
const BASELINE = join(ROOT, 'luals-baseline.json');
// Which part of the baseline holds: the run with the registry's types/, or with the app's.
const MODE = APP ? 'app' : 'types';

/** Where the app's types come from, and the modules a plugin may require from its lib/. */
function appLibrary() {
  if (APP) return [join(APP, 'lua', 'types'), join(APP, 'lua', 'lib'), join(ROOT, 'types', 'tests.lua')];
  return [join(ROOT, 'types')];
}

/** The lua-language-server to run, or an error that says how to get it. */
function program() {
  const name = process.env.LUALS || 'lua-language-server';
  let out = '';
  try {
    out = execFileSync(name, ['--version'], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] });
  } catch {
    throw new Error(`lua-language-server ${VERSION} is not on the PATH. Install it from https://github.com/LuaLS/lua-language-server/releases/tag/${VERSION}, or set LUALS to its program.`);
  }
  if (!out.includes(VERSION)) {
    throw new Error(`${name} is ${out.trim()}, not the pinned ${VERSION}. Another version reports other problems.`);
  }
  return name;
}

/** A plugin's proteus.json, or an empty one. */
function meta(id) {
  const path = join(PLUGINS, id, 'proteus.json');
  return existsSync(path) ? JSON.parse(readFileSync(path, 'utf8')) : {};
}

/** The registry plugins `id` depends on, directly or through others, `optional` included. */
export function dependenciesOf(id, read = meta, has = (x) => existsSync(join(PLUGINS, x, 'init.lua'))) {
  const seen = new Set([id]);
  const queue = [id];
  while (queue.length > 0) {
    const m = read(queue.shift());
    for (const dep of [...(m.depends ?? []), ...(m.optional ?? [])]) {
      if (!seen.has(dep) && has(dep)) {
        seen.add(dep);
        queue.push(dep);
      }
    }
  }
  seen.delete(id);
  return [...seen].sort();
}

/**
 * @typedef {{ file: string, line: number, column: number, key: string }} Problem
 * A problem LuaLS found. `key` is its kind and message, which the baseline counts per file.
 */

/** Runs LuaLS on one plugin and returns its problems. */
function check(luals, id, scratch) {
  const config = join(scratch, `${id}.json`);
  const out = join(scratch, `${id}.out.json`);
  writeFileSync(
    config,
    JSON.stringify({
      'runtime.version': 'Lua 5.4',
      'workspace.library': [...appLibrary(), ...dependenciesOf(id).map((d) => join(PLUGINS, d))],
      'workspace.checkThirdParty': false,
      'diagnostics.libraryFiles': 'Disable',
    }),
  );
  const dir = join(PLUGINS, id);
  return new Promise((done, fail) => {
    const child = spawn(luals, [`--check=${dir}`, '--checklevel=Warning', `--configpath=${config}`, '--check_format=json', `--check_out_path=${out}`], {
      stdio: ['ignore', 'ignore', 'inherit'],
    });
    child.on('error', fail);
    child.on('close', () => {
      // No file means no problems.
      const report = existsSync(out) ? JSON.parse(readFileSync(out, 'utf8') || '{}') : {};
      const problems = [];
      for (const [uri, list] of Object.entries(report)) {
        const file = relative(ROOT, fileURLToPath(uri)).split('\\').join('/');
        for (const d of list) {
          problems.push({ file, line: d.range.start.line + 1, column: d.range.start.character + 1, key: `${d.code}  ${d.message.split('\n')[0]}` });
        }
      }
      done(problems.sort((a, b) => a.file.localeCompare(b.file) || a.line - b.line || a.column - b.column));
    });
  });
}

/** Counts problems by file, then by key, as luals-baseline.json holds them. */
export function countOf(problems) {
  const out = {};
  for (const p of problems) {
    out[p.file] ??= {};
    out[p.file][p.key] = (out[p.file][p.key] ?? 0) + 1;
  }
  return out;
}

/**
 * Holds problems to a baseline. `added` are the problems beyond what it allows, as lines;
 * `fixed` counts what it allows that no longer happens. Only files under `scope` count, so a
 * check of some plugins says nothing about the others.
 */
export function compareToBaseline(problems, baseline, scope = () => true) {
  const seen = {};
  const added = [];
  for (const p of problems) {
    seen[p.file] ??= {};
    const n = (seen[p.file][p.key] = (seen[p.file][p.key] ?? 0) + 1);
    if (n > (baseline[p.file]?.[p.key] ?? 0)) added.push(`${p.file}:${p.line}:${p.column}  ${p.key}`);
  }
  let fixed = 0;
  for (const [file, keys] of Object.entries(baseline)) {
    if (!scope(file)) continue;
    for (const [key, n] of Object.entries(keys)) fixed += Math.max(0, n - (seen[file]?.[key] ?? 0));
  }
  return { added, fixed };
}

/** Sorts a baseline's files and keys, so it diffs cleanly. */
function sorted(baseline) {
  const out = {};
  for (const file of Object.keys(baseline).sort()) {
    out[file] = {};
    for (const key of Object.keys(baseline[file]).sort()) out[file][key] = baseline[file][key];
  }
  return out;
}

if (process.argv[1] && resolve(process.argv[1]) === resolve(import.meta.filename)) {
  const update = process.argv.includes('--update');
  const filter = process.argv.slice(2).find((a) => !a.startsWith('--')) ?? '';
  try {
    const luals = program();
    const ids = readdirSync(PLUGINS)
      .filter((id) => id.includes(filter) && statSync(join(PLUGINS, id)).isDirectory() && existsSync(join(PLUGINS, id, 'init.lua')))
      .sort();
    const scratch = mkdtempSync(join(tmpdir(), 'luals-'));
    const results = new Map();
    let next = 0;
    const worker = async () => {
      while (next < ids.length) {
        const id = ids[next++];
        results.set(id, await check(luals, id, scratch));
      }
    };
    await Promise.all(Array.from({ length: Math.max(2, availableParallelism()) }, worker));
    rmSync(scratch, { recursive: true, force: true });
    const problems = ids.flatMap((id) => results.get(id));
    const whole = existsSync(BASELINE) ? JSON.parse(readFileSync(BASELINE, 'utf8')) : {};
    const baseline = whole[MODE] ?? {};
    console.log(APP ? `Checking against the app's types and lib/ in ${APP}.` : "Checking against the app's types copied in types/.");
    const checked = new Set(ids);
    const inScope = (file) => checked.has(file.split('/')[1]);
    if (update) {
      const next = Object.fromEntries(Object.entries(baseline).filter(([file]) => !inScope(file)));
      Object.assign(next, countOf(problems));
      whole[MODE] = sorted(next);
      writeFileSync(BASELINE, JSON.stringify({ types: whole.types ?? {}, app: whole.app ?? {} }, null, 2) + '\n');
      console.log(`Wrote the ${MODE} part of luals-baseline.json with the ${problems.length} problems LuaLS found in ${ids.length} plugins.`);
    } else {
      const { added, fixed } = compareToBaseline(problems, baseline, inScope);
      if (added.length > 0) console.log(added.join('\n'));
      console.log(
        `\nLuaLS checked ${ids.length} plugins: ${problems.length} problem${problems.length === 1 ? '' : 's'}, ${added.length} not in luals-baseline.json.`,
      );
      if (fixed > 0) {
        console.log(`${fixed} problem${fixed === 1 ? ' in the baseline is' : 's in the baseline are'} fixed. Run node scripts/luals.mjs --update to take them off it.`);
      }
      if (added.length > 0) process.exitCode = 1;
    }
  } catch (err) {
    console.error(err.message);
    process.exitCode = 1;
  }
}
