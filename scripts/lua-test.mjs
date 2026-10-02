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
//   read(path)                 reads a file of a plugin or profile, from the top of the
//                              registry, such as read('plugins/my.plugin/init.lua')
//   update, write(path, text)  true with --update, and then writes a file
// `require('name')` loads name.lua from the plugin's own folder, then from the app's lua/lib.
//
// Last it runs contracts/*.test.lua, which hold every plugin of one kind to the app's rules,
// such as every theme to the theme contract. They get two more globals:
//   plugin_ids()               every plugin id, sorted
//   load_plugin(id)            the table a plugin's init.lua returns, loaded as Proteus does
//
// The app's lua/lib comes from a ProteusApp/app checkout: PROTEUS_APP names it, or it sits
// beside the registry at ../app. The app's repository is private, so the check workflow has
// none. Without one, the contracts and each test that requires one of the app's lib/ modules
// are skipped, with the reason printed.

import { APP, NO_APP, declaredOf, engine, reader } from './lua.mjs';
import { existsSync, readFileSync, readdirSync, realpathSync, statSync, writeFileSync } from 'node:fs';
import { join, relative, resolve, sep } from 'node:path';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';

const ROOT = resolve(import.meta.dirname, '..');
const APP_LIB = APP ? resolve(APP, 'lua', 'lib') : null;

