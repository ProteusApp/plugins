-- view.fonts: opens font files in a tab that shows the font, instead of the text editor.
--
-- TTF, OTF, TTC, WOFF and WOFF2 files open in a web view page. The page loads the font and
-- shows its names and sizes, a sample to type in, the sample at many sizes, the alphabet and
-- digits, and every character the font has. A collection of fonts, such as a TTC file, has a
-- picker for each font in it.
--
-- viewer.lua builds the tabs and sends each page its file. page/font-parse.js reads the
-- font's tables, and page/fonts.js shows them.

local formats = require ('formats') --[[@as table<string, string>]]
local viewer = require ('viewer') --[[@as table]]

local SAMPLE = 'The quick brown fox jumps over the lazy dog.'

---The line of facts at the right of the bar, such as `Arial Regular · TrueType · 4651 glyphs`.
---@param state table
---@return string
local function describe (state)
  local parts = {} ---@type string[]
  local name = table.concat ({ state.family or '', state.style or '' }, ' ')
  name = name:gsub ('^%s+', ''):gsub ('%s+$', '')
  if name ~= '' then
    parts[#parts + 1] = name
  end
  if state.format then
    parts[#parts + 1] = state.format
  end
  if state.faces and state.faces > 1 then
    parts[#parts + 1] = string.format ('%d fonts', state.faces)
  end
  if state.glyphs then
    parts[#parts + 1] = state.glyphs == 1 and '1 glyph'
      or string.format ('%d glyphs', state.glyphs)
  end
  if state.bytes then
    parts[#parts + 1] = viewer.size_text (state.bytes)
  end
  return table.concat (parts, ' · ')
end

---@type Proteus.Plugin
return {
  name = 'Font viewer',
  description = 'Opens TTF, OTF, TTC, WOFF and WOFF2 fonts in a tab with their names, a sample to type in, a range of sizes and every character they have.',
  version = '1.0.0',
  -- `files` for the `editor` service, which lets the plugin open fonts its own way, and for
  -- sending a file on disk to the page.
  permissions = { 'files' },
  requires = {
    proteus = '>=0.3.0',
    features = { 'permissions', 'webview', 'webview-disk' },
  },
  depends = { 'proteus.lib.ui', 'proteus.ui.tabs', 'proteus.editor.core' },
  optional = {
    'proteus.core.commands',
    'proteus.core.settings',
    'proteus.core.themes',
    'proteus.core.icons',
    'proteus.core.files',
  },
  activate = function (app)
    local settings = app.try_use ('settings')
    local files = app.try_use ('files')

    local sample = SAMPLE

    ---Sends a page the sample text.
    ---@param view Viewer.View
    local function send_config (view)
      view.post ({ type = 'config', sample = sample })
    end

    local service = viewer.start (app, {
      prefix = 'fonts',
      extensions = formats,
      icon = 'type',
      page = 'page/index.html',
      noun = 'Font',
      build = send_config,
      on_message = function (view, message)
        local state = view.state
        if message.type == 'view' then
          state.family = type (message.family) == 'string' and message.family
            or nil
          state.style = type (message.style) == 'string' and message.style
            or nil
          state.format = type (message.format) == 'string' and message.format
            or nil
          state.faces = tonumber (message.faces)
          state.glyphs = tonumber (message.glyphs)
          state.bytes = tonumber (message.bytes)
          view.info (describe (state))
        elseif message.type == 'error' then
          view.info (tostring (message.error or 'The font did not load.'), true)
        end
      end,
    })

    if settings then
      settings.define ('fonts.sample', {
        title = 'Font sample text',
        type = 'string',
        default = SAMPLE,
        description = 'The text a font shows when it opens, at the top and at each size.',
      })
      settings.watch ('fonts.sample', function (value)
        sample = type (value) == 'string' and value ~= '' and value or SAMPLE
        service.each (send_config)
      end)
    end

    if files then
      for ext in pairs (formats) do
        files.associate ({
          kind = 'icon',
          pattern = '*.' .. ext,
          value = { icon = 'type', color = 'var(--syn-keyword)' },
        })
      end
    end
  end,
}
