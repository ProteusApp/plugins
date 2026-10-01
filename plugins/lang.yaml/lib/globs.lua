-- globs: turns `schema` file associations into the `yaml.schemas` setting of
-- yaml-language-server. The server takes globs, not regular expressions, and matches them
-- against a file's whole address. Nothing here calls the host, so the tests reach it.

---@class LangYaml.GlobsModule
local M = {}

---True when a pattern holds a wildcard.
---@param pattern string
---@return boolean
local function wild (pattern)
  return pattern:find ('[%*%?]') ~= nil
end

---A pattern with `/` between folders, and without a drive or a `/` at its start.
---@param pattern string
---@return string
local function plain (pattern)
  local p = pattern:gsub ('\\', '/')
  p = p:gsub ('^%a:/', '/')
  return (p:gsub ('^/+', ''))
end

---The glob the server reads for a file association pattern. A pattern matches the end of a
---path, so the glob starts with `**/`, which lets any folders come before it.
---@param pattern string
---@return string
function M.to_glob (pattern)
  -- The server reads `{`, `}`, `(` and `)` as glob syntax. A file association reads them as
  -- plain characters, so each goes in brackets, where it stands for itself.
  local body = plain (pattern):gsub ('[%(%){}]', '[%0]')
  if body:sub (1, 3) == '**/' then
    return body
  end
  return '**/' .. body
end

---The Lua pattern for a file association pattern, not anchored.
---@param pattern string
---@return string
local function lua_body (pattern)
  local out = pattern:gsub ('[%^%$%(%)%%%.%[%]%+%-]', '%%%0')
  out = out:gsub ('%*%*', '\1'):gsub ('%*', '[^/]*'):gsub ('%?', '[^/]')
  return (out:gsub ('\1', '.*'))
end

---True when the path a plain pattern names fits a wildcard pattern. A pattern without `/`
---only looks at names, and one with `/` at the end of a path.
---@param pattern string
---@param path string
---@return boolean
function M.fits (pattern, path)
  local p, subject = plain (pattern), plain (path)
  if not p:find ('/', 1, true) then
    local name = subject:match ('([^/]*)$') or subject
    return name:find ('^' .. lua_body (p) .. '$') ~= nil
  end
  local body = lua_body (p:match ('^%*%*/(.*)$') or p)
  return subject:find ('^' .. body .. '$') ~= nil
    or subject:find ('/' .. body .. '$') ~= nil
end

---@param list string[]
---@param value string
local function add (list, value)
  for _, v in ipairs (list) do
    if v == value then
      return
    end
  end
  list[#list + 1] = value
end

---The `yaml.schemas` setting: each schema's address, and the globs of the files it checks.
---
---When the server finds several schemas for one file, the file must pass all of them. So a
---file that one association names in full, such as `.github/ISSUE_TEMPLATE/config.yml`, is
---left out of another schema's wildcard pattern that also fits it, such as
---`.github/ISSUE_TEMPLATE/*.yml`. The server reads a glob that starts with `!` as one to
---leave out.
---
---A schema association may hold the schema itself, or a function that builds it. The server
---reads schemas by address only, so those are left out.
---@param all { pattern: string, value: any }[]
---@return table<string, string[]>
function M.schemas (all)
  local associations = {} ---@type { pattern: string, value: string }[]
  for _, a in ipairs (all) do
    if type (a.value) == 'string' then
      associations[#associations + 1] = a
    end
  end
  local out = {} ---@type table<string, string[]>
  for _, a in ipairs (associations) do
    local url = tostring (a.value)
    if not out[url] then
      out[url] = {}
    end
    add (out[url], M.to_glob (a.pattern))
  end
  for _, a in ipairs (associations) do
    local url = tostring (a.value)
    if wild (a.pattern) then
      for _, other in ipairs (associations) do
        if
          tostring (other.value) ~= url
          and not wild (other.pattern)
          and M.fits (a.pattern, other.pattern)
        then
          add (out[url], '!' .. M.to_glob (other.pattern))
        end
      end
    end
  end
  return out
end

return M
