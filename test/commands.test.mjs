import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync, readdirSync, statSync } from 'node:fs';
import { join } from 'node:path';

// Proteus lets a plugin it does not trust run only its own commands and the ones marked
// `shared = true` (core.commands in the app). Every plugin here is such a plugin, so a button
// that runs another plugin's command does nothing unless that command is shared.

const ROOT = new URL('../plugins/', import.meta.url);

/** Every .lua file under a folder, as paths from the registry's plugins folder. */
function luaFiles(dir) {
  const out = [];
  for (const name of readdirSync(new URL(dir, ROOT))) {
    const rel = `${dir}${name}`;
    if (statSync(new URL(rel, ROOT)).isDirectory()) {
      if (name !== 'tests') out.push(...luaFiles(`${rel}/`));
    } else if (name.endsWith('.lua')) out.push(rel);
  }
  return out;
}

/**
 * The commands a plugin registers with a literal id, and whether each is shared. StyLua closes
 * a `commands.register ({` call with `})` at the indent it opened at, which ends the spec.
 */
function registered(source) {
  const out = new Map();
  const lines = source.split('\n');
  lines.forEach((line, i) => {
    const open = line.match(/^(\s*).*\.register \(\{$/);
    if (!open) return;
    const close = new RegExp(`^${open[1]}\\}\\)`);
    let end = i + 1;
    while (end < lines.length && !close.test(lines[end])) end++;
    const spec = lines.slice(i + 1, end);
    const id = spec.map((l) => l.match(/^\s*id = '([^']+)',$/)).find(Boolean);
    if (id) out.set(id[1], spec.some((l) => /^\s*shared = true,$/.test(l)));
  });
  return out;
}

/** The commands a plugin runs by a literal id. */
function runs(source) {
  return [...source.matchAll(/commands\.run \('([^']+)'/g)].map((m) => m[1]);
}

const plugins = readdirSync(ROOT).filter((id) => existsSync(new URL(`${id}/init.lua`, ROOT)));
const sources = Object.fromEntries(
  plugins.map((id) => [id, luaFiles(`${id}/`).map((f) => readFileSync(new URL(f, ROOT), 'utf8')).join('\n')]),
);

test('the reader finds ids and the shared flag', () => {
  const src = [
    '    commands.register ({',
    "      id = 'a.one',",
    '      shared = true,',
    '      run = function ()',
    '      end,',
    '    })',
    "    app.use ('commands').register ({",
    "      id = 'a.two',",
    '      run = run,',
    '    })',
  ].join('\n');
  assert.deepEqual([...registered(src)], [
    ['a.one', true],
    ['a.two', false],
  ]);
  assert.deepEqual(runs("commands.run ('a.one')\ncommands.run (name)"), ['a.one']);
});

test("a plugin runs another plugin's command only when it is shared", () => {
  const owner = new Map();
  for (const id of plugins) {
    for (const [cmd, shared] of registered(sources[id])) owner.set(cmd, { id, shared });
  }
  const problems = [];
  for (const id of plugins) {
    for (const cmd of new Set(runs(sources[id]))) {
      const o = owner.get(cmd);
      if (o && o.id !== id && !o.shared) problems.push(`${id} runs ${cmd}, which ${o.id} does not share`);
    }
  }
  assert.deepEqual(problems, []);
});