/** Reads a file of a plugin's own folder, then of the app's lua/lib, as Proteus's require does. */
function ownThenLib(dir) {
  const own = reader(dir);
  const lib = APP_LIB ? reader(APP_LIB) : () => undefined;
  return (rel) => own(rel) ?? lib(rel);
}
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
  local skipped = 0
  for _, t in ipairs (tests) do
    local good, err = xpcall (t.fn, debug.traceback)
    if good then
      passed = passed + 1
    elseif tostring (err):find ('(NEEDS_APP)', 1, true) then
      -- It needs one of the app's lib/ modules, and there is no app checkout.
      skipped = skipped + 1
    else
      failed = failed + 1
      lines[#lines + 1] = '  FAIL ' .. t.name .. '\\n    ' .. tostring (err):gsub ('\\n', '\\n    ')
    end
  end
  return passed, failed, table.concat (lines, '\\n'), skipped
end
`;

/**
 * Reads a file for a test. A submitted plugin's tests run here, and the log is public, so a
 * test reads only the registry's plugins and profiles: the path, links followed, stays in
 * plugins/ or profiles/.
 */
function readForTest(path) {
  const shown = String(path);
  let target;
  try {
    target = realpathSync(resolve(ROOT, shown));
  } catch {
    throw new Error(`read: ${shown} does not exist`);
  }
  const inside = ['plugins', 'profiles'].some((root) => target.startsWith(realpathSync(join(ROOT, root)) + sep));
  if (!inside || statSync(target).isDirectory()) throw new Error(`read: a test reads only files in plugins/ and profiles/, not ${shown}`);
  return readFileSync(target, 'utf8');
}

const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);
const list = (v) => (Array.isArray(v) ? v : []);

/** What declared fields disagree with proteus.json, as sentences. */
function compare(declared, meta, kind) {
  const problems = [];
  for (const key of ['name', 'description', 'version']) {
    const d = typeof declared[key] === 'string' ? declared[key].trim() : declared[key];
    if (d !== meta[key]) problems.push(`${key} is ${JSON.stringify(d)} in the Lua file but ${JSON.stringify(meta[key])} in proteus.json.`);
  }
  const keys = kind === 'profile' ? ['plugins'] : ['depends', 'optional', 'permissions', 'folders', 'exports'];
  for (const key of keys) {
    if (!same(list(declared[key]), list(meta[key]))) {
      problems.push(`${key} is ${JSON.stringify(list(declared[key]))} in the Lua file but ${JSON.stringify(list(meta[key]))} in proteus.json.`);
    }
  }
  // A profile that starts from a base names the feature, so a Proteus without bases does not
  // install it and run only half its plugins.
  if (kind === 'profile' && declared.extends !== undefined) {
    if (typeof declared.extends !== 'string') {
      problems.push("extends must name a base that ships with Proteus, such as 'shell'.");
    } else if (!list(declared.requires?.features).includes('profile-extends')) {
      problems.push("A profile with extends needs requires = { features = { 'profile-extends' } }.");
    }
  }
  const req = (r) => ({ proteus: r?.proteus ?? null, features: list(r?.features) });
  if (!same(req(declared.requires), req(meta.requires))) {
    problems.push(`requires is ${JSON.stringify(req(declared.requires))} in the Lua file but ${JSON.stringify(req(meta.requires))} in proteus.json.`);
  }
  return problems;
}

// Tests can also check shader code with real compilers, through
//   shader_check(lang, stage, source, entry)
// lang is 'glsl', 'wgsl' or 'hlsl', and stage is 'fragment' or 'vertex' (WGSL checks the whole
// module). entry names the HLSL entry point, `main` when nil. It returns true when the code
// compiles, false and the compiler's messages when it does not, and nil and why when the
// compiler is not installed: glslangValidator for GLSL ES and HLSL, and naga for WGSL. With
// SHADER_TOOLS=required in the environment, as in the check workflow, a missing compiler fails
// the test instead.
const SHADER_TOOLS = {
  glsl: { tool: 'glslangValidator', ext: { fragment: 'frag', vertex: 'vert' }, args: (file) => [file] },
  wgsl: { tool: 'naga', ext: { fragment: 'wgsl', vertex: 'wgsl' }, args: (file) => [file] },
  // glslang reads HLSL only to make SPIR-V, which goes beside the source and is thrown away.
  hlsl: {
    tool: 'glslangValidator',
    ext: { fragment: 'hlsl', vertex: 'hlsl' },
    args: (file, stage, entry) => ['-D', '-V', '-S', stage === 'vertex' ? 'vert' : 'frag', '-e', entry || 'main', '-o', `${file}.spv`, file],
  },
};

/** 'ok', 'missing:<why>' or 'error:<messages>', which the Lua side turns into its results. */
function shaderCheck(lang, stage, source, entry) {
  const spec = SHADER_TOOLS[String(lang)];
  const ext = spec?.ext[String(stage)];
  if (!spec || !ext) throw new Error(`shader_check: no compiler for ${lang} ${stage}`);
  const dir = mkdtempSync(join(tmpdir(), 'shader-check-'));
  try {
    const file = join(dir, `shader.${ext}`);
    writeFileSync(file, String(source));
    const run = spawnSync(spec.tool, spec.args(file, String(stage), entry == null ? '' : String(entry)), {
      encoding: 'utf8',
      timeout: 30000,
    });
    if (run.error?.code === 'ENOENT') {
      const why = `${spec.tool} is not installed`;
      if (process.env.SHADER_TOOLS === 'required') throw new Error(`shader_check: ${why}`);
      return `missing:${why}`;
    }
    if (run.error) throw run.error;
    if (run.status === 0) return 'ok';
    return `error:${`${run.stdout}${run.stderr}`.split(file).join(`shader.${ext}`).trim()}`;
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

const SHADER_PRELUDE = `
function shader_check (lang, stage, source, entry)
  local result = __shader_check (lang, stage, source, entry)
  if result == 'ok' then return true end
  local kind, rest = result:match ('^(%a+):(.*)$')
  if kind == 'missing' then return nil, rest end
  return false, rest
end
`;

let failed = 0;
let passed = 0;
let skipped = 0;

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
      t.global.set('read', readForTest);
      t.global.set('update', update);
      t.global.set('write', (path, body) => {
        if (!update) throw new Error('write needs --update');
        const target = resolve(ROOT, path);
        if (!target.startsWith(dir + sep)) throw new Error(`a test may only write inside ${root}/${id}`);
        writeFileSync(target, body);
      });
      t.global.set('__read_own', ownThenLib(dir));
      t.global.set('__shader_check', shaderCheck);
      // Tests run with the whole standard library, and require from the plugin's own folder.
      t.doStringSync(`
        local own = __sandbox (__read_own).require
        function require (name) return own (name) end
      `);
      t.doStringSync(PRELUDE);
      t.doStringSync(SHADER_PRELUDE);
      const shown = relative(ROOT, file);
      try {
        await t.doString(readFileSync(file, 'utf8'));
        const [p, f, r, s] = t.doStringSync('local p, f, r, s = __run_tests () return { p, f, r, s }');
        passed += p;
        failed += f;
        console.log(`${f === 0 ? 'ok  ' : 'FAIL'} ${shown}  (${p} passed, ${f} failed${s > 0 ? `, ${s} skipped: ${NO_APP}` : ''})`);
        skipped += s;
        if (r) console.log(r);
      } catch (err) {
        if (String(err.message).includes('(NEEDS_APP)')) {
          // A module it requires at the top is one of the app's, and there is no checkout.
          skipped += 1;
          console.log(`skip ${shown}: ${NO_APP}`);
        } else {
          failed += 1;
          console.log(`FAIL ${shown}: ${err.message}`);
        }
      }
      t.global.close();
    }
  }
}

// The contracts: every plugin of one kind held to the app's rules.
const contractDir = join(ROOT, 'contracts');
const contracts = existsSync(contractDir) ? readdirSync(contractDir).filter((n) => n.endsWith('.test.lua') && n.includes(filter)).sort() : [];
if (contracts.length > 0 && !APP_LIB) {
  skipped += contracts.length;
  console.log(
    `skip ${contracts.map((n) => `contracts/${n}`).join(', ')}: they need the app's lua/lib, and ${NO_APP}. ` +
      'Run them locally before a pull request that changes a theme or an icon pack.',
  );
}
const pluginIds = existsSync(join(ROOT, 'plugins'))
  ? readdirSync(join(ROOT, 'plugins'))
      .filter((id) => existsSync(join(ROOT, 'plugins', id, 'init.lua')))
      .sort()
  : [];
