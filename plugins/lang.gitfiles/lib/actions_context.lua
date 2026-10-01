-- actions_context: where the cursor is in a GitHub workflow or action file, for completion.
-- It finds an action being named after `uses:`, its version after `@`, and a name inside a
-- `${{ }}` expression or an `if:` condition. It also finds the step and job ids a file
-- defines. Nothing here calls the host, so it runs anywhere.

---@class LangGitfiles.ActionsContext
---@field where 'action'|'version'|'expression'
---@field word string What is typed so far, which completion replaces.
---@field from integer Where `word` starts in the line, counted from 0.
---@field repo? string The repository a version is for, such as `actions/checkout`.
---@field object? string In an expression, the names before the last dot, such as `github` or `steps.build`.

---@class LangGitfiles.ActionsContextModule
local M = {}

---@param text string
---@return string[]
function M.lines (text)
  local out = {} ---@type string[]
  for line in (text .. '\n'):gmatch ('([^\n]*)\n') do
    out[#out + 1] = (line:gsub ('\r$', ''))
  end
  return out
end

---Where the expression around the cursor starts in `before`, counted from 1, or nil when the
---cursor is not in one. It is inside the last `${{` that has no `}}` after it yet, or after
---`if:`, whose value is an expression without the braces.
---@param before string The line up to the cursor.
---@return integer?
local function expression_start (before)
  local open = nil ---@type integer?
  local at = 1
  while true do
    local _, last = before:find ('${{', at, true)
    if not last then
      break
    end
    open, at = last, last + 1
  end
  if open then
    if before:find ('}}', open + 1, true) then
      return nil
    end
    return open + 1
  end
  local condition = before:match ('^%s*%-?%s*if:%s*')
  return condition and #condition + 1 or nil
end

---What is typed at a line counted from 0 and a column. Workflow lines that matter here are
---plain ASCII, so a column counts bytes.
---@param lines string[]
---@param line integer
---@param column integer
---@return LangGitfiles.ActionsContext?
function M.at (lines, line, column)
  local text = lines[line + 1]
  if not text then
    return nil
  end
  local before = text:sub (1, column)
  if before:match ('^%s*#') then
    return nil
  end

  local head, typed = before:match ('^(%s*%-?%s*uses:%s*["\']?)(.*)$')
  if head then
    -- A version after `@`, for `owner/repo` or a path inside it.
    local repo, version =
      typed:match ('^([%w_%.%-]+/[%w_%.%-]+)[%w_%.%-/]*@([%w_%.%-/]*)$')
    if repo then
      return {
        where = 'version',
        repo = repo,
        word = version,
        from = #before - #version,
      }
    end
    -- An action in this repository starts with `./`, and a Docker image with `docker://`.
    if typed:match ('^[%w_%-][%w_%.%-/]*$') or typed == '' then
      return { where = 'action', word = typed, from = #head }
    end
    return nil
  end

  local start = expression_start (before)
  if not start then
    return nil
  end
  local expr = before:sub (start)
  -- Inside a quoted text there is nothing to complete. Expressions quote with `'`.
  local _, quotes = expr:gsub ("'", '')
  if quotes % 2 == 1 then
    return nil
  end
  local path = expr:match ('([%a_][%w_%.%-]*)$') or ''
  local object, word = path:match ('^(.*)%.([^%.]*)$')
  if not object then
    word = path
  end
  if object and (object == '' or object:find ('%.%.')) then
    return nil
  end
  return {
    where = 'expression',
    word = word,
    object = object,
    from = #before - #word,
  }
end

---The ids of the steps in a file, in order, each once.
---@param lines string[]
---@return string[]
function M.step_ids (lines)
  local out, seen = {}, {} ---@type string[], table<string, true>
  for _, line in ipairs (lines) do
    local id = line:match ('^%s*%-?%s*id:%s*["\']?([%w_%-]+)')
    if id and not seen[id] then
      seen[id] = true
      out[#out + 1] = id
    end
  end
  return out
end

---The ids of the jobs under `jobs:`, in order.
---@param lines string[]
---@return string[]
function M.job_ids (lines)
  local out = {} ---@type string[]
  local inside, indent = false, nil ---@type boolean, integer?
  for _, line in ipairs (lines) do
    local blank = line:match ('^%s*$') or line:match ('^%s*#')
    if line:match ('^jobs:%s*$') or line:match ('^jobs:%s*#') then
      inside, indent = true, nil
    elseif not blank and inside then
      local spaces, key = line:match ('^(%s*)([%w_%-]+):')
      if #line:match ('^%s*') == 0 then
        inside = false
      elseif spaces and (indent == nil or #spaces == indent) then
        indent = #spaces
        out[#out + 1] = key
      end
    end
  end
  return out
end

---The tags of a repository, newest version first. A tag such as `v4` comes before `v4.2.1`,
---since it follows the newest release of that version. Tags that are not versions go last.
---@param names string[]
---@return string[]
function M.sort_tags (names)
  local versions, others = {}, {} ---@type table[], string[]
  for _, name in ipairs (names) do
    local major, minor, patch, rest =
      name:match ('^[vV]?(%d+)%.?(%d*)%.?(%d*)(.*)$')
    if major then
      versions[#versions + 1] = {
        name = name,
        major = tonumber (major),
        minor = tonumber (minor) or -1,
        patch = tonumber (patch) or -1,
        rest = rest,
      }
    else
      others[#others + 1] = name
    end
  end
  ---A missing part sorts first, then the larger number.
  ---@param a integer
  ---@param b integer
  ---@return boolean
  local function part_first (a, b)
    if a < 0 or b < 0 then
      return a < b
    end
    return a > b
  end
  table.sort (versions, function (a, b)
    if a.major ~= b.major then
      return a.major > b.major
    end
    if a.minor ~= b.minor then
      return part_first (a.minor, b.minor)
    end
    if a.patch ~= b.patch then
      return part_first (a.patch, b.patch)
    end
    if (a.rest == '') ~= (b.rest == '') then
      return a.rest == ''
    end
    return a.name > b.name
  end)
  local out = {} ---@type string[]
  for _, v in ipairs (versions) do
    out[#out + 1] = v.name
  end
  for _, name in ipairs (others) do
    out[#out + 1] = name
  end
  return out
end

return M
