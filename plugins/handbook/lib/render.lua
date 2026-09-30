-- lib.render: the HTML the reader puts on screen, short of the Markdown itself, which the
-- app renders safely. Links between pages become addresses under INTERNAL before rendering,
-- since the safe renderer keeps only web links, and the reader tells them apart on a click.
-- Code blocks are colored here, with a Copy button. What a click means comes back through
-- `data-item`, as `link:<address>`, `copy:<n>` or `page:<id>`.

local highlight = require ('lib.highlight')
local page = require ('lib.page')

local M = {}

M.INTERNAL = 'https://handbook.proteus/'

---A heading and the HTML under it, up to the next heading.
---@class Handbook.Part
---@field heading? Handbook.Block
---@field html string

---@alias Handbook.Target
---| { kind: 'page', id: string, anchor?: string }
---| { kind: 'url', url: string }
---| { kind: 'copy', n: integer }

---Points the links between pages at INTERNAL, so they survive the safe renderer.
---@param md string
---@param source string The page's source, for links within it.
---@param name string The page's name, for `#anchor` links.
---@return string
function M.links (md, source, name)
  return page.map_links (md, function (target)
    local ref = page.resolve (target, source, name)
    if ref.url then
      return ref.url
    end
    return M.INTERNAL
      .. page.id_of (ref)
      .. (ref.anchor and ('#' .. ref.anchor) or '')
  end)
end

---Tidies what the safe renderer made: a link between pages shows no address on hover.
---@param html string
---@return string
function M.tidy (html)
  local prefix = M.INTERNAL:gsub ('%p', '%%%0')
  return (
    html:gsub ('%s*title="' .. prefix .. '[^"]*"', ''):gsub (
      'data%-item="link:' .. prefix,
      'data-page="1" data-item="link:' .. M.INTERNAL
    )
  )
end

---A code block with its language and a Copy button.
---@param code string
---@param lang string
---@param n integer Which block it is on the page, for the Copy button.
---@return string
function M.code (code, lang, n)
  local label = lang ~= '' and lang ~= 'text' and highlight.escape (lang) or ''
  return '<div class="hb-code"><div class="hb-code-head"><span>'
    .. label
    .. '</span><button class="hb-copy" data-item="copy:'
    .. n
    .. '" title="Copy the code">Copy</button></div><pre><code>'
    .. highlight.html (code, lang)
    .. '</code></pre></div>'
end

---What a click on an element with `data-item` asks for.
---@param item string?
---@return Handbook.Target?
function M.target (item)
  if not item then
    return nil
  end
  local n = item:match ('^copy:(%d+)$')
  if n then
    return {
      kind = 'copy',
      n = tonumber (n) --[[@as integer]],
    }
  end
  local id = item:match ('^page:(.*)$')
  if id then
    local pid, anchor = page.split_id (id)
    return { kind = 'page', id = pid, anchor = anchor }
  end
  local url = item:match ('^link:(.+)$')
  if not url then
    return nil
  end
  if url:sub (1, #M.INTERNAL) == M.INTERNAL then
    local pid, anchor = page.split_id (url:sub (#M.INTERNAL + 1))
    return { kind = 'page', id = pid, anchor = anchor }
  end
  return { kind = 'url', url = url }
end

---Groups a page's blocks for drawing: each heading starts a part, and the text and code
---after it join into one piece of HTML. `markdown` is the app's safe renderer.
---@param doc Handbook.Doc
---@param source string
---@param name string
---@param markdown fun(text: string): string
---@return Handbook.Part[] parts
---@return string[] codes Every code block's text, by its number in the Copy buttons.
function M.parts (doc, source, name, markdown)
  local parts = {} ---@type Handbook.Part[]
  local codes = {} ---@type string[]
  local html = {} ---@type string[]
  local current = { html = '' } ---@type Handbook.Part
  parts[1] = current

  local function close ()
    current.html = table.concat (html)
    html = {}
  end

  for _, block in ipairs (doc.blocks) do
    if block.kind == 'heading' then
      close ()
      current = { heading = block, html = '' }
      parts[#parts + 1] = current
    elseif block.kind == 'code' then
      codes[#codes + 1] = block.text
      html[#html + 1] = M.code (block.text, block.lang or '', #codes)
    else
      html[#html + 1] = M.tidy (markdown (M.links (block.text, source, name)))
    end
  end
  close ()
  if parts[1].html == '' and #parts > 1 then
    table.remove (parts, 1)
  end
  return parts, codes
end

---A heading as HTML, through the safe renderer so its code and emphasis show.
---@param block Handbook.Block
---@param source string
---@param name string
---@param markdown fun(text: string): string
---@return string
function M.heading (block, source, name, markdown)
  local level = math.min (block.level or 2, 6)
  return M.tidy (
    markdown (
      string.rep ('#', level) .. ' ' .. M.links (block.text, source, name)
    )
  )
end

return M