for (const name of APP_LIB ? contracts : []) {
  const file = join(contractDir, name);
  const t = await engine();
  t.global.set('read', (path) => readFileSync(join(ROOT, path), 'utf8'));
  t.global.set('__plugin_ids', () => pluginIds.join('\n'));
  t.global.set('__read_plugin', (id, path) => {
    if (!pluginIds.includes(String(id))) return undefined;
    return ownThenLib(join(ROOT, 'plugins', String(id)))(path);
  });
  t.global.set('__read_own', reader(APP_LIB));
  t.doStringSync(`
    local lib = __sandbox (__read_own).require
    function require (name) return lib (name) end
    function plugin_ids ()
      local out = {}
      for id in (__plugin_ids () .. '\\n'):gmatch ('([^\\n]+)\\n') do out[#out + 1] = id end
      return out
    end
    function load_plugin (id)
      local function read_own (path) return __read_plugin (id, path) end
      local src = read_own ('init.lua')
      if not src then error ('plugins/' .. tostring (id) .. ' has no init.lua', 2) end
      local env = __sandbox (read_own)
      return assert (load (src, '@plugins/' .. id .. '/init.lua', 't', env)) ()
    end
  `);
  t.doStringSync(PRELUDE);
  const shown = relative(ROOT, file);
  try {
    await t.doString(readFileSync(file, 'utf8'));
    const [p, f, r, s] = t.doStringSync('local p, f, r, s = __run_tests () return { p, f, r, s }');
    passed += p;
    failed += f;
    console.log(`${f === 0 ? 'ok  ' : 'FAIL'} ${shown}  (${p} passed, ${f} failed${s > 0 ? `, ${s} skipped: ${NO_APP}` : ''})`);
        skipped += s;
    if (r) console.log(r);
  } catch (err) {
    failed += 1;
    console.log(`FAIL ${shown}: ${err.message}`);
  }
  t.global.close();
}

console.log(`\n${passed} passed, ${failed} failed${skipped > 0 ? `, ${skipped} skipped` : ''}`);
process.exitCode = failed === 0 ? 0 : 1;
