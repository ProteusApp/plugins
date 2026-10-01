-- package_context: where the cursor is in a package.json, for completing npm packages. It
-- finds a package's name being typed in one of the dependency lists, or its version.
-- Nothing here calls the host, so it runs anywhere.

-- The lists of packages in a package.json.
local LISTS = {
  dependencies = true,
  devDependencies = true,
  peerDependencies = true,
  optionalDependencies = true,
}

---@class LangJavascript.PackageContext
---@field where 'name'|'version'
---@field name? string The package a version is for.
---@field word string What is typed so far, which completion replaces.
---@field from integer Where `word` starts in the line, counted from 0.

---@class LangJavascript.PackageContextModule
local M = {}

---The keys of the objects open at the end of the text, outermost first. The top object has
---the key `''`. Strings are skipped, so a brace inside one does not count.
---@param text string
---@return string[]
function M.open_keys (text)
  local stack = {} ---@type string[]
  local last = nil ---@type string?
  local key = nil ---@type string?
  local i, n = 1, #text
  while i <= n do
    local c = text:sub (i, i)
    if c == '"' then
      local j = i + 1
      while j <= n do
        local d = text:sub (j, j)
        if d == '\\' then
          j = j + 1
        elseif d == '"' then
          break
        end
        j = j + 1
      end
      last = text:sub (i + 1, j - 1)
      i = j
    elseif c == ':' then
      key = last
    elseif c == '{' or c == '[' then
      stack[#stack + 1] = key or ''
      key = nil
    elseif c == '}' or c == ']' then
      stack[#stack] = nil
      key = nil
    elseif c == ',' then
      key = nil
    end
    i = i + 1
  end
  return stack
end

---@param text string
---@return string[]
function M.lines (text)
  local out = {} ---@type string[]
  for line in (text .. '\n'):gmatch ('([^\n]*)\n') do
    out[#out + 1] = (line:gsub ('\r$', ''))
  end
  return out
end

---What is being typed at a line counted from 0 and a column. Package names and versions are
---plain ASCII, so a column counts bytes.
---@param lines string[]
---@param line integer
---@param column integer
---@return LangJavascript.PackageContext?
function M.at (lines, line, column)
  local text = lines[line + 1]
  if not text then
    return nil
  end
  local before = text:sub (1, column)
  local head = table.concat (lines, '\n', 1, line)
  local keys = M.open_keys ((line > 0 and (head .. '\n') or '') .. before)
  -- A list of packages sits right inside the top object.
  if #keys ~= 2 or keys[1] ~= '' or not LISTS[keys[2]] then
    return nil
  end
  local name, typed = before:match ('^%s*"([^"]+)"%s*:%s*"([^"]*)$')
  if name then
    -- A range such as `^1.2` or `>=2` keeps its sign, and only the version is replaced.
    local version = typed:match ('^[%^~<>=%s]*(.*)$')
    return {
      where = 'version',
      name = name,
      word = version,
      from = #before - #version,
    }
  end
  local word = before:match ('^%s*"([^"]*)$')
  if word then
    return { where = 'name', word = word, from = #before - #word }
  end
  return nil
end

return M
