// Keeps each plugin's vendor.json honest. A vendored file is code copied from elsewhere, such
// as a library's build or a WebAssembly module, which a reviewer checks against its source
// instead of reading.
//
//   node scripts/vendor.mjs hash plugins/<id>      writes each listed file's sha256
//   node scripts/vendor.mjs verify [plugins/<id>]  fetches each source and compares the files
//
// A source is `npm:<package>@<version>/<path in the package>`, such as
// `npm:@webaudiomodules/sdk@0.0.12/dist/index.js`, or an https address of the file itself.
// verify runs every plugin with a vendor.json, or with a binary file, when it is given none.
// It compares bytes, so a binary file is checked the same way as text. A binary file that
// vendor.json does not list fails, since nothing else vouches for it.
import { execFileSync } from 'node:child_process';
import { existsSync, mkdtempSync, readdirSync, readFileSync, rmSync, statSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';
import { isBinaryPath, sha256 } from './registry.mjs';

/** The npm package, version and path a source names, or null for an https source. */
export function npmSource(source) {
  const m = /^npm:(@?[^@/]+(?:\/[^@/]+)?)@([^/]+)\/(.+)$/.exec(source);
  return m ? { name: m[1], version: m[2], path: m[3] } : null;
}

/** Every file under a folder, as paths from that folder. */
function filesUnder(dir, prefix = '') {
  const out = [];
  for (const name of readdirSync(dir)) {
    const full = join(dir, name);
    const rel = prefix ? `${prefix}/${name}` : name;
    if (statSync(full).isDirectory()) out.push(...filesUnder(full, rel));
    else out.push(rel);
  }
  return out;
}

/** The vendor.json of a plugin folder, or an empty one. */
function vendorJson(dir) {
  const path = join(dir, 'vendor.json');
  return existsSync(path) ? JSON.parse(readFileSync(path, 'utf8')) : { files: {} };
}

/** Writes the sha256 of each file vendor.json lists. */
export function hashFolder(dir) {
  const data = vendorJson(dir);
  for (const [file, entry] of Object.entries(data.files ?? {})) entry.sha256 = sha256(readFileSync(join(dir, file)));
  writeFileSync(join(dir, 'vendor.json'), JSON.stringify(data, null, 2) + '\n');
}

/**
 * Compares each file vendor.json lists with the bytes its source holds, and with its sha256.
 * `sourceBytes(source)` fetches a source. Returns one line for each file, `ok` or `FAIL`.
 */
export async function verifyFolder(dir, sourceBytes) {
  const lines = [];
  const entries = vendorJson(dir).files ?? {};
  for (const file of filesUnder(dir).filter(isBinaryPath).sort()) {
    if (!Object.hasOwn(entries, file)) lines.push(`FAIL ${dir}/${file}: a binary file vendor.json does not list`);
  }
  for (const [file, entry] of Object.entries(entries)) {
    const kind = isBinaryPath(file) ? ' (binary)' : '';
    try {
      const local = readFileSync(join(dir, file));
      const upstream = await sourceBytes(entry.source);
      const same = sha256(upstream) === sha256(local) && sha256(local) === entry.sha256;
      lines.push(`${same ? 'ok  ' : 'FAIL'} ${dir}/${file}${kind} <- ${entry.source}`);
    } catch (err) {
      lines.push(`FAIL ${dir}/${file}${kind}: ${err.message}`);
    }
  }
  return lines;
}

/** Fetches sources from npm and the web, unpacking each npm package once. `done` cleans up. */
export function webSources() {
  const packs = new Map();
  const unpacked = (name, version) => {
    const key = `${name}@${version}`;
    if (packs.has(key)) return packs.get(key);
    const dir = mkdtempSync(join(tmpdir(), 'vendor-'));
    const file = execFileSync('npm', ['pack', key, '--silent', '--ignore-scripts', '--pack-destination', dir], { encoding: 'utf8' }).trim();
    execFileSync('tar', ['xzf', join(dir, file), '-C', dir]);
    packs.set(key, join(dir, 'package'));
    return join(dir, 'package');
  };
  return {
    async sourceBytes(source) {
      const npm = npmSource(source);
      if (npm) return readFileSync(join(unpacked(npm.name, npm.version), npm.path));
      const res = await fetch(source);
      if (!res.ok) throw new Error(`${source}: ${res.status}`);
      return Buffer.from(await res.arrayBuffer());
    },
    done() {
      for (const dir of new Set(packs.values())) rmSync(join(dir, '..'), { recursive: true, force: true });
    },
  };
}

// Run from the command line, not when a test imports this file.
if (import.meta.url === pathToFileURL(process.argv[1]).href) {
  const [command, ...dirs] = process.argv.slice(2);
  if (!['hash', 'verify'].includes(command)) {
    console.error('Usage: node scripts/vendor.mjs hash plugins/<id> | verify [plugins/<id> ...]');
    process.exit(2);
  }
  const wanted = (dir) => existsSync(join(dir, 'vendor.json')) || filesUnder(dir).some(isBinaryPath);
  const targets = dirs.length
    ? dirs
    : readdirSync('plugins')
        .map((id) => join('plugins', id))
        .filter((dir) => statSync(dir).isDirectory() && wanted(dir));
  if (command === 'hash') {
    for (const dir of targets) hashFolder(dir);
  } else {
    const web = webSources();
    let failed = 0;
    for (const dir of targets) {
      for (const line of await verifyFolder(dir, web.sourceBytes)) {
        console.log(line);
        if (line.startsWith('FAIL')) failed += 1;
      }
    }
    web.done();
    if (failed) process.exitCode = 1;
  }
}
