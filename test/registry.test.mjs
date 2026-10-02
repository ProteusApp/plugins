import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import {
  LABEL,
  approvedCommit,
  branchFor,
  buildIndex,
  canApprove,
  collectSubmission,
  commandOf,
  compareVersions,
  folderFor,
  historyOf,
  indexProblems,
  MAX_VERSIONS,
  isSubmission,
  kindOf,
  manifestFor,
  pathProblem,
  textProblem,
  vendorOf,
  sha256,
  pullRequestBody,
  RESERVED_FOLDERS,
  validate,
} from '../scripts/registry.mjs';

// The Proteus app writes this exact issue for its sample plugin, and its own tests check that
// it still does. See tests/lua/interface/store_issue.md in the Proteus repository.
const SAMPLE = readFileSync(new URL('./fixtures/store-issue.md', import.meta.url), 'utf8').replace(/\r\n/g, '\n');

const FENCE = '```';

/** A file block the way the app writes one. */
const block = (path, k, n, text, fence = FENCE) =>
  `<!-- proteus-file path="${path}" part="${k}" of="${n}" -->\n${fence}lua\n${text}\n${fence}`;

/** A manifest block the way the app writes one. */
const manifestBlock = (files) =>
  `<!-- proteus-manifest -->\n${FENCE}json\n${JSON.stringify({ format: 2, id: 'a.b', name: 'A', description: 'B.', version: '1.0.0', files })}\n${FENCE}`;

