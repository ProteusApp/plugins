import { test } from 'node:test';
import assert from 'node:assert/strict';
import { compareToBaseline, countOf, dependenciesOf } from '../scripts/luals.mjs';

test('a plugin is type-checked with every registry plugin it needs', () => {
  const metas = {
    'shader.canvas': { depends: ['shader.core', 'proteus.lib.ui'], optional: ['shader.docs'] },
    'shader.docs': { depends: ['shader.core'] },
    'shader.core': {},
  };
  const has = (id) => id in metas;
  const read = (id) => metas[id] ?? {};
  assert.deepEqual(dependenciesOf('shader.canvas', read, has), ['shader.core', 'shader.docs']);
  assert.deepEqual(dependenciesOf('shader.core', read, has), []);
});

test('only problems beyond the baseline fail the LuaLS check', () => {
  const p = (file, key, line = 1) => ({ file, line, column: 1, key });
  const baseline = countOf([p('plugins/a/init.lua', 'undefined-field  x'), p('plugins/a/init.lua', 'undefined-field  x')]);
  assert.deepEqual(baseline, { 'plugins/a/init.lua': { 'undefined-field  x': 2 } });

  const same = compareToBaseline([p('plugins/a/init.lua', 'undefined-field  x', 7), p('plugins/a/init.lua', 'undefined-field  x', 9)], baseline);
  assert.deepEqual(same, { added: [], fixed: 0 }, 'lines may move');

  const more = compareToBaseline(
    [
      p('plugins/a/init.lua', 'undefined-field  x'),
      p('plugins/a/init.lua', 'undefined-field  x'),
      p('plugins/a/init.lua', 'undefined-field  x', 30),
      p('plugins/b/init.lua', 'need-check-nil  y', 4),
    ],
    baseline,
  );
  assert.deepEqual(more.added, ['plugins/a/init.lua:30:1  undefined-field  x', 'plugins/b/init.lua:4:1  need-check-nil  y']);

  assert.deepEqual(compareToBaseline([], baseline), { added: [], fixed: 2 });
  assert.deepEqual(compareToBaseline([], baseline, (file) => !file.startsWith('plugins/a/')), { added: [], fixed: 0 });
});
