-- lib.search: finds pages and headings for a query. Each page and each heading is an entry
-- with a label and the text under it. A match in a label counts for more than a match in
-- the text, and a whole-label match counts most, so `commands` finds the Commands page
-- before a page that mentions commands.

local page = require ('lib.page')

local M = {}

---@class Handbook.Entry
---@field id string The page's id.
---@field anchor? string The heading's anchor, or nil for the page itself.
---@field label string What the result shows, such as `Commands` or `register`.
---@field context string Where it is, such as the page's title or section.
---@field key string The label and keywords in lower case.
---@field body string The text under it, as written.
---@field lower string The text under it, in lower case.
---@field rank integer Pages first, then headings in page order.

---@class Handbook.Hit
---@field id string
---@field anchor? string
---@field label string
---@field context string
---@field snippet? string A line of text around the match, for a match in the text.
---@field score number

---@class Handbook.IndexPage
---@field id string
---@field title string
---@field section string
---@field keywords? string
---@field doc Handbook.Doc

---@param text string
---@return string
local function flat (text)
  return (text:gsub ('%s+', ' '))
end

---Builds the entries for some pages.
---@param pages Handbook.IndexPage[]
---@return Handbook.Entry[]
function M.index (pages)
  local entries = {} ---@type Handbook.Entry[]
  local rank = 0 ---@type integer
  for _, p in ipairs (pages) do
    local parts = {} ---@type string[]
    local head ---@type Handbook.Entry?
    local page_entry = {
      id = p.id,
      label = p.title,
      context = p.section,
      key = (p.title .. ' ' .. (p.keywords or '') .. ' ' .. p.id):lower (),
      body = '',
      lower = '',
      rank = rank,
    }
    rank = rank + 1
    entries[#entries + 1] = page_entry

    local function close ()
      local text = flat (table.concat (parts, ' '))
      parts = {}
      local target = head or page_entry
      target.body = target.body .. text
      target.lower = target.body:lower ()
    end

    for _, block in ipairs (p.doc.blocks) do
      if block.kind == 'heading' and block.level > 1 then
        close ()
        local label = page.plain (block.text)
        head = {
          id = p.id,
          anchor = block.anchor,
          label = label,
          context = p.title,
          key = label:lower (),
          body = '',
          lower = '',
          rank = rank,
        }
        rank = (rank + 1) --[[@as integer]]
        entries[#entries + 1] = head
      elseif block.kind ~= 'heading' then
        parts[#parts + 1] = block.kind == 'text'
            and page.plain (block.text):gsub ('|', ' '):gsub ('%-%-%-+', ' ')
          or block.text
      end
    end
    close ()
  end
  return entries
end

---@param text string
---@param words string[]
---@return boolean
local function has_all (text, words)
  for _, w in ipairs (words) do
    if not text:find (w, 1, true) then
      return false
    end
  end
  return true
end

---A short piece of `body` around where `word` first appears.
---@param body string
---@param lower string
---@param word string
---@return string
local function snippet (body, lower, word)
  local at = lower:find (word, 1, true) or 1
  local from = math.max (1, at - 50)
  local to = math.min (#body, at + #word + 70)
  -- Keep whole words at both ends.
  if from > 1 then
    from = (body:find (' ', from, true) or from) + 1
  end
  if to < #body then
    local back = body:sub (from, to):match ('^.*() ')
    to = back and (from + back - 2) or to
  end
  local s = body:sub (from, to)
  return (from > 1 and '… ' or '') .. s .. (to < #body and ' …' or '')
end

---Scores one entry, or returns nil when it does not match.
---@param e Handbook.Entry
---@param q string
---@param words string[]
---@return number? score
---@return boolean in_body
local function score (e, q, words)
  local label = e.label:lower ()
  if label == q then
    return 100, false
  end
  if label:sub (1, #q) == q then
    return 80 - #label / 100, false
  end
  local at = label:find (q, 1, true)
  if at then
    local edge = at == 1 or label:sub (at - 1, at - 1):match ('[%s%.:_(-]')
    return (edge and 70 or 60) - #label / 100, false
  end
  if has_all (e.key, words) then
    return 40 - #label / 100, false
  end
  if has_all (e.lower, words) then
    local count = 0
    local pattern = words[1]:gsub ('%p', '%%%0')
    for _ in e.lower:gmatch (pattern) do
      count = count + 1
    end
    return 10 + math.min (count, 10) / 2, true
  end
  return nil, false
end

---Finds the best entries for a query.
---@param entries Handbook.Entry[]
---@param query string
---@param limit? integer 50 when nil.
---@return Handbook.Hit[]
function M.find (entries, query, limit)
  local q = query:lower ():gsub ('^%s+', ''):gsub ('%s+$', ''):gsub ('%s+', ' ')
  if q == '' then
    return {}
  end
  local words = {} ---@type string[]
  for w in q:gmatch ('%S+') do
    words[#words + 1] = w
  end
  local found = {} ---@type { e: Handbook.Entry, score: number, body: boolean }[]
  for _, e in ipairs (entries) do
    local s, in_body = score (e, q, words)
    if s then
      -- A page ranks just above its own headings when both match as well.
      found[#found + 1] =
        { e = e, score = s + (e.anchor and 0 or 0.5), body = in_body }
    end
  end
  table.sort (found, function (a, b)
    if a.score ~= b.score then
      return a.score > b.score
    end
    return a.e.rank < b.e.rank
  end)
  local hits = {} ---@type Handbook.Hit[]
  for i = 1, math.min (#found, limit or 50) do
    local f = found[i]
    hits[i] = {
      id = f.e.id,
      anchor = f.e.anchor,
      label = f.e.label,
      context = f.e.context,
      snippet = f.body and snippet (f.e.body, f.e.lower, words[1]) or nil,
      score = f.score,
    }
  end
  return hits
end

return M
