-- render: turns a Markdown file into the HTML of each part, with the app's safe renderer
-- passed in. A part whose text did not change since the last time reuses its HTML, so typing
-- in one section renders only that section again. It needs no `app`, so the tests load it
-- with a stand-in renderer.

local blocks = require ('lib.blocks') --[[@as LangMarkdown.BlocksModule]]
local links = require ('lib.links') --[[@as LangMarkdown.LinksModule]]

---A part of the page, ready to draw.
---@class LangMarkdown.Drawn
---@field line integer The line it starts on, from 1.
---@field anchor? string The `#link` name of its heading.
---@field html string

---@class LangMarkdown.Page
---@field parts LangMarkdown.Drawn[]
---@field lines integer How many lines the file has.

---@class LangMarkdown.RenderModule
local M = {}

---Renders a file. `cache` holds the HTML of the last render, by each part's Markdown, and
---the cache to keep for the next render comes back with the page.
---@param text string
---@param markdown fun(text: string): string The app's safe renderer.
---@param cache? table<string, string>
---@return LangMarkdown.Page page
---@return table<string, string> cache
function M.page (text, markdown, cache)
  cache = cache or {}
  local split = blocks.split (text, links.task_line)
  -- A reference definition may sit anywhere in the file, so every part gets them all.
  local refs = #split.refs > 0 and ('\n\n' .. table.concat (split.refs, '\n'))
    or ''
  local kept = {} ---@type table<string, string>
  local parts = {} ---@type LangMarkdown.Drawn[]
  for _, part in ipairs (split.parts) do
    local source = part.text .. refs
    local html = kept[source] or cache[source]
    if not html then
      local md, targets = links.rewrite (source)
      html = links.finish (markdown (md), targets)
    end
    kept[source] = html
    parts[#parts + 1] = { line = part.line, anchor = part.anchor, html = html }
  end
  return { parts = parts, lines = split.lines }, kept
end

return M
