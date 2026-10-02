// Keeps each plugin's vendor.json honest. A vendored file is code copied from elsewhere, such
// as a library's build, which a reviewer checks against its source instead of reading.
//
//   node scripts/vendor.mjs hash plugins/<id>      writes each listed file's sha256
//   node scripts/vendor.mjs verify [plugins/<id>]  fetches each source and compares the files
//
// A source is `npm:<package>@<version>/<path in the package>`, such as
// `npm:@webaudiomodules/sdk@0.0.12/dist/index.js`, from a package in VENDOR_PACKAGES in
// registry.mjs. verify runs every plugin with a vendor.json when it is given none. The check
// workflow runs it, so a vendored file that differs from its published source never merges.
import { execFileSync } from 'node:child_process';
import { existsSync, mkdtempSync, readdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { VENDOR_PACKAGES, npmSource, sha256 } from './registry.mjs';

const [command, ...dirs] = process.argv.slice(2);
if (!['hash', 'verify'].includes(command)) {
  console.error('Usage: node scripts/vendor.mjs hash plugins/<id> | verify [plugins/<id> ...]');
  process.exit(2);
}

const withVendor = (dir) => existsSync(join(dir, 'vendor.json'));
const targets = dirs.length
  ? dirs
  : readdirSync('plugins')
      .map((id) => join('plugins', id))
      .filter(withVendor);

const packs = new Map();
/** Unpacks an npm package once, and returns its folder. */
function unpacked(name, version) {
  const key = `${name}@${version}`;
  if (packs.has(key)) return packs.get(key);
  const dir = mkdtempSync(join(tmpdir(), 'vendor-'));
  const file = execFileSync('npm', ['pack', key, '--silent', '--ignore-scripts', '--pack-destination', dir], { encoding: 'utf8' }).trim();
  execFileSync('tar', ['xzf', join(dir, file), '-C', dir]);
  packs.set(key, join(dir, 'package'));
  return join(dir, 'package');
}

/** The bytes a source names. */
async function sourceBytes(source) {
  const npm = npmSource(source);
  if (!npm) throw new Error(`${source} is not npm:<package>@<version>/<path>`);
  if (!VENDOR_PACKAGES.includes(npm.name)) throw new Error(`${npm.name} is not a package the registry takes vendored files from`);
  return readFileSync(join(unpacked(npm.name, npm.version), npm.path));
}

let failed = 0;
for (const dir of targets) {
  const path = join(dir, 'vendor.json');
  const data = JSON.parse(readFileSync(path, 'utf8'));
  for (const [file, entry] of Object.entries(data.files ?? {})) {
    const local = readFileSync(join(dir, file));
    if (command === 'hash') {
      entry.sha256 = sha256(local);
      continue;
    }
    try {
      const upstream = await sourceBytes(entry.source);
      const same = sha256(upstream) === sha256(local) && sha256(local) === entry.sha256;
      console.log(`${same ? 'ok  ' : 'FAIL'} ${dir}/${file} <- ${entry.source}`);
      if (!same) failed += 1;
    } catch (err) {
      console.log(`FAIL ${dir}/${file}: ${err.message}`);
      failed += 1;
    }
  }
  if (command === 'hash') writeFileSync(path, JSON.stringify(data, null, 2) + '\n');
}
for (const dir of new Set(packs.values())) rmSync(join(dir, '..'), { recursive: true, force: true });
if (failed) process.exitCode = 1;
