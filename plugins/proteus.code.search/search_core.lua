-- search_core: the parts of Search that call no host function, so the tests reach them. It
-- reads the patterns typed into the boxes, groups matches by file, keeps the search history,
-- walks the rows of the results, and replaces one match in a file's text.

---All the matches in one file.
---@class CodeSearch.File
---@field path string From the project folder.
---@field matches Proteus.SearchMatch[]

---A row of the results: a file, or a match inside it.
---@class CodeSearch.Row
---@field key string `f:<file>` or `m:<file>:<match>`, by their places in the list.
---@field fi integer
---@field mi? integer

---@class CodeSearch.Core
local M = {}

-- A line of the results shows this much of a match, as the host cuts it.
M.HIT_CHARS = 160

---Splits a list of glob patterns typed with commas. A plain folder name, such as `src`, means
---everything inside it.
---@param text string
---@return string[]
function M.globs (text)
  local out = {} ---@type string[]
  for part in text:gmatch ('[^,]+') do
    local glob = part:match ('^%s*(.-)%s*$') --[[@as string]]
    glob = glob:gsub ('\\', '/'):gsub ('^%./', '')
    if glob ~= '' then
      if not glob:find ('[%*%?%[]') then
        glob = glob:gsub ('/$', '') .. '/**'
      end
      out[#out + 1] = glob
    end
  end
  return out
end

---Groups matches by file, keeping the order they came in.
---@param matches Proteus.SearchMatch[]
---@return CodeSearch.File[]
function M.by_file (matches)
  local out = {} ---@type CodeSearch.File[]
  local last = nil ---@type CodeSearch.File?
  for _, m in ipairs (matches) do
    if not last or last.path ~= m.path then
      last = { path = m.path, matches = {} }
      out[#out + 1] = last
    end
    last.matches[#last.matches + 1] = m
  end
  return out
end

---What the status line says about a search's result.
---@param count integer
---@param files integer
---@param truncated boolean
---@return string
function M.summary (count, files, truncated)
  if count == 0 then
    return 'No results.'
  end
  return (truncated and 'The first ' or '')
    .. count
    .. (count == 1 and ' result' or ' results')
    .. ' in '
    .. files
    .. (files == 1 and ' file' or ' files')
    .. (truncated and '. Narrow the search to see the rest.' or '.')
end

---The history with `text` at the front, each search once, at most `max` long.
---@param history string[]
---@param text string
---@param max integer
---@return string[]
function M.remember (history, text, max)
  local out = { text } ---@type string[]
  for _, h in ipairs (history) do
    if h ~= text and #out < max then
      out[#out + 1] = h
    end
  end
  return out
end

---A path from the folder as an include pattern that matches that one file, from the root,
---with the characters a pattern reads written plainly.
---@param rel string
---@return string
function M.exact_glob (rel)
  local out = rel:gsub ('[\\%*%?%[%]]', '\\%0')
  out = out:gsub (' $', '\\ ')
  return '/' .. out
end

---Every row of the results, top to bottom. A file folded shut shows no matches.
---@param files CodeSearch.File[]
---@param closed table<string, boolean> Paths of the files folded shut.
---@return CodeSearch.Row[]
function M.rows (files, closed)
  local out = {} ---@type CodeSearch.Row[]
  for fi, f in ipairs (files) do
    out[#out + 1] = { key = 'f:' .. fi, fi = fi }
    if not closed[f.path] then
      for mi = 1, #f.matches do
        out[#out + 1] = { key = 'm:' .. fi .. ':' .. mi, fi = fi, mi = mi }
      end
    end
  end
  return out
end

---The match after or before the one at `fi`, `mi`, going round at the ends. Files folded
---shut count too. From no match, it is the first or the last.
---@param files CodeSearch.File[]
---@param fi integer?
---@param mi integer?
---@param step 1|-1
---@return integer? fi
---@return integer? mi
function M.next_match (files, fi, mi, step)
  local all = {} ---@type integer[][]
  local at = nil ---@type integer?
  for i, f in ipairs (files) do
    for j = 1, #f.matches do
      all[#all + 1] = { i, j }
      if i == fi and j == mi then
        at = #all
      end
    end
  end
  if #all == 0 then
    return nil, nil
  end
  local n = 1 ---@type integer
  if not at then
    -- From a file row, the next match is its first one.
    n = step == 1 and 1 or #all
    if fi then
      for k, pair in ipairs (all) do
        if pair[1] >= fi then
          n = step == 1 and k or math.max (k - 1, 1)
          break
        end
      end
    end
  else
    n = math.floor ((at - 1 + step) % #all) + 1
  end
  return all[n][1], all[n][2]
end

---The byte where a column counted in UTF-16 units starts, as the host counts `col`, or nil
---past the end of the line.
---@param line string
---@param col integer From 1.
---@return integer?
function M.byte_at (line, col)
  local units = 1
  for pos, code in utf8.codes (line) do
    if units == col then
      return pos
    elseif units > col then
      return nil
    end
    units = units + (code >= 0x10000 and 2 or 1)
  end
  return units == col and #line + 1 or nil
end

---The text with one match replaced by what it becomes, `m.with`. Nil and the reason when the
---text no longer holds the match where the search found it, or the match was too long to show
---whole.
---@param text string
---@param m Proteus.SearchMatch
---@return string? text
---@return string? problem
function M.replace_one (text, m)
  if type (m.with) ~= 'string' then
    return nil, 'Type what to replace it with first.'
  end
  if utf8.len (m.hit) == M.HIT_CHARS + 1 and m.hit:sub (-3) == '…' then
    return nil,
      'This match is too long to replace on its own. Replace All in File replaces it.'
  end
  local stale = 'The file changed since the search. Search again, then replace.'
  local line_no, start = 1, 1
  while line_no < m.line do
    local nl = text:find ('\n', start, true)
    if not nl then
      return nil, stale
    end
    start = nl + 1
    line_no = line_no + 1
  end
  local stop = text:find ('\n', start, true)
  local line = text:sub (start, (stop or #text + 1) - 1)
  local at = M.byte_at (line, m.col)
  if not at or line:sub (at, at + #m.hit - 1) ~= m.hit then
    return nil, stale
  end
  local pos = start + at - 1
  return text:sub (1, pos - 1) .. m.with .. text:sub (pos + #m.hit)
end

return M