/** A submission that meets every rule. */
function good(extra = {}) {
  return {
    format: 2,
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

test('the sample issue from the app reads back to its files', () => {
  const got = collectSubmission([SAMPLE]);
  assert.equal(got.complete, true);
  assert.equal(got.sub.id, 'hello.world');
  assert.equal(got.sub.version, '1.0.0');
  assert.deepEqual(got.sub.files, {
    'init.lua': "return {\n  name = 'Hello',\n  description = 'Says \u201Chello\u201D.',\n}\n",
    'README.md': "# Hello\n\n```lua\nprint('hi')\n```\n",
    'lib/util.lua': 'return 1',
  });
  assert.deepEqual(validate(got.sub, { reserved }), []);
});

test('the sample issue reads the same after GitHub turns its line endings into CRLF', () => {
  const got = collectSubmission([SAMPLE.replace(/\n/g, '\r\n')]);
  assert.equal(got.sub.files['lib/util.lua'], 'return 1');
  assert.equal(got.sub.files['init.lua'].includes('\r'), false);
});

test('a submission is known by its label, its title or its manifest', () => {
  assert.ok(isSubmission({ labels: [{ name: LABEL }] }));
  assert.ok(isSubmission({ title: 'Plugin submission: hello.world 1.0.0' }));
  assert.ok(isSubmission({ title: 'x', body: SAMPLE }));
  assert.ok(!isSubmission({ title: 'Bug: it crashes', body: 'help' }));
});

test('parts of a file join in order across the issue and its comments', () => {
  const texts = [
    manifestBlock(['init.lua']) + '\n\n' + block('init.lua', 1, 3, 'one\n'),
    block('init.lua', 3, 3, 'three'),
    'a comment in between',
    block('init.lua', 2, 3, 'two\n'),
  ];
  const got = collectSubmission(texts);
  assert.equal(got.complete, true);
  assert.equal(got.sub.files['init.lua'], 'one\ntwo\nthree');
});

test('a submission waits for a missing file or part', () => {
  const texts = [manifestBlock(['init.lua', 'b.lua']) + '\n' + block('init.lua', 1, 2, 'x')];
  const got = collectSubmission(texts);
  assert.equal(got.complete, false);
  assert.deepEqual(got.missing, ['init.lua', 'b.lua']);
  assert.equal(collectSubmission(['no manifest here']).complete, false);
});

test('a longer fence keeps backticks inside a file', () => {
  const inner = 'a\n```\nb';
  const got = collectSubmission([manifestBlock(['init.lua']) + '\n' + block('init.lua', 1, 1, inner, '````')]);
  assert.equal(got.sub.files['init.lua'], inner);
});

test('an edited part replaces the old one', () => {
  const got = collectSubmission([
    manifestBlock(['init.lua']) + '\n' + block('init.lua', 1, 1, 'old'),
    block('init.lua', 1, 1, 'new'),
  ]);
  assert.equal(got.sub.files['init.lua'], 'new');
});

test('an unreadable manifest or an unknown format is reported', () => {
  assert.match(collectSubmission([`<!-- proteus-manifest -->\n${FENCE}json\n{nope\n${FENCE}`]).error, /manifest/);
  const old = `<!-- proteus-manifest -->\n${FENCE}json\n{"format":1}\n${FENCE}`;
  assert.match(collectSubmission([old]).error, /format/);
});

test('commandOf reads the command on a comment\'s first line', () => {
  assert.equal(commandOf('/approve'), 'approve');
  assert.equal(commandOf('  /Approve looks good\nthanks'), 'approve');
  assert.equal(commandOf('I would /approve this'), null);
  assert.equal(commandOf('/approved'), 'approved');
  assert.equal(commandOf(''), null);
});

test('canApprove takes write access and above', () => {
  assert.ok(canApprove('admin'));
  assert.ok(canApprove('maintain'));
  assert.ok(canApprove('write'));
  assert.ok(!canApprove('triage'));
  assert.ok(!canApprove('read'));
  assert.equal(branchFor(12), 'submission/12');
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

test('validate takes an official id only when the check names it', () => {
  const withOfficial = { ...reserved, prefixes: [...reserved.prefixes, 'proteus.'] };
  assert.match(validate(good({ id: 'proteus.git' }), { reserved: withOfficial }).join(), /ships with Proteus/);
  assert.deepEqual(validate(good({ id: 'proteus.git' }), { reserved: withOfficial, official: ['proteus.git'] }), []);
  assert.match(
    validate(good({ id: 'proteus.other' }), { reserved: withOfficial, official: ['proteus.git'] }).join(),
    /ships with Proteus/,
  );
});

test('validate lets only the author update a plugin, and only upward', () => {
  const existing = { id: 'hello.world', version: '1.0.0', author: { login: 'ann', id: 1 } };
  assert.match(validate(good(), { existing, author: { login: 'bob', id: 2 }, reserved }).join(), /belongs to @ann/);
  assert.match(validate(good(), { existing, author: { login: 'ann', id: 1 }, reserved }).join(), /Raise the version/);
  assert.deepEqual(validate(good({ version: '1.0.1' }), { existing, author: { login: 'ann', id: 1 }, reserved }), []);
});

test('pathProblem allows plain file paths only', () => {
  assert.equal(pathProblem('init.lua'), null);
  assert.equal(pathProblem('assets/logo.svg'), null);
  assert.equal(pathProblem('page/preview.js'), null);
  assert.match(pathProblem('../evil.lua'), /plain file path/);
  assert.match(pathProblem('/abs.lua'), /plain file path/);
  assert.match(pathProblem('bin/-tool'), /plain file path/);
  assert.match(pathProblem('a/b/c/d/e.lua'), /too deep/);
  assert.match(pathProblem('proteus.json'), /written by the registry/);
});

test('textProblem takes readable text only', () => {
  assert.equal(textProblem('a.lua', 'local x = 1\r\n\tprint(x)\n'), null);
  assert.equal(textProblem('a.wgsl', 'fn main() {} // é ✓'), null);
  assert.equal(textProblem('a.md', Buffer.from('\ufeff# Title\n')), null);
  assert.match(textProblem('a.bin', Buffer.from([0x4d, 0x5a, 0x00, 0x01])), /control characters/);
  assert.match(textProblem('a.lua', Buffer.from([0xff, 0xfe])), /not UTF-8/);
  assert.match(textProblem('a.lua', 'x = 1 \u001b[2J'), /control characters/);
  assert.match(textProblem('a.lua', 'if admin \u202e then'), /reorder/);
  assert.match(textProblem('a.lua', 'x \u2067 y'), /reorder/);
  assert.match(textProblem('a.js', 'x'.repeat(1001)), /longer than 1000/);
  assert.equal(textProblem('a.md', 'é'.repeat(1000)), null);
});

test('validate checks permissions, folders and requires', () => {
  const problems = validate(
    good({ permissions: ['net', 'root'], folders: ['shaders', 'plugins', '../x'], requires: { proteus: '~>1' } }),
    { reserved },
  );
  assert.equal(problems.length, 4, problems.join('\n'));
  assert.deepEqual(
    validate(
      good({ permissions: ['net'], folders: ['shaders'], requires: { proteus: '>=0.2.0 <1', features: ['webview'] } }),
      { reserved },
    ),
    [],
  );
});

test('validate wants every dependency to ship with Proteus or be listed', () => {
  const known = new Set(['core.commands', 'lib.ui']);
  assert.deepEqual(validate(good({ depends: ['core.commands'] }), { reserved, known }), []);
  assert.match(validate(good({ depends: ['nowhere.plugin'] }), { reserved, known }).join(), /nowhere\.plugin/);
});

test('manifestFor and buildIndex carry permissions, folders and requires', () => {
  const sub = good({ permissions: ['files'], folders: ['shaders'], requires: { proteus: '>=0.2.0', features: ['webview'] } });
  const m = manifestFor(sub, { login: 'ann', id: 1 }, 7);
  assert.deepEqual(m.permissions, ['files']);
  assert.deepEqual(m.folders, ['shaders']);
  assert.deepEqual(m.requires, { proteus: '>=0.2.0', features: ['webview'] });
  const [entry] = buildIndex([{ manifest: m, commit: 'abc', updated: '' }]).plugins;
  assert.deepEqual(entry.permissions, ['files']);
  assert.deepEqual(entry.requires, { proteus: '>=0.2.0', features: ['webview'] });
  assert.match(pullRequestBody(m, sub, 7, false), /Files on this computer\*\* \(full access\)/);
});

test('what changed goes into proteus.json, the index and the pull request', () => {
  const sub = good({ version: '1.1.0', changes: '  Shows the date too.\nFixes the clock at midnight.  ' });
  assert.deepEqual(validate(sub, { reserved }), []);
  const m = manifestFor(sub, { login: 'ann', id: 1 }, 7);
  assert.equal(m.changes, 'Shows the date too.\nFixes the clock at midnight.');
  const [entry] = buildIndex([{ manifest: m, commit: 'abc', updated: '' }]).plugins;
  assert.equal(entry.changes, m.changes);
  const body = pullRequestBody(m, sub, 7, true);
  assert.match(body, /### What changed\n\n> Shows the date too\.\n> Fixes the clock at midnight\./);
  // None, or only spaces, leaves the field out.
  assert.equal('changes' in manifestFor(good({ changes: '  ' }), { login: 'ann', id: 1 }, 7), false);
  assert.equal('changes' in buildIndex([{ manifest: manifestFor(good(), { login: 'ann', id: 1 }, 7), commit: 'a', updated: '' }]).plugins[0], false);
  assert.match(validate(good({ changes: 'x'.repeat(2001) }), { reserved }).join(' '), /What changed/);
  assert.match(validate(good({ changes: 5 }), { reserved }).join(' '), /What changed/);
});

test('compareVersions compares each part as a number', () => {
  assert.equal(compareVersions('1.10.0', '1.9.9'), 1);
  assert.equal(compareVersions('1.0.0', '1.0.0'), 0);
  assert.equal(compareVersions('0.9.0', '1.0.0'), -1);
});

test('compareVersions follows semver for pre-release tags and build metadata', () => {
  assert.equal(compareVersions('1.0.0', '1.0.0-beta.1'), 1);
  assert.equal(compareVersions('1.0.0-2', '1.0.0'), -1);
  const order = ['1.0.0-alpha', '1.0.0-alpha.1', '1.0.0-alpha.beta', '1.0.0-beta', '1.0.0-beta.2', '1.0.0-beta.11', '1.0.0-rc.1', '1.0.0'];
  for (let i = 1; i < order.length; i++) assert.equal(compareVersions(order[i - 1], order[i]), -1, `${order[i - 1]} < ${order[i]}`);
  assert.equal(compareVersions('1.0.0+build.5', '1.0.0'), 0);
  const existing = { id: 'hello.world', version: '1.0.0-beta.1', author: { login: 'ann', id: 1 } };
  assert.deepEqual(validate(good(), { existing, author: { login: 'ann', id: 1 } }), []);
});

test('validate reports a manifest without a string id instead of throwing', () => {
  const sub = good({ id: undefined });
  assert.match(validate(sub, { reserved: { ids: [], prefixes: ['core.'] } })[0], /id must be lower case/);
  assert.match(validate(good({ id: 42 }), { reserved: { ids: [], prefixes: ['core.'] } })[0], /id must be lower case/);
});

test('approvedCommit reads the commit after /approve', () => {
  assert.equal(approvedCommit('/approve 1A2b3c4 thanks!'), '1a2b3c4');
  assert.equal(approvedCommit('/approve thanks!'), null);
  assert.equal(approvedCommit('/approve 12345'), null);
  assert.equal(approvedCommit('/approve\n1a2b3c4'), null);
});

test('a name or a description cannot hide the rest of the pull request', () => {
  for (const [field, value] of [
    ['description', 'Says hello. <!--'],
    ['name', 'Hello\n### Permissions'],
    ['name', 'Hello ```'],
    ['description', 'Fine -->'],
  ]) {
    assert.ok(validate(good({ [field]: value })).some((p) => p.startsWith(`The ${field} `)), `${field}: ${JSON.stringify(value)}`);
  }
  const sub = good({ name: 'Hello *World* [x](y)' });
  assert.deepEqual(validate(sub), []);
  const body = pullRequestBody(manifestFor(sub, { login: 'ann', id: 1 }, 7), sub, 7, false);
  assert.match(body, /\*\*Hello \\\*World\\\* \\\[x\\\]\(y\)\*\*/);
});

test('file paths that differ only in case are refused', () => {
  const problems = validate(good({ files: { 'init.lua': 'return {}', 'INIT.lua': 'return 1' } }));
  assert.ok(problems.some((p) => /differ only in case/.test(p)));
  assert.ok(validate(good({ files: { 'init.lua': 'return {}', 'lib/A.lua': '', 'Lib/a.lua': '' } })).some((p) => /differ only in case/.test(p)));
});

test('a taken-down id stays with its owner', () => {
  const removed = { login: 'ann', id: 1 };
  assert.deepEqual(validate(good(), { removed, author: { login: 'ann', id: 1 } }), []);
  assert.match(validate(good(), { removed, author: { login: 'eve', id: 9 } })[0], /taken down, and its id stays with @ann/);
});

test('Proteus keeps its tooling folder', () => {
  assert.ok(RESERVED_FOLDERS.includes('tooling'));
  assert.match(validate(good({ folders: ['tooling'] })).join(' '), /belongs to Proteus/);
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

test('only blocks of the manifest revision count, so a half-edited issue waits', () => {
  const manifest = `<!-- proteus-manifest -->\n${FENCE}json\n${JSON.stringify({ format: 2, revision: 'new', id: 'a.b', name: 'A', description: 'B.', version: '1.0.1', files: ['init.lua'] })}\n${FENCE}`;
  const withRev = (rev, text) => `<!-- proteus-file path="init.lua" part="1" of="1" rev="${rev}" -->\n${FENCE}lua\n${text}\n${FENCE}`;
  assert.equal(collectSubmission([manifest, withRev('old', 'stale')]).complete, false);
  const got = collectSubmission([manifest, withRev('old', 'stale'), withRev('new', 'fresh')]);
  assert.equal(got.sub.files['init.lua'], 'fresh');
});

/** A profile submission that meets every rule. */
function goodProfile(extra = {}) {
  return {
    format: 2,
    kind: 'profile',
    id: 'writer',
    name: 'Writer',
    description: 'Notes and a to-do list side by side.',
    version: '1.0.0',
    plugins: ['app.notes', 'hello.world'],
    files: { 'profile.lua': "return { name = 'Writer', plugins = { 'app.notes' } }", 'README.md': '# Writer' },
    ...extra,
  };
}

const reservedWithProfiles = { ...reserved, profiles: ['editor', 'code'] };

test('a manifest names its kind, and one without a kind holds a plugin', () => {
  assert.equal(kindOf({}), 'plugin');
  assert.equal(kindOf({ kind: 'profile' }), 'profile');
  assert.equal(folderFor('plugin', 'a.b'), 'plugins/a.b');
  assert.equal(folderFor('profile', 'a.b'), 'profiles/a.b');
  assert.ok(isSubmission({ title: 'Profile submission: writer 1.0.0' }));
});

test('a good profile submission has no problems', () => {
  assert.deepEqual(validate(goodProfile(), { reserved: reservedWithProfiles }), []);
});

test('a profile needs profile.lua and a list of plugins', () => {
  const problems = validate(goodProfile({ plugins: [], files: { 'init.lua': 'return {}' } }), { reserved: reservedWithProfiles });
  assert.match(problems.join('\n'), /profile\.lua/);
  assert.match(problems.join('\n'), /at least one plugin/);
  assert.match(validate(goodProfile({ plugins: ['Bad Id'] }), { reserved }).join(), /plugins must be a list/);
});

test('builtin profile ids are kept for Proteus, apart from plugin ids', () => {
  assert.match(validate(goodProfile({ id: 'editor' }), { reserved: reservedWithProfiles }).join(), /ships with Proteus/);
  // A profile may share an id with a plugin, and core. is a plugin prefix only.
  assert.deepEqual(validate(goodProfile({ id: 'app.git' }), { reserved: reservedWithProfiles }), []);
  assert.deepEqual(validate(good({ id: 'editor' }), { reserved: reservedWithProfiles }), []);
});

test('an unknown kind is refused', () => {
  assert.match(validate(good({ kind: 'theme' }), { reserved }).join(), /kind must be/);
});

test('a profile manifest keeps its plugins and its kind', () => {
  const m = manifestFor(goodProfile(), { login: 'ann', id: 1 }, 9);
  assert.equal(m.kind, 'profile');
  assert.deepEqual(m.plugins, ['app.notes', 'hello.world']);
  assert.equal(m.depends, undefined);
  assert.deepEqual(m.files, ['README.md', 'profile.lua']);
});

test('buildIndex lists profiles apart from plugins', () => {
  const plugin = manifestFor(good(), { login: 'ann', id: 1 }, 1);
  const profile = manifestFor(goodProfile(), { login: 'bob', id: 2 }, 2);
  const index = buildIndex([
    { manifest: plugin, commit: 'aaa', updated: '2026-01-01' },
    { manifest: profile, commit: 'bbb', updated: '2026-01-02' },
  ]);
  assert.deepEqual(index.plugins.map((p) => p.id), ['hello.world']);
  assert.deepEqual(index.profiles, [
    {
      id: 'writer',
      name: 'Writer',
      description: 'Notes and a to-do list side by side.',
      version: '1.0.0',
      author: 'bob',
      plugins: ['app.notes', 'hello.world'],
      files: ['README.md', 'profile.lua'],
      commit: 'bbb',
      updated: '2026-01-02',
    },
  ]);
});

test('the pull request of a profile names its folder and its plugins', () => {
  const sub = goodProfile();
  const body = pullRequestBody(manifestFor(sub, { login: 'ann', id: 1 }, 7), sub, 7, false);
  assert.match(body, /^Adds the profile \*\*Writer\*\*/);
  assert.match(body, /profiles\/writer\/profile\.lua/);
  assert.match(body, /`app\.notes`, `hello\.world`/);
});

test('a vendored file may have long lines, when vendor.json vouches for it', () => {
  const built = 'export const x=' + '1+'.repeat(800) + '1;\n';
  const vendor = (entry) => JSON.stringify({ files: { 'lib/built.js': entry } });
  const good = { source: 'npm:@webaudiomodules/sdk@0.0.12/dist/index.js', license: 'MIT', sha256: sha256(built) };
  assert.deepEqual([...vendorOf({ 'lib/built.js': built, 'vendor.json': vendor(good) }).vendored], ['lib/built.js']);
  assert.equal(textProblem('lib/built.js', built, { vendored: true }), null);
  assert.match(textProblem('lib/built.js', built), /longer than/);
  assert.match(vendorOf({ 'lib/built.js': built + ' ', 'vendor.json': vendor(good) }).problems[0], /does not match the sha256/);
  assert.match(vendorOf({ 'vendor.json': vendor(good) }).problems[0], /does not have/);
  assert.match(vendorOf({ 'lib/built.js': built, 'vendor.json': vendor({ ...good, license: '' }) }).problems[0], /license/);
  assert.match(vendorOf({ 'lib/built.js': built, 'vendor.json': vendor({ ...good, source: 'file:///etc/passwd' }) }).problems[0], /source/);
  assert.match(vendorOf({ 'vendor.json': '{' }).problems[0], /not valid JSON/);
  assert.match(vendorOf({ 'lib/built.js': built, 'vendor.json': vendor({ ...good, source: 'https://example.com/lib.js' }) }).problems[0], /source/);
  assert.equal(textProblem('lib/built.js', built.replace('1;', '\u0000;'), { vendored: true }) !== null, true, 'control characters still count');
});

test('only built JavaScript or CSS from a package the registry takes can be vendored', () => {
  const lua = 'return {}\n';
  const entry = (path, text, source = 'npm:@webaudiomodules/sdk@0.0.12/dist/index.js') => ({
    [path]: text,
    'vendor.json': JSON.stringify({ files: { [path]: { source, license: 'MIT', sha256: sha256(text) } } }),
  });
  for (const path of ['init.lua', 'lib/util.lua', 'page/index.html']) {
    const got = vendorOf(entry(path, lua));
    assert.equal(got.vendored.size, 0, path);
    assert.match(got.problems[0], /only for built JavaScript or CSS/);
  }
  const stranger = vendorOf(entry('lib/x.js', 'x', 'npm:left-pad@1.3.0/index.js'));
  assert.equal(stranger.vendored.size, 0);
  assert.match(stranger.problems[0], /left-pad is not a package/);
  for (const source of ['npm:@webaudiomodules/sdk@^0.0.12/dist/index.js', 'npm:@webaudiomodules/sdk@0.0.12/../x.js']) {
    assert.match(vendorOf(entry('lib/x.js', 'x', source)).problems[0], /exact version/, source);
  }
  assert.equal(vendorOf(entry('lib/x.css', 'x')).vendored.size, 1);
});

test('buildIndex carries what a plugin exports', () => {
  const m = manifestFor(good({ exports: ['wam'], files: { 'init.lua': '', 'wam/a.js': '' } }), { login: 'ann', id: 1 }, 1);
  assert.deepEqual(buildIndex([{ manifest: m, commit: 'aaa', updated: '' }]).plugins[0].exports, ['wam']);
  const plain = manifestFor(good(), { login: 'ann', id: 1 }, 1);
  assert.equal('exports' in buildIndex([{ manifest: plain, commit: 'aaa', updated: '' }]).plugins[0], false);
});

test('indexProblems holds each entry to the commit it names', () => {
  const commit = 'a'.repeat(40);
  const manifest = manifestFor(good({ permissions: ['net'] }), { login: 'ann', id: 1 }, 1);
  const history = { manifest, files: ['README.md', 'init.lua', 'lib/util.lua'], last: commit, updated: '2026-01-01T00:00:00+00:00' };
  const at = (kind, id, c) => (kind === 'plugin' && id === 'hello.world' && c === commit ? history : null);
  const index = buildIndex([{ manifest, commit, updated: '2026-01-01T00:00:00Z' }]);
  assert.deepEqual(indexProblems(index, at), []);

  const wider = structuredClone(index);
  wider.plugins[0].permissions = [];
  assert.match(indexProblems(wider, at)[0], /permissions of plugins\/hello\.world is \[\]/);

  const forked = structuredClone(index);
  forked.plugins[0].commit = 'b'.repeat(40);
  assert.match(indexProblems(forked, at)[0], /not in the history of main/);

  const untouched = (kind, id, c) => ({ ...history, last: 'c'.repeat(40), c });
  assert.match(indexProblems(index, untouched)[0], /did not change that folder/);

  const extra = structuredClone(index);
  extra.plugins[0].files.push('evil.lua');
  assert.ok(indexProblems(extra, at).some((p) => /files of plugins\/hello\.world/.test(p)));

  const older = structuredClone(index);
  delete older.plugins[0].optional;
  assert.deepEqual(indexProblems(older, at), [], 'an index from before a field was added still holds');
  delete older.plugins[0].permissions;
  assert.match(indexProblems(older, at)[0], /no permissions/);
});

/** One step of a folder's log, the way index.mjs reads it: a commit, its date, proteus.json and files. */
function step(commit, version, { author = { login: 'ann', id: 1 }, issue = null, permissions = [], files } = {}) {
  const manifest = manifestFor(good({ version, permissions }), author, issue);
  return { commit: commit.repeat(40), updated: '2026-01-01T00:00:00Z', manifest, files: files ?? [...manifest.files] };
}

test('historyOf keeps each past version at the last commit that had it', () => {
  const log = [step('d', '1.2.0', { issue: 9 }), step('c', '1.1.0', { permissions: ['net'] }), step('b', '1.1.0'), step('a', '1.0.0', { issue: 4 })];
  const past = historyOf(log);
  assert.deepEqual(
    past.versions.map((v) => [v.version, v.commit[0]]),
    [
      ['1.1.0', 'c'],
      ['1.0.0', 'a'],
    ],
  );
  assert.deepEqual(past.versions[0].permissions, ['net'], 'each version says what it asked for then');
  assert.deepEqual(past.versions[0].files, ['README.md', 'init.lua', 'lib/util.lua']);
  assert.equal('id' in past.versions[0], false);
  assert.equal(past.issue, 4, 'the issue that first submitted it');
  assert.deepEqual(past.issues, [9, 4]);
});

test('historyOf stops where the folder was gone or someone else published it', () => {
  const gone = [step('c', '2.0.0'), { commit: 'b'.repeat(40), updated: '', manifest: null, files: [] }, step('a', '1.0.0', { issue: 3 })];
  assert.deepEqual(historyOf(gone), { versions: [], issue: null, issues: [] });
  const taken = [step('c', '2.0.0'), step('b', '1.0.0', { author: { login: 'eve', id: 2 } })];
  assert.deepEqual(historyOf(taken).versions, []);
  const mismatched = [step('c', '2.0.0'), step('b', '1.5.0', { files: ['init.lua'] }), step('a', '1.0.0')];
  assert.deepEqual(
    historyOf(mismatched).versions.map((v) => v.version),
    ['1.0.0'],
    'a commit whose files do not match its proteus.json is skipped',
  );
  const higher = [step('c', '1.0.0'), step('b', '1.5.0')];
  assert.deepEqual(historyOf(higher).versions, [], 'only versions below the current one count');
  assert.deepEqual(historyOf([]), { versions: [], issue: null, issues: [] });
});

test('buildIndex carries past versions and the submission issue', () => {
  const log = [step('c', '1.2.0', { issue: 9 }), step('b', '1.1.0'), step('a', '1.0.0', { issue: 4 })];
  const { versions, issue } = historyOf(log);
  const [entry] = buildIndex([{ manifest: log[0].manifest, commit: log[0].commit, updated: log[0].updated, versions, issue }]).plugins;
  assert.equal(entry.issue, 4);
  assert.deepEqual(
    entry.versions.map((v) => v.version),
    ['1.1.0', '1.0.0'],
  );
  const [plain] = buildIndex([{ manifest: log[0].manifest, commit: log[0].commit, updated: '', versions: [], issue: null }]).plugins;
  assert.equal('versions' in plain, false);
  assert.equal('issue' in plain, false);
  const many = Array.from({ length: MAX_VERSIONS + 5 }, (_, i) => ({ version: `0.${i}.0` }));
  assert.equal(buildIndex([{ manifest: log[0].manifest, commit: 'c', updated: '', versions: many }]).plugins[0].versions.length, MAX_VERSIONS);
});

test('indexProblems holds each past version to its commit', () => {
  const log = [step('c', '1.2.0', { issue: 9 }), step('b', '1.1.0', { permissions: ['net'] }), step('a', '1.0.0', { issue: 4 })];
  const { versions, issue } = historyOf(log);
  const top = log[0];
  const at = (kind, id, c) => (c === top.commit ? { manifest: top.manifest, files: top.files, last: top.commit, updated: top.updated, history: log } : null);
  const index = buildIndex([{ manifest: top.manifest, commit: top.commit, updated: top.updated, versions, issue }]);
  assert.deepEqual(indexProblems(index, at), []);

  const fewer = structuredClone(index);
  fewer.plugins[0].versions.pop();
  assert.deepEqual(indexProblems(fewer, at), [], 'an index may keep fewer versions than the history has');

  const wider = structuredClone(index);
  wider.plugins[0].versions[0].permissions = [];
  assert.match(indexProblems(wider, at)[0], /permissions of plugins\/hello\.world "1\.1\.0" is \[\], but the history says \["net"\]/);

  const moved = structuredClone(index);
  moved.plugins[0].versions[1].commit = 'b'.repeat(40);
  assert.match(indexProblems(moved, at)[0], /commit of plugins\/hello\.world "1\.0\.0"/);

  const invented = structuredClone(index);
  invented.plugins[0].versions.push({ ...invented.plugins[0].versions[1], version: '0.9.0' });
  assert.match(indexProblems(invented, at)[0], /"0\.9\.0" as a past version, but no commit/);

  const twice = structuredClone(index);
  twice.plugins[0].versions.push(twice.plugins[0].versions[1]);
  assert.ok(indexProblems(twice, at).some((p) => /twice/.test(p)));

  const shuffled = structuredClone(index);
  shuffled.plugins[0].versions.reverse();
  assert.ok(indexProblems(shuffled, at).some((p) => /out of order/.test(p)));

  const otherIssue = structuredClone(index);
  otherIssue.plugins[0].issue = 12;
  assert.match(indexProblems(otherIssue, at)[0], /the issue 12/);
  otherIssue.plugins[0].issue = 9;
  assert.deepEqual(indexProblems(otherIssue, at), [], 'any submission issue of the span holds');

  const notList = structuredClone(index);
  notList.plugins[0].versions = 'all';
  assert.match(indexProblems(notList, at)[0], /not a list/);

  // Someone else's code at the same id is never a past version.
  const taken = [top, step('b', '1.1.0', { author: { login: 'eve', id: 2 } }), log[2]];
  const atTaken = (kind, id, c) => ({ ...at(kind, id, c), history: taken });
  assert.ok(indexProblems(index, atTaken).some((p) => /"1\.1\.0" as a past version/.test(p)));
});
