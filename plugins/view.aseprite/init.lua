-- view.aseprite: opens Aseprite sprites in a tab, with their frames, tags and layers.
--
-- A .aseprite or .ase file opens in a web view page, which reads the file and draws it with
-- sharp square pixels. The sprite plays with each frame's own duration. A timeline under it
-- plays, pauses and steps through the frames, and picks a tag to play on its own. The layer
-- list at the side hides and shows each layer. Ctrl and the mouse wheel zoom around the
-- pointer, and a drag moves the sprite.
--
-- viewer.lua builds the tabs and sends each page its file. The page reads the file in
-- page/aseprite-parse.js and draws its frames in page/aseprite-render.js.

local formats = require ('formats') --[[@as table<string, boolean>]]
local viewer = require ('viewer') --[[@as table]]

-- How each color depth is called in the bar.
local MODES = { [32] = 'RGBA', [16] = 'Grayscale', [8] = 'Indexed' }

---The line of facts at the right of the bar, such as `64 × 64 px · 8 frames · RGBA · 3 KB`.
---@param state table
---@return string
local function describe (state)
  local parts = {} ---@type string[]
  if state.width and state.height then
    parts[#parts + 1] = string.format ('%d × %d px', state.width, state.height)
  end
  if state.frames then
    parts[#parts + 1] = state.frames == 1 and '1 frame'
      or string.format ('%d frames', state.frames)
  end
  if state.depth and MODES[state.depth] then
    parts[#parts + 1] = MODES[state.depth]
  end
  if state.bytes then
    parts[#parts + 1] = viewer.size_text (state.bytes)
  end
  if state.zoom then
    parts[#parts + 1] = viewer.zoom_text (state.zoom)
  end
  return table.concat (parts, ' · ')
end

---@type Proteus.Plugin
return {
  name = 'Aseprite viewer',
  description = 'Opens Aseprite sprites in a tab that plays their frames and tags, with zoom and a list of layers to hide and show.',
  version = '1.0.0',
  -- `files` for the `editor` service, which lets the plugin open sprites its own way, and for
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
    local ui = app.use ('ui')
    local commands = app.try_use ('commands')
    local settings = app.try_use ('settings')
    local files = app.try_use ('files')

    -- What the settings say, sent to each page as it opens.
    local config = { checkerboard = true, autoplay = true }

    ---Sends a page the settings.
    ---@param view Viewer.View
    local function send_config (view)
      view.post ({
        type = 'config',
        checkerboard = config.checkerboard,
        autoplay = config.autoplay,
      })
    end

    local service = viewer.start (app, {
      prefix = 'aseprite',
      extensions = formats,
      icon = 'film',
      page = 'page/index.html',
      noun = 'Sprite',
      build = function (view)
        ---@param icon string
        ---@param title string
        ---@param message table
        ---@return Proteus.El
        local function button (icon, title, message)
          return ui.button ({
            icon = icon,
            variant = 'ghost',
            title = title,
            onclick = function ()
              view.post (message)
            end,
          })
        end

        view.bar:append (
          button ('scan', 'Fit to the tab (0)', { type = 'zoom', to = 'fit' })
        )
        view.bar:append (ui.button ({
          '1:1',
          variant = 'ghost',
          title = 'Actual size (1)',
          onclick = function ()
            view.post ({ type = 'zoom', to = 'actual' })
          end,
        }))
        view.bar:append (
          button ('zoom-out', 'Zoom out (-)', { type = 'zoom', to = 'out' })
        )
        view.bar:append (
          button ('zoom-in', 'Zoom in (+)', { type = 'zoom', to = 'in' })
        )
        send_config (view)
      end,
      on_message = function (view, message)
        local state = view.state
        if message.type == 'view' then
          state.width = tonumber (message.width)
          state.height = tonumber (message.height)
          state.frames = tonumber (message.frames)
          state.depth = tonumber (message.depth)
          state.bytes = tonumber (message.bytes)
          state.zoom = tonumber (message.zoom)
          view.info (describe (state))
        elseif message.type == 'error' then
          view.info (
            tostring (message.error or 'The sprite did not load.'),
            true
          )
        end
      end,
    })

    ---Declares a setting and follows it. Without the settings service, the default holds.
    ---@param key string
    ---@param spec Proteus.SettingSpec
    ---@param fn fun(value: any)
    local function setting (key, spec, fn)
      if settings then
        settings.define (key, spec)
        settings.watch (key, fn)
      else
        fn (spec.default)
      end
    end

    setting ('aseprite.autoplay', {
      title = 'Play sprites as they open',
      type = 'boolean',
      default = true,
      description = 'Starts playing a sprite with more than one frame as soon as it opens.',
    }, function (value)
      config.autoplay = value ~= false
      service.each (send_config)
    end)
    setting ('aseprite.checkerboard', {
      title = 'Checkerboard behind sprites',
      type = 'boolean',
      default = true,
      description = 'Shows a checkerboard behind the clear parts of a sprite. Without it, they show the background of the tab.',
    }, function (value)
      config.checkerboard = value ~= false
      service.each (send_config)
    end)

    if files then
      for ext in pairs (formats) do
        files.associate ({
          kind = 'icon',
          pattern = '*.' .. ext,
          value = { icon = 'film', color = 'var(--syn-function)' },
        })
      end
    end

    if commands then
      local function is_open ()
        return service.active () ~= nil
      end

      ---@param id string
      ---@param title string
      ---@param icon string
      ---@param message table
      local function page_command (id, title, icon, message)
        commands.register ({
          id = id,
          category = 'Sprite',
          title = title,
          icon = icon,
          when = is_open,
          run = function ()
            local view = service.active ()
            if view then
              view.post (message)
            end
          end,
        })
      end

      page_command (
        'aseprite.play',
        'Play or Pause the Sprite',
        'play',
        { type = 'play' }
      )
      page_command (
        'aseprite.next_frame',
        'Next Frame',
        'skip-forward',
        { type = 'step', by = 1 }
      )
      page_command (
        'aseprite.previous_frame',
        'Previous Frame',
        'skip-back',
        { type = 'step', by = -1 }
      )
      page_command (
        'aseprite.fit',
        'Fit the Sprite to the Tab',
        'scan',
        { type = 'zoom', to = 'fit' }
      )
      page_command (
        'aseprite.actual_size',
        'Show the Sprite at Actual Size',
        'square',
        { type = 'zoom', to = 'actual' }
      )
      page_command (
        'aseprite.zoom_in',
        'Zoom In on the Sprite',
        'zoom-in',
        { type = 'zoom', to = 'in' }
      )
      page_command (
        'aseprite.zoom_out',
        'Zoom Out of the Sprite',
        'zoom-out',
        { type = 'zoom', to = 'out' }
      )
    end
  end,
}
