import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import {
  LABEL,
  branchFor,
  buildIndex,
  canApprove,
  collectSubmission,
  commandOf,
  compareVersions,
  folderFor,
  isSubmission,
  kindOf,
  manifestFor,
  pathProblem,
  textProblem,
  vendorOf,
  BINARY_TYPES,
  LIMITS,
  base64Lines,
  binaryProblem,
  fromBase64,
  isBinaryPath,
  sha256,
  pullRequestBody,
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
  assert.equal(textProblem('lib/built.js', built.replace('1;', '\u0000;'), { vendored: true }) !== null, true, 'control characters still count');
});

// The app writes this issue for a plugin with a vendored WebAssembly module. See
// tests/lua/interface/store_binary_issue.md in the Proteus repository.
const BINARY_SAMPLE = readFileSync(new URL('./fixtures/store-binary-issue.md', import.meta.url), 'utf8').replace(/\r\n/g, '\n');

/** A WebAssembly module that holds every byte from 0 to 255 in a custom section, as in the sample. */
const WASM = Buffer.concat([Buffer.from([0, 0x61, 0x73, 0x6d, 1, 0, 0, 0, 0, 0x85, 0x02, 4]), Buffer.from('data'), Buffer.from([...Array(256).keys()])]);

/** vendor.json for some files, each with its true hash. */
const vendorFor = (files) =>
  JSON.stringify({
    files: Object.fromEntries(Object.entries(files).map(([path, bytes]) => [path, { source: 'npm:@proteus-samples/tone@1.0.0/dist/tone.wasm', license: 'MIT', sha256: sha256(bytes) }])),
  });

/** A plugin that vendors WebAssembly modules. */
function withWasm(wasm = { 'wam/tone.wasm': WASM }, extra = {}) {
  return good({ id: 'wam.tone', files: { 'init.lua': 'return {}', ...wasm, 'vendor.json': vendorFor(wasm) }, ...extra });
}

test('the binary sample issue from the app reads back to the module\'s bytes', () => {
  const got = collectSubmission([BINARY_SAMPLE]);
  assert.equal(got.complete, true);
  assert.deepEqual(Object.keys(got.sub.files), ['init.lua', 'vendor.json', 'wam/tone.wasm']);
  assert.ok(Buffer.isBuffer(got.sub.files['wam/tone.wasm']));
  assert.ok(got.sub.files['wam/tone.wasm'].equals(WASM));
  assert.equal(typeof got.sub.files['init.lua'], 'string');
  assert.deepEqual(validate(got.sub, { reserved }), []);
});

test('base64 travels in lines of 76 and reads back to the same bytes', () => {
  const bytes = Buffer.from([...Array(1000).keys()].map((i) => (i * 7) % 256));
  const text = base64Lines(bytes);
  assert.ok(text.split('\n').every((line) => line.length <= 76));
  assert.ok(fromBase64(text).equals(bytes));
  assert.equal(fromBase64('AGFz bQ==\n').toString('latin1'), '\0asm');
  assert.equal(fromBase64('AGFzbQ'), null, 'a length that is not a multiple of 4');
  assert.equal(fromBase64('AGF$bQ=='), null);
  assert.equal(fromBase64('AG==bQ=='), null, 'padding only at the end');
});

test('a base64 block is read only for a binary file, and only when it is base64', () => {
  const manifest = (files) => `<!-- proteus-manifest -->\n${FENCE}json\n${JSON.stringify({ format: 2, revision: 'r', id: 'a.b', name: 'A', description: 'B.', version: '1.0.0', files })}\n${FENCE}`;
  const blockAs = (path, encoding, text, k = 1, n = 1) =>
    `<!-- proteus-file path="${path}" part="${k}" of="${n}" rev="r"${encoding ? ` encoding="${encoding}"` : ''} -->\n${FENCE}text\n${text}\n${FENCE}`;
  const half = base64Lines(WASM).split('\n');
  const got = collectSubmission([
    manifest(['m.wasm']),
    blockAs('m.wasm', 'base64', half.slice(0, 2).join('\n') + '\n', 1, 2),
    blockAs('m.wasm', 'base64', half.slice(2).join('\n'), 2, 2),
  ]);
  assert.ok(got.sub.files['m.wasm'].equals(WASM));
  assert.match(collectSubmission([manifest(['init.lua']), blockAs('init.lua', 'base64', 'cmV0dXJuIHt9')]).error, /only a binary file/);
  assert.match(collectSubmission([manifest(['m.wasm']), blockAs('m.wasm', 'base64', 'not base64!')]).error, /not valid base64/);
  assert.match(collectSubmission([manifest(['m.wasm']), blockAs('m.wasm', 'hex', '0061736d')]).error, /encoding this registry does not know/);
  assert.match(
    collectSubmission([manifest(['m.wasm']), blockAs('m.wasm', 'base64', half[0], 1, 2), blockAs('m.wasm', '', half[1], 2, 2)]).error,
    /different encodings/,
  );
});

