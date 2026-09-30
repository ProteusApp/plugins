import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  LABEL,
  buildIndex,
  collectParts,
  compareVersions,
  decodePayload,
  isSubmission,
  manifestFor,
  pathProblem,
  pullRequestBody,
  validate,
} from '../scripts/registry.mjs';

// The Proteus app's own tests encode the same text and expect this same base64.
const SHARED_TEXT = '{"format":1,"id":"hello.world","note":"café ✓"}';
const SHARED_BASE64 = 'eyJmb3JtYXQiOjEsImlkIjoiaGVsbG8ud29ybGQiLCJub3RlIjoiY2Fmw6kg4pyTIn0=';

/** A part as the app writes it. */
const part = (k, n, text) => `<!-- proteus-submission part ${k} of ${n} -->\n\`\`\`text\n${text}\n\`\`\``;

/** A submission that meets every rule. */
function good(extra = {}) {
  return {
    format: 1,
    id: 'hello.world',
    name: 'Hello World',
    description: 'Says hello in the status bar.',
    version: '1.0.0',
    depends: ['ui.statusbar'],
    files: { 'init.lua': 'return {}', 'lib/util.lua': 'return 1', 'README.md': '# Hello' },
    ...extra,
  };
}

const reserved = { ids: ['core.keys', 'app.git'], prefixes: ['core.', 'ui.'] };

test('the shared text decodes the way the app encodes it', () => {
  assert.equal(Buffer.from(SHARED_TEXT, 'utf8').toString('base64'), SHARED_BASE64);
  assert.equal(decodePayload(SHARED_BASE64).note, 'café ✓');
});

test('a submission is known by its label, its title or its first part', () => {
  assert.ok(isSubmission({ labels: [{ name: LABEL }] }));
  assert.ok(isSubmission({ title: 'Plugin submission: hello.world 1.0.0' }));
  assert.ok(isSubmission({ title: 'x', body: part(1, 2, 'YWJj') }));
  assert.ok(!isSubmission({ title: 'Bug: it crashes', body: 'help' }));
});

test('collectParts joins the parts in order, from any text', () => {
  const got = collectParts(['intro\n' + part(1, 3, 'YW'), part(3, 3, 'Jj'), 'noise', part(2, 3, 'Jj\nYW')]);
  assert.deepEqual(got, { total: 3, have: 3, complete: true, data: 'YWJjYWJj' });
});

test('collectParts waits for a missing part', () => {
  const got = collectParts([part(1, 2, 'YWJj')]);
  assert.equal(got.complete, false);
  assert.equal(got.have, 1);
  assert.equal(got.data, '');
});

test('collectParts keeps the last copy of a part', () => {
  const got = collectParts([part(1, 1, 'b2xk'), part(1, 1, 'bmV3')]);
  assert.equal(got.data, 'bmV3');
});

test('decodePayload refuses text that is not a submission', () => {
  assert.throws(() => decodePayload('bm90IGpzb24='), /could not be read/);
  assert.throws(() => decodePayload(Buffer.from('{"format":9}').toString('base64')), /format/);
});

test('a good submission has no problems', () => {
  assert.deepEqual(validate(good(), { reserved }), []);
});

test('validate names every rule a submission breaks', () => {
  const problems = validate(
    good({ id: 'Bad Id', name: '', description: '', version: 'one', files: { 'a.lua': 'x' } }),
    { reserved },
  );
  assert.equal(problems.length, 5);
  assert.match(problems.join('\n'), /lower case/);
  assert.match(problems.join('\n'), /init\.lua/);
});

test('validate keeps builtin ids for Proteus', () => {
  assert.match(validate(good({ id: 'app.git' }), { reserved }).join(), /ships with Proteus/);
  assert.match(validate(good({ id: 'core.mine' }), { reserved }).join(), /ships with Proteus/);
});

test('validate lets only the author update a plugin, and only upward', () => {
  const existing = { id: 'hello.world', version: '1.0.0', author: { login: 'ann', id: 1 } };
  assert.match(validate(good(), { existing, author: { login: 'bob', id: 2 }, reserved }).join(), /belongs to @ann/);
  assert.match(validate(good(), { existing, author: { login: 'ann', id: 1 }, reserved }).join(), /Raise the version/);
  assert.deepEqual(validate(good({ version: '1.0.1' }), { existing, author: { login: 'ann', id: 1 }, reserved }), []);
});

test('pathProblem allows plain text files only', () => {
  assert.equal(pathProblem('init.lua'), null);
  assert.equal(pathProblem('assets/logo.svg'), null);
  assert.match(pathProblem('../evil.lua'), /plain file path/);
  assert.match(pathProblem('/abs.lua'), /plain file path/);
  assert.match(pathProblem('bin/tool.exe'), /kind of file/);
  assert.match(pathProblem('a/b/c/d/e.lua'), /too deep/);
  assert.match(pathProblem('proteus.json'), /written by the registry/);
});

test('compareVersions compares each part as a number', () => {
  assert.equal(compareVersions('1.10.0', '1.9.9'), 1);
  assert.equal(compareVersions('1.0.0', '1.0.0'), 0);
  assert.equal(compareVersions('0.9.0', '1.0.0'), -1);
});

test('manifestFor records the author and the sorted files', () => {
  const m = manifestFor(good(), { login: 'ann', id: 1, type: 'User' }, 7);
  assert.deepEqual(m.author, { login: 'ann', id: 1 });
  assert.deepEqual(m.files, ['README.md', 'init.lua', 'lib/util.lua']);
  assert.equal(m.issue, 7);
});

test('buildIndex lists plugins by name with their approved commit', () => {
  const a = manifestFor(good({ id: 'b.plugin', name: 'Zebra' }), { login: 'ann', id: 1 }, 1);
  const b = manifestFor(good({ id: 'a.plugin', name: 'apple' }), { login: 'bob', id: 2 }, 2);
  const index = buildIndex([
    { manifest: a, commit: 'aaa', updated: '2026-01-01' },
    { manifest: b, commit: 'bbb', updated: '2026-01-02' },
  ]);
  assert.equal(index.format, 1);
  assert.deepEqual(index.plugins.map((p) => [p.id, p.author, p.commit]), [
    ['a.plugin', 'bob', 'bbb'],
    ['b.plugin', 'ann', 'aaa'],
  ]);
});

test('the pull request names the plugin, its files and the review', () => {
  const sub = good();
  const body = pullRequestBody(manifestFor(sub, { login: 'ann', id: 1 }, 7), sub, 7, false);
  assert.match(body, /^Adds \*\*Hello World\*\*/);
  assert.match(body, /plugins\/hello\.world\/init\.lua/);
  assert.match(body, /Closes #7\./);
});
