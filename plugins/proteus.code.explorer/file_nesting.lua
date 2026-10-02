-- file_nesting: works out which files of one folder the tree draws under another file, such
-- as package-lock.json under package.json. It calls no host function, so the tests reach it.
--
-- The setting maps a name pattern for the file on top to the name patterns of the files under
-- it. `*` matches any run of characters and `?` matches one. The first `*` in the top pattern
-- is kept, and `${capture}` in a pattern below stands for what it matched. So `*.ts` with
-- `${capture}.js` puts `app.js` under `app.ts`.
--
-- Nesting goes one level deep. A file that another file wants under it never holds files of
-- its own, so `app.js.map` goes under `app.ts` rather than under `app.js`.

---One entry of the setting, ready to match.
---@class CodeExplorer.NestRule
---@field top string An anchored Lua pattern for the file on top.
---@field captures boolean True when `top` captures what its first `*` matched.
---@field under string[] Name patterns for the files under it, `${capture}` and all.

---@class CodeExplorer.Nesting
local M = {}

local CAPTURE = '${capture}'

---A name pattern as an unanchored Lua pattern.
---@param glob string
---@return string
local function body (glob)
  return (
    glob
      :gsub ('[%^%$%(%)%%%.%[%]%+%-]', '%%%0')
      :gsub ('%*', '.*')
      :gsub ('%?', '.')
  )
end

---The Lua pattern for a top pattern, which captures what its first `*` matches.
---@param glob string
---@return string pattern
---@return boolean captures
local function top_pattern (glob)
  local star = glob:find ('*', 1, true)
  if not star then
    return '^' .. body (glob) .. '$', false
  end
  return '^' .. body (glob:sub (1, star - 1)) .. '(.*)' .. body (
    glob:sub (star + 1)
  ) .. '$',
    true
end

---The pieces of a pattern below, split where `${capture}` goes.
---@param glob string
---@return string[]
local function pieces (glob)
  local out = {} ---@type string[]
  local from = 1
  while true do
    local at = glob:find (CAPTURE, from, true)
    if not at then
      out[#out + 1] = glob:sub (from)
      return out
    end
    out[#out + 1] = glob:sub (from, at - 1)
    from = at + #CAPTURE
  end
end

---Reads the setting's value into rules, sorted by the top pattern. An entry counts when its
---value is a list of patterns or one string of them split by commas. Patterns with a `/` are
---left out, since nesting only looks at names.
---@param value any
---@param fold? boolean Matches names without case, as Windows compares them.
---@return CodeExplorer.NestRule[]
function M.rules (value, fold)
  local out = {} ---@type CodeExplorer.NestRule[]
  if type (value) ~= 'table' then
    return out
  end
  local tops = {} ---@type string[]
  for k in pairs (value) do
    if type (k) == 'string' and k ~= '' and not k:find ('/', 1, true) then
      tops[#tops + 1] = k
    end
  end
  table.sort (tops)
  for _, top in ipairs (tops) do
    local raw = value[top]
    local list = {} ---@type string[]
    if type (raw) == 'string' then
      for piece in raw:gmatch ('[^,]+') do
        list[#list + 1] = piece
      end
    elseif type (raw) == 'table' then
      for _, v in ipairs (raw) do
        if type (v) == 'string' then
          list[#list + 1] = v
        end
      end
    end
    local under = {} ---@type string[]
    for _, v in ipairs (list) do
      local name = v:match ('^%s*(.-)%s*$') or ''
      if name ~= '' and not name:find ('/', 1, true) then
        under[#under + 1] = fold and name:lower () or name
      end
    end
    if #under > 0 then
      local pattern, captures = top_pattern (fold and top:lower () or top)
      out[#out + 1] = { top = pattern, captures = captures, under = under }
    end
  end
  return out
end

---Which of `names`, the files of one folder, go under which. Each file on top maps to the
---files under it, in the order of `names`. A file two files want goes under the first one.
---@param names string[]
---@param rules CodeExplorer.NestRule[]
---@param fold? boolean Compares names without case, as Windows does.
---@return table<string, string[]>
function M.group (names, rules, fold)
  local out = {} ---@type table<string, string[]>
  if #rules == 0 then
    return out
  end
  local keys = {} ---@type string[]
  local index = {} ---@type table<string, integer>
  for i, n in ipairs (names) do
    keys[i] = fold and n:lower () or n
    index[keys[i]] = index[keys[i]] or i
  end

  ---Adds the files a pattern below names, for one top file, to `found`.
  ---@param glob string
  ---@param capture string
  ---@param self integer
  ---@param found table<integer, boolean>
  local function collect (glob, capture, self, found)
    local parts = pieces (glob)
    local exact = not glob:find ('[%*%?]')
    if exact then
      local j = index[table.concat (parts, capture)]
      if j and j ~= self then
        found[j] = true
      end
      return
    end
    -- A literal capture inside a Lua pattern escapes every character that means something.
    local literal = capture:gsub ('[%^%$%(%)%%%.%[%]%*%+%-%?]', '%%%0')
    local bodies = {} ---@type string[]
    for i, p in ipairs (parts) do
      bodies[i] = body (p)
    end
    local pattern = '^' .. table.concat (bodies, literal) .. '$'
    for j, other in ipairs (keys) do
      if j ~= self and other:find (pattern) then
        found[j] = true
      end
    end
  end

  local wants = {} ---@type table<integer, table<integer, boolean>>
  local wanted = {} ---@type table<integer, boolean>
  for i, key in ipairs (keys) do
    local found = {} ---@type table<integer, boolean>
    for _, rule in ipairs (rules) do
      local hit = key:match (rule.top)
      if hit then
        local capture = rule.captures and hit or ''
        for _, glob in ipairs (rule.under) do
          collect (glob, capture, i, found)
        end
      end
    end
    if next (found) then
      wants[i] = found
      for j in pairs (found) do
        wanted[j] = true
      end
    end
  end

  local taken = {} ---@type table<integer, boolean>
  for i, name in ipairs (names) do
    local found = wants[i]
    if found and not wanted[i] then
      local kids = {} ---@type string[]
      for j, kid in ipairs (names) do
        if found[j] and not taken[j] then
          taken[j] = true
          kids[#kids + 1] = kid
        end
      end
      if #kids > 0 then
        out[name] = kids
      end
    end
  end
  return out
end

return M
