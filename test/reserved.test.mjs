// reserved.json against the app that is checked out beside the registry. The app's repository
// is private, so the check workflow has no copy, and these tests skip there.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readdirSync, readFileSync, statSync } from 'node:fs';
import { join } from 'node:path';
import { APP, NO_APP } from '../scripts/lua.mjs';

const reserved = JSON.parse(readFileSync(new URL('../reserved.json', import.meta.url), 'utf8'));

/** True when reserved.json keeps a plugin id from submissions. */
const isReserved = (id) => reserved.ids.includes(id) || reserved.prefixes.some((p) => id.startsWith(p));

/** The old ids the kernel still reads, from its RENAMED table. */
export function renamedOf(kernel) {
  const block = kernel.match(/local RENAMED = \{[^\n]*\n([\s\S]*?)\n\}/);
  if (!block) throw new Error('src/kernel.lua has no RENAMED table');
  const out = {};
  for (const [, from, to] of block[1].matchAll(/\['([^']+)'\]\s*=\s*'([^']+)'/g)) out[from] = to;
  return out;
}

/** The plugin ids the app ships: each lua/plugins/<group>/<id>/init.lua. */
function appPlugins() {
  const root = join(APP, 'lua', 'plugins');
  const ids = [];
  for (const group of readdirSync(root)) {
    if (!statSync(join(root, group)).isDirectory()) continue;
    for (const id of readdirSync(join(root, group))) {
      if (existsSync(join(root, group, id, 'init.lua'))) ids.push(id);
    }
  }
  return ids.sort();
}

test('reserved.json keeps every plugin id the app ships', { skip: NO_APP ?? false }, () => {
  const ids = appPlugins();
  assert.ok(ids.length > 0);
  assert.deepEqual(ids.filter((id) => !isReserved(id)), []);
});

test('reserved.json keeps every old id the app still reads', { skip: NO_APP ?? false }, () => {
  const renamed = renamedOf(readFileSync(join(APP, 'src', 'kernel.lua'), 'utf8'));
  assert.ok(Object.keys(renamed).length > 0);
  assert.deepEqual(Object.keys(renamed).filter((id) => !isReserved(id)), []);
});

test('reserved.json keeps every profile the app ships', { skip: NO_APP ?? false }, () => {
  const profiles = readdirSync(join(APP, 'lua', 'profiles'))
    .filter((f) => f.endsWith('.lua'))
    .map((f) => f.slice(0, -4));
  assert.ok(profiles.includes('editor'));
  assert.deepEqual(profiles.filter((id) => !reserved.profiles.includes(id)), []);
});

test("the app's old ids come from its kernel's RENAMED table", () => {
  const kernel = [
    'local X = 1',
    'local RENAMED = { ---@type table<string, string>',
    "  ['app.notes'] = 'proteus.notes',",
    "  ['ws.explorer'] = 'proteus.editor.plugins',",
    '}',
    "local OTHER = { ['not.this'] = 'one' }",
  ].join('\n');
  assert.deepEqual(renamedOf(kernel), { 'app.notes': 'proteus.notes', 'ws.explorer': 'proteus.editor.plugins' });
  assert.throws(() => renamedOf('local nothing = {}'), /no RENAMED/);
});