test('a binary file must be a vendored WebAssembly module', () => {
  assert.deepEqual(Object.keys(BINARY_TYPES), ['wasm']);
  assert.ok(isBinaryPath('wam/dsp.wasm'));
  assert.ok(isBinaryPath('DSP.WASM'));
  assert.ok(!isBinaryPath('logo.png'));
  assert.ok(!isBinaryPath('wasm'));
  assert.deepEqual(validate(withWasm(), { reserved }), []);
  const bare = good({ files: { 'init.lua': 'return {}', 'wam/tone.wasm': WASM } });
  assert.deepEqual(validate(bare, { reserved }), [
    'Wam/tone.wasm is a binary file, which the registry takes only when vendor.json lists it with its source, license and sha256.',
  ]);
  const fake = Buffer.from('MZ\x90\x00not wasm');
  assert.deepEqual(validate(withWasm({ 'wam/tone.wasm': fake }), { reserved }), ['Wam/tone.wasm is not a WebAssembly module.']);
  assert.match(binaryProblem('a.png', WASM, { vendored: true }), /not a kind of binary file/);
  // The hash still ties the bytes to vendor.json.
  const sub = withWasm();
  sub.files['wam/tone.wasm'] = Buffer.concat([WASM, Buffer.from([0])]);
  assert.match(validate(sub, { reserved }).join(), /does not match the sha256/);
  // Any other file that is not text is refused, vendored or not.
  const png = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
  assert.deepEqual(validate(withWasm({ 'logo.png': png }), { reserved }), ['Logo.png is not UTF-8 text.']);
});

test('binary files are held to a size of their own, and stay out of profiles', () => {
  const big = Buffer.concat([WASM, Buffer.alloc(400 * 1024)]);
  const three = { 'wam/a.wasm': big, 'wam/b.wasm': big, 'wam/c.wasm': big };
  assert.equal(LIMITS.binaryBytes, 1024 * 1024);
  assert.deepEqual(validate(withWasm(three), { reserved }), ["The plugin's binary files come to more than 1 MB."]);
  const huge = Buffer.concat([WASM, Buffer.alloc(LIMITS.fileBytes)]);
  assert.match(validate(withWasm({ 'wam/a.wasm': huge }), { reserved }).join(), /larger than 512 KB/);
  const profile = goodProfile({ files: { 'profile.lua': 'return {}', 'm.wasm': WASM } });
  assert.match(validate(profile, { reserved }).join(), /M\.wasm is not UTF-8 text|M\.wasm holds control characters/);
});

test('the index lists a plugin\'s binary files, and the pull request marks them', () => {
  const sub = withWasm();
  const m = manifestFor(sub, { login: 'ann', id: 1 }, 7);
  const index = buildIndex([
    { manifest: m, commit: 'abc', updated: '' },
    { manifest: manifestFor(good(), { login: 'ann', id: 1 }, 8), commit: 'def', updated: '' },
  ]);
  assert.deepEqual(index.plugins.find((p) => p.id === 'wam.tone').binary, ['wam/tone.wasm']);
  assert.equal('binary' in index.plugins.find((p) => p.id === 'hello.world'), false);
  const body = pullRequestBody(m, sub, 7, false);
  assert.match(body, /`plugins\/wam\.tone\/wam\/tone\.wasm` from `npm:@proteus-samples\/tone@1\.0\.0\/dist\/tone\.wasm` \(MIT, a binary WebAssembly module\)/);
  assert.match(body, /`plugins\/wam\.tone\/wam\/tone\.wasm` \(0\.3 KB, binary\)/);
  assert.match(body, /Every binary file is a published build/);
  assert.doesNotMatch(pullRequestBody(manifestFor(good(), { login: 'ann', id: 1 }, 7), good(), 7, false), /Every binary file/);
});
