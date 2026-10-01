-- view.images: opens pictures in a tab of their own instead of the text editor.
--
-- PNG, JPEG, GIF, WebP, AVIF, BMP, ICO and SVG files open in a web view page, which shows
-- the picture over a checkerboard, so clear parts stay visible. The picture starts fitted to
-- the tab. Ctrl and the mouse wheel zoom around the pointer, and a drag moves it. Small
-- pictures, such as pixel art, show with sharp square pixels. Animated GIF and WebP files
-- play. An SVG file can also open as text, for editing.
--
-- viewer.lua builds the tabs and sends each page its file. page/images.js draws.

local formats = require ('formats') --[[@as table<string, string>]]
local viewer = require ('viewer') --[[@as table]]

---The line of facts at the right of the bar, such as `512 × 512 px · 34 KB · 200%`.
---@param state table
---@return string
local function describe (state)
  local parts = {} ---@type string[]
  if state.width and state.height then
    parts[#parts + 1] = string.format ('%d × %d px', state.width, state.height)
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
  name = 'Image viewer',
  description = 'Opens PNG, JPEG, GIF, WebP, AVIF, BMP, ICO and SVG files in a tab with zoom, panning and a checkerboard behind clear parts.',
  version = '1.0.0',
  -- `files` for the `editor` service, which lets the plugin open pictures its own way, and
  -- for sending a file on disk to the page.
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
    local editor = app.use ('editor')
    local commands = app.try_use ('commands')
    local settings = app.try_use ('settings')
    local files = app.try_use ('files')

    -- What the settings say, sent to each page as it opens.
    local config = { checkerboard = true, pixelated = 'auto' }

    ---Sends a page the settings.
    ---@param view Viewer.View
    local function send_config (view)
      view.post ({
        type = 'config',
        checkerboard = config.checkerboard,
        pixelated = config.pixelated,
      })
    end

    local service = viewer.start (app, {
      prefix = 'images',
      extensions = formats,
      icon = 'image',
      page = 'page/index.html',
      noun = 'Image',
      build = function (view)
        local state = view.state

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
        view.bar:append (ui.span ({ class = 'vw-sep' }))
        state.pixel_button = button (
          'grid-3x3',
          'Sharp square pixels, for pixel art (P)',
          { type = 'pixelated' }
        )
        view.bar:append (state.pixel_button)
        if viewer.extension (view.path) == 'svg' then
          view.bar:append (ui.span ({ class = 'vw-sep' }))
          view.bar:append (ui.button ({
            'View as Text',
            icon = 'file-code',
            variant = 'ghost',
            title = 'Open the SVG in the code editor',
            onclick = function ()
              editor.open (view.path)
            end,
          }))
        end
        send_config (view)
      end,
      on_message = function (view, message)
        local state = view.state
        if message.type == 'view' then
          state.width = tonumber (message.width)
          state.height = tonumber (message.height)
          state.bytes = tonumber (message.bytes)
          state.zoom = tonumber (message.zoom)
          state.pixel_button:class ('vw-on', message.pixelated == true)
          state.pixel_button:set ('disabled', message.vector == true)
          view.info (describe (state))
        elseif message.type == 'error' then
          view.info (
            tostring (message.error or 'The picture did not load.'),
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

    setting ('images.checkerboard', {
      title = 'Checkerboard behind pictures',
      type = 'boolean',
      default = true,
      description = 'Shows a checkerboard behind the clear parts of a picture. Without it, they show the background of the tab.',
    }, function (value)
      config.checkerboard = value ~= false
      service.each (send_config)
    end)
    setting ('images.pixelated', {
      title = 'Sharp square pixels',
      type = 'select',
      options = { 'auto', 'always', 'never' },
      default = 'auto',
      description = 'Draws pixels as sharp squares when zoomed in, rather than smooth. Auto does so for pictures up to 256 pixels across, such as pixel art.',
    }, function (value)
      config.pixelated = (value == 'always' or value == 'never') and value
        or 'auto'
      service.each (send_config)
    end)

    if files then
      for ext in pairs (formats) do
        files.associate ({
          kind = 'icon',
          pattern = '*.' .. ext,
          value = { icon = 'image', color = 'var(--syn-constant)' },
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
          category = 'Image',
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
        'images.fit',
        'Fit the Image to the Tab',
        'scan',
        { type = 'zoom', to = 'fit' }
      )
      page_command (
        'images.actual_size',
        'Show the Image at Actual Size',
        'square',
        { type = 'zoom', to = 'actual' }
      )
      page_command (
        'images.zoom_in',
        'Zoom In on the Image',
        'zoom-in',
        { type = 'zoom', to = 'in' }
      )
      page_command (
        'images.zoom_out',
        'Zoom Out of the Image',
        'zoom-out',
        { type = 'zoom', to = 'out' }
      )
      page_command (
        'images.toggle_pixelated',
        'Toggle Sharp Square Pixels',
        'grid-3x3',
        { type = 'pixelated' }
      )
      commands.register ({
        id = 'images.view_as_text',
        category = 'Image',
        title = 'View the SVG as Text',
        icon = 'file-code',
        when = function ()
          local view = service.active ()
          return view ~= nil and viewer.extension (view.path) == 'svg'
        end,
        run = function ()
          local view = service.active ()
          if view then
            editor.open (view.path)
          end
        end,
      })
    end
  end,
}
