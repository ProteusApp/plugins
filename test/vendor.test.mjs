import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { sha256 } from '../scripts/registry.mjs';
import { hashFolder, npmSource, verifyFolder } from '../scripts/vendor.mjs';

const WASM = Buffer.from([0, 0x61, 0x73, 0x6d, 1, 0, 0, 0, 0x80, 0xff]);
const SOURCE = 'npm:@proteus-samples/tone@1.0.0/dist/tone.wasm';

/** A plugin folder with a vendored module and the sources it names. */
function plugin(t, files) {
  const dir = mkdtempSync(join(tmpdir(), 'vendor-test-'));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  for (const [path, bytes] of Object.entries(files)) {
    mkdirSync(join(dir, path, '..'), { recursive: true });
    writeFileSync(join(dir, path), bytes);
  }
  return dir;
}

const vendorJson = (sha) => JSON.stringify({ files: { 'wam/tone.wasm': { source: SOURCE, license: 'MIT', sha256: sha } } });

test('npmSource reads a package, its version and a path', () => {
  assert.deepEqual(npmSource('npm:@webaudiomodules/sdk@0.0.12/dist/index.js'), { name: '@webaudiomodules/sdk', version: '0.0.12', path: 'dist/index.js' });
  assert.deepEqual(npmSource('npm:left-pad@1.3.0/index.js'), { name: 'left-pad', version: '1.3.0', path: 'index.js' });
  assert.equal(npmSource('https://example.com/x.wasm'), null);
});

test('verify compares a binary file with its source, byte for byte', async (t) => {
  const dir = plugin(t, { 'wam/tone.wasm': WASM, 'vendor.json': vendorJson(sha256(WASM)) });
  const asked = [];
  const same = async (source) => {
    asked.push(source);
    return WASM;
  };
  assert.deepEqual(await verifyFolder(dir, same), [`ok   ${dir}/wam/tone.wasm (binary) <- ${SOURCE}`]);
  assert.deepEqual(asked, [SOURCE]);
  const other = async () => Buffer.concat([WASM, Buffer.from([1])]);
  assert.match((await verifyFolder(dir, other))[0], /^FAIL /);
  const gone = async () => {
    throw new Error('404');
  };
  assert.match((await verifyFolder(dir, gone))[0], /^FAIL .*: 404$/);
});

test('verify fails a binary file that vendor.json does not list', async (t) => {
  const dir = plugin(t, { 'wam/tone.wasm': WASM, 'wam/extra.wasm': WASM, 'vendor.json': vendorJson(sha256(WASM)) });
  const lines = await verifyFolder(dir, async () => WASM);
  assert.equal(lines[0], `FAIL ${dir}/wam/extra.wasm: a binary file vendor.json does not list`);
  assert.match(lines[1], /^ok /);
});

test('hash writes each listed file\'s sha256', (t) => {
  const dir = plugin(t, { 'wam/tone.wasm': WASM, 'vendor.json': vendorJson('') });
  hashFolder(dir);
  const data = JSON.parse(readFileSync(join(dir, 'vendor.json'), 'utf8'));
  assert.equal(data.files['wam/tone.wasm'].sha256, sha256(WASM));
});
