-- cargo_context: where the cursor is in a Cargo.toml, for completing crates. It finds a
-- crate's name being typed in a dependencies table, or its version. Nothing here calls the
-- host, so it runs anywhere.

---@class LangRust.CargoContext
---@field where 'name'|'version'
---@field crate? string The crate a version is for.
---@field word string What is typed so far, which completion replaces.
---@field from integer Where `word` starts in the line, counted from 0.

---@class LangRust.CargoContextModule
local M = {}

---The table a line sits in, without brackets, quotes or spaces, such as `dependencies` or
---`target.cfg(unix).dependencies`.
---@param lines string[]
---@param line integer Counted from 1.
---@return string?
local function table_at (lines, line)
  for i = line, 1, -1 do
    local inner = lines[i]:match ('^%s*%[%[?([^%]]*)%]')
    if inner then
      return (inner:gsub ('["\'%s]', ''))
    end
  end
  return nil
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

---What is being typed at a line counted from 0 and a column. Dependency lines are plain
---ASCII, so a column counts bytes.
---@param lines string[]
---@param line integer
---@param column integer
---@return LangRust.CargoContext?
function M.at (lines, line, column)
  local text = lines[line + 1]
  local tbl = text and table_at (lines, line)
  if not text or not tbl or text:match ('^%s*%[') then
    return nil
  end
  local before = text:sub (1, column)
  ---@param where 'name'|'version'
  ---@param word string
  ---@param crate? string
  ---@return LangRust.CargoContext
  local function result (where, word, crate)
    return { where = where, word = word, crate = crate, from = #before - #word }
  end
  -- A table for one crate, as in `[dependencies.serde]`.
  local crate_table = tbl:match ('dependencies%.([%w_%-]+)$')
  if crate_table then
    local typed = before:match ('^%s*version%s*=%s*"([^"]*)$')
    return typed and result ('version', typed, crate_table) or nil
  end
  if not tbl:match ('dependencies$') then
    return nil
  end
  local crate, typed = before:match ('^%s*([%w_%-]+)%s*=%s*"([^"]*)$')
  if not crate then
    crate, typed =
      before:match ('^%s*([%w_%-]+)%s*=%s*{.-version%s*=%s*"([^"]*)$')
  end
  if crate and typed then
    return result ('version', typed, crate)
  end
  local name = before:match ('^%s*([%w_%-]*)$')
  return name and result ('name', name) or nil
end

return M
