// Loads plugin and profile Lua files the way Proteus loads a plugin it does not trust, on the
// same Lua 5.4, to read what they declare. The check and the tests share it.

import { LuaFactory } from 'wasmoon';
import { existsSync, readFileSync, statSync } from 'node:fs';
import { join, resolve, sep } from 'node:path';

// Only what a restricted plugin sees in Proteus: no io, os.execute, package or debug.
export const SANDBOX = `
local function copy (t)
  local out = {}
  for k, v in pairs (t) do out[k] = v end
  return out
end

-- Stands in for a module from Proteus itself, such as lib/disk_paths.lua, which the registry
-- does not have. Reading a manifest needs only the table init.lua returns.
local stub
stub = setmetatable ({}, {
  __index = function () return stub end,
  __call = function () return stub end,
})

function __sandbox (read_own, lenient)
  local env = {
    assert = assert, error = error, ipairs = ipairs, next = next, pairs = pairs,
    pcall = pcall, xpcall = xpcall, select = select, tonumber = tonumber,
    tostring = tostring, type = type, rawequal = rawequal, rawget = rawget,
    rawset = rawset, rawlen = rawlen, setmetatable = setmetatable,
    getmetatable = getmetatable, _VERSION = _VERSION,
    string = copy (string), table = copy (table), math = copy (math),
    utf8 = copy (utf8), coroutine = copy (coroutine),
    os = { time = os.time, date = os.date, clock = os.clock, difftime = os.difftime },
    debug = { traceback = debug.traceback },
  }
  env.string.dump = nil
  env.print = print
  env._G = env
  env.load = function (chunk, name, _, e) return load (chunk, name, 't', e or env) end
  local std = { string = env.string, table = env.table, math = env.math, utf8 = env.utf8, coroutine = env.coroutine }
  local cache = {}
  env.require = function (name)
    if std[name] then return std[name] end
    if cache[name] ~= nil then return cache[name] end
    if type (name) ~= 'string' or name:find ('%.%.') or name:find ('[/\\\\:]') then
      error ("cannot load the module '" .. tostring (name) .. "'", 2)
    end
    local path = name:gsub ('%.', '/') .. '.lua'
    local src = read_own (path)
    if not src and lenient then return stub end
    if not src and __no_app then
      -- It may be one of the app's lib/ modules, which only an app checkout has. NEEDS_APP
      -- tells scripts/lua-test.mjs to skip the test rather than fail it.
      error ("module '" .. name .. "' is not in the plugin's folder, and there is no app checkout for the app's lib/ (NEEDS_APP)", 2)
    end
    if not src then error ("module '" .. name .. "' not found in the plugin's folder or the app's lib/", 2) end
    local chunk = assert (load (src, '@' .. path, 't', env))
    local value = chunk (name)
    if value == nil then value = true end
    cache[name] = value
    return value
  end
  return env
end

-- A small JSON writer for what a manifest declares: strings, numbers, booleans and lists.
local function json (v)
  local t = type (v)
  if t == 'string' then
    return '"' .. v:gsub ('[%c"\\\\]', function (c)
      return string.format ('\\\\u%04x', c:byte ())
    end) .. '"'
  elseif t == 'number' or t == 'boolean' then
    return tostring (v)
  elseif t == 'table' then
    if #v > 0 or next (v) == nil then
      local parts = {}
      for i, x in ipairs (v) do parts[i] = json (x) end
      return '[' .. table.concat (parts, ',') .. ']'
    end
    local keys = {}
    for k in pairs (v) do if type (k) == 'string' then keys[#keys + 1] = k end end
    table.sort (keys)
    local parts = {}
    for _, k in ipairs (keys) do parts[#parts + 1] = json (k) .. ':' .. json (v[k]) end
    return '{' .. table.concat (parts, ',') .. '}'
  end
  return 'null'
end

function __declared (src, path)
  local read_own = __read_own
  local env = __sandbox (read_own, true)
  local chunk, err = load (src, '@' .. path, 't', env)
  if not chunk then return json ({ error = tostring (err) }) end
  local ok, m = pcall (chunk)
  if not ok then return json ({ error = tostring (m) }) end
  if type (m) ~= 'table' then return json ({ error = path .. ' must return a table' }) end
  local out = {}
  for _, k in ipairs ({ 'name', 'description', 'version', 'depends', 'optional', 'permissions', 'folders', 'exports', 'requires', 'plugins' }) do
    local v = m[k]
    if type (v) ~= 'function' then out[k] = v end
  end
  return json (out)
end
`;

/**
 * A ProteusApp/app checkout, for the app's lua/lib and lua/types: the one PROTEUS_APP names,
 * or else one beside the registry at ../app. Null when there is none, as in the check
 * workflow, since the app's repository is private. PROTEUS_APP set to a folder without the
 * app means none, which is how to run the checks as the workflow does.
 */
export const APP = (() => {
  const named = process.env.PROTEUS_APP;
  const candidate = named ? resolve(named) : resolve(import.meta.dirname, '..', '..', 'app');
  return existsSync(join(candidate, 'lua', 'lib')) ? candidate : null;
})();

/** Why the checks that need the app are skipped, or null when there is an app checkout. */
export const NO_APP = APP
  ? null
  : 'there is no ProteusApp/app checkout (set PROTEUS_APP, or put it beside the registry at ../app)';

const factory = new LuaFactory();

/** A fresh Lua state with the sandbox helpers. */
export async function engine() {
  const lua = await factory.createEngine({ enableProxy: false, injectObjects: false });
  lua.global.set('__no_app', APP === null);
  lua.doStringSync(SANDBOX);
  return lua;
}

/** Reads a file inside `dir`, or undefined. The path never leaves the folder. */
export function reader(dir) {
  return (rel) => {
    const path = resolve(dir, String(rel));
    if (!path.startsWith(dir + sep) || !existsSync(path) || statSync(path).isDirectory()) return undefined;
    return readFileSync(path, 'utf8');
  };
}


/**
 * What a plugin's init.lua or a profile's profile.lua declares: name, description, version,
 * depends, optional, permissions, folders, requires and plugins. `error` is set when the file
 * did not load.
 */
export async function declaredOf(dir, main, shown = main) {
  const lua = await engine();
  try {
    lua.global.set('__read_own', reader(resolve(dir)));
    const text = lua.global.get('__declared')(readFileSync(resolve(dir, main), 'utf8'), shown);
    return JSON.parse(text);
  } finally {
    lua.global.close();
  }
}
