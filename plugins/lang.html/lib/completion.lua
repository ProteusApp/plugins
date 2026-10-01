-- completion: what the plugin adds to the server's completion in `.html` and `.htm` files.
--
-- - `!` or `html:5` on a line of its own completes to an HTML5 page.
-- - After `</`, the first item closes the element that is still open.
--
-- The editor tells a plugin nothing as a key is typed, and does not say where the cursor
-- is. So the plugin cannot close a tag the moment `>` is typed, and offers the closing tag
-- as a completion instead.
--
-- The server also writes some items as snippets, such as `class="$1"`, even though the
-- client asks for plain text. Each plugin has its own copy of the client's modules, so this
-- one turns those items back into plain text in its copy of lsp.protocol.

local markup = require ('lib.markup') --[[@as LangHtml.Markup]]
local protocol = require ('lsp.protocol') --[[@as Lsp.Protocol]]

-- The protocol's number for an item whose text is a snippet.
local SNIPPET = 2

---@class LangHtml.CompletionModule
local M = {}

---Plain text for the server's snippet items, in this plugin's copy of lsp.protocol.
local function plain_items ()
  local convert = protocol.completion
  if type (convert) ~= 'function' then
    return
  end
  ---@param raw Lsp.CompletionItem
  ---@return Proteus.CompletionItem
  protocol.completion = function (raw)
    local item = convert (raw)
    local format = (raw --[[@as { insertTextFormat?: integer }]]).insertTextFormat
    if format == SNIPPET and item.insert then
      item.insert = markup.plain_snippet (item.insert)
    end
    return item
  end
end

---Answers a `completion` association: the skeleton, or the closing tag, or nothing.
---@param doc Proteus.DocInfo
---@param pos Proteus.CodePosition
---@param respond fun(result: Lsp.Extra?)
local function complete (doc, pos, respond)
  local before, line_before = markup.before (doc.text (), pos)
  local item, from = markup.skeleton (line_before)
  if not item then
    item, from = markup.closing (before, line_before)
  end
  if not item then
    respond (nil)
    return
  end
  respond ({ items = { item }, from = from })
end

---@param files Proteus.Files
function M.install (files)
  plain_items ()
  for _, pattern in ipairs ({ '*.html', '*.htm' }) do
    files.associate ({ kind = 'completion', pattern = pattern, value = complete })
  end
end

return M
