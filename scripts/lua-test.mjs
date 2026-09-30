// Runs the Lua side of the registry's check, on the same Lua 5.4 Proteus uses.
//
//   node scripts/lua-test.mjs            checks every plugin and profile, and runs their tests
//   node scripts/lua-test.mjs shader     only the folders whose id contains "shader"
//   node scripts/lua-test.mjs --update   lets tests write the files they check, such as examples
//
// For each plugin it loads init.lua, the way Proteus does for a plugin it does not trust, and
// checks that what it declares matches its proteus.json: name, description, version, what it
// depends on, and above all its permissions, folders and requires. The marketplace shows
// proteus.json before an install, so the two must agree. Each profile's profile.lua is
// checked against its proteus.json the same way.
//
// Then it runs every plugins/<id>/tests/*.test.lua. A test file gets these globals:
//   test(name, fn)             declares a test
//   eq(actual, expected, msg)  deep equality, with a readable difference on failure
//   ok(value, msg)             fails unless value is truthy
//   read(path)                 reads a file, from the top of the registry
//   update, write(path, text)  true with --update, and then writes a file
// `require('name')` loads name.lua from the plugin's own folder.

import { declaredOf, engine, reader } from './lua.mjs';
import { existsSync, readFileSync, readdirSync, statSync, writeFileSync } from 'node:fs';
import { join, relative, resolve } from 'node:path';

const ROOT = resolve(import.meta.dirname, '..');
const args = process.argv.slice(2);
const update = args.includes('--update');
const filter = args.find((a) => !a.startsWith('--')) ?? '';

const PRELUDE = `
local tests = {}
function test (name, fn) tests[#tests + 1] = { name = name, fn = fn } end

local function show (v, depth)
  depth = depth or 0
  if type (v) == 'string' then return string.format ('%q', v) end
  if type (v) ~= 'table' then return tostring (v) end
  if depth > 3 then return '{...}' end
  local keys = {}
  for k in pairs (v) do keys[#keys + 1] = k end
  table.sort (keys, function (a, b) return tostring (a) < tostring (b) end)
  local parts = {}
  for _, k in ipairs (keys) do parts[#parts + 1] = tostring (k) .. ' = ' .. show (v[k], depth + 1) end
  return '{ ' .. table.concat (parts, ', ') .. ' }'
end

local function diff (a, b, path)
  if type (a) ~= type (b) then return path .. ': ' .. show (a) .. ' vs expected ' .. show (b) end
  if type (a) ~= 'table' then
    if a ~= b then return path .. ': ' .. show (a) .. ' vs expected ' .. show (b) end
    return nil
  end
  for k, v in pairs (b) do
    local d = diff (a[k], v, path .. '.' .. tostring (k))
    if d then return d end
  end
  for k, v in pairs (a) do
    if b[k] == nil then return path .. '.' .. tostring (k) .. ': unexpected ' .. show (v) end
  end
  return nil
end

function eq (actual, expected, msg)
  local d = diff (actual, expected, 'value')
  if d then error ((msg and (msg .. ': ') or '') .. d, 2) end
end

function ok (value, msg)
  if not value then error (msg or 'expected a true value', 2) end
end

function __run_tests ()
  local passed, failed, lines = 0, 0, {}
  for _, t in ipairs (tests) do
    local good, err = xpcall (t.fn, debug.traceback)
    if good then
      passed = passed + 1
    else
      failed = failed + 1
      lines[#lines + 1] = '  FAIL ' .. t.name .. '\\n    ' .. tostring (err):gsub ('\\n', '\\n    ')
    end
  end
  return passed, failed, table.concat (lines, '\\n')
end
`;

const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);
const list = (v) => (Array.isArray(v) ? v : []);

/** What declared fields disagree with proteus.json, as sentences. */
function compare(declared, meta, kind) {
  const problems = [];
  for (const key of ['name', 'description', 'version']) {
    const d = typeof declared[key] === 'string' ? declared[key].trim() : declared[key];
    if (d !== meta[key]) problems.push(`${key} is ${JSON.stringify(d)} in the Lua file but ${JSON.stringify(meta[key])} in proteus.json.`);
  }
  const keys = kind === 'profile' ? ['plugins'] : ['depends', 'optional', 'permissions', 'folders'];
  for (const key of keys) {
    if (!same(list(declared[key]), list(meta[key]))) {
      problems.push(`${key} is ${JSON.stringify(list(declared[key]))} in the Lua file but ${JSON.stringify(list(meta[key]))} in proteus.json.`);
    }
  }
  const req = (r) => ({ proteus: r?.proteus ?? null, features: list(r?.features) });
  if (!same(req(declared.requires), req(meta.requires))) {
    problems.push(`requires is ${JSON.stringify(req(declared.requires))} in the Lua file but ${JSON.stringify(req(meta.requires))} in proteus.json.`);
  }
  return problems;
}

let failed = 0;
let passed = 0;

for (const [root, kind, main] of [
  ['plugins', 'plugin', 'init.lua'],
  ['profiles', 'profile', 'profile.lua'],
]) {
  const base = join(ROOT, root);
  for (const id of existsSync(base) ? readdirSync(base).sort() : []) {
    const dir = join(base, id);
    if (!statSync(dir).isDirectory() || !id.includes(filter)) continue;
    const metaPath = join(dir, 'proteus.json');
    const mainPath = join(dir, main);
    if (!existsSync(metaPath) || !existsSync(mainPath)) continue;
    const meta = JSON.parse(readFileSync(metaPath, 'utf8'));
    const declared = await declaredOf(dir, main, `${root}/${id}/${main}`);
    const problems = declared.error ? [`${main} did not load: ${declared.error}`] : compare(declared, meta, kind);
    if (problems.length > 0) {
      failed += 1;
      console.log(`FAIL ${root}/${id}/${main}`);
      for (const p of problems) console.log(`  - ${p}`);
    } else {
      passed += 1;
      console.log(`ok   ${root}/${id}/${main} matches proteus.json`);
    }

    const testDir = join(dir, 'tests');
    if (kind !== 'plugin' || !existsSync(testDir)) continue;
    for (const name of readdirSync(testDir).filter((n) => n.endsWith('.test.lua')).sort()) {
      const file = join(testDir, name);
      const t = await engine();
      t.global.set('read', (path) => readFileSync(join(ROOT, path), 'utf8'));
      t.global.set('update', update);
      t.global.set('write', (path, body) => {
        if (!update) throw new Error('write needs --update');
        const target = resolve(ROOT, path);
        if (!target.startsWith(dir + '/')) throw new Error(`a test may only write inside ${root}/${id}`);
        writeFileSync(target, body);
      });
      t.global.set('__read_own', reader(dir));
      // Tests run with the whole standard library, and require from the plugin's own folder.
      t.doStringSync(`
        local own = __sandbox (__read_own).require
        function require (name) return own (name) end
      `);
      t.doStringSync(PRELUDE);
      const shown = relative(ROOT, file);
      try {
        await t.doString(readFileSync(file, 'utf8'));
        const [p, f, r] = t.doStringSync('local p, f, r = __run_tests () return { p, f, r }');
        passed += p;
        failed += f;
        console.log(`${f === 0 ? 'ok  ' : 'FAIL'} ${shown}  (${p} passed, ${f} failed)`);
        if (r) console.log(r);
      } catch (err) {
        failed += 1;
        console.log(`FAIL ${shown}: ${err.message}`);
      }
      t.global.close();
    }
  }
}

console.log(`\n${passed} passed, ${failed} failed`);
process.exitCode = failed === 0 ? 0 : 1;
