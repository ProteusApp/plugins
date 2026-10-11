---@type Proteus.Plugin
return {
  name = 'Godot resource inspector',
  description = 'Edits Godot .tres files with fields for saved properties and subresources.',
  version = '1.0.0',
  permissions = { 'files' },
  requires = { proteus = '>=0.3.0', features = { 'permissions', 'webview' } },
  depends = { 'proteus.lib.ui', 'proteus.ui.tabs', 'proteus.editor.core' },
  optional = { 'proteus.core.commands' },
  activate = function (app)
    local ui = app.use ('ui')
    local tabs = app.use ('tabs')
    local editor = app.use ('editor')
    local commands = app.try_use ('commands')
    local saves = {} ---@type table<string, fun()>

    editor.add_opener (function (path)
      if not path:lower ():match ('%.tres$') then
        return false
      end
      if
        not (
          path:match ('^/')
          or path:match ('^%a:[/\\]')
          or path:match ('^\\\\')
        )
      then
        return false
      end
      local key = path:gsub ('\\', '/')
      if key:match ('^%a:') or key:match ('^//') then
        key = key:lower ()
      end
      local id = 'tres:' .. key
      local existing = tabs.get (id)
      if existing then
        existing.focus ()
        return true
      end
      local tab ---@type Proteus.Tab?
      local page ---@type Proteus.El
      local original, current = nil, nil ---@type string?, string?
      local busy, closed = false, false
      local close_after_save = false

      ---@param message table
      local function post (message)
        if not closed then
          page:widget ('post', message)
        end
      end

      ---@param text string
      local function status (text)
        post ({ type = 'status', text = text })
      end

      local function load ()
        if busy then
          return
        end
        busy = true
        app.fs.read_file (path, function (text, err)
          busy = false
          if closed then
            return
          end
          if err or not text then
            status (err or 'The file could not be read.')
            return
          end
          original, current = text, text
          if tab then
            tab.set_dirty (false)
          end
          post ({ type = 'load', text = text })
        end)
      end

      local function save ()
        if busy or not current or current == original then
          return
        end
        busy = true
        local snapshot = current
        app.fs.read_file (path, function (disk, err)
          if closed then
            busy = false
            return
          end
          if err or disk ~= original then
            busy = false
            status (
              err
                or 'The file changed on disk. Copy any edits before reloading.'
            )
            return
          end
          app.fs.write_file (path, snapshot, function (_, write_err)
            busy = false
            if write_err then
              status ('Save failed: ' .. write_err)
              return
            end
            original = snapshot
            if tab and not closed then
              tab.set_dirty (current ~= original)
            end
            status (
              current == original and 'Saved.'
                or 'Saved. Newer edits are still unsaved.'
            )
            if close_after_save and current == original and tab then
              close_after_save = false
              tab.close ()
            end
          end)
        end)
      end

      page = ui.webview ({
        page = 'page/index.html',
        on_message = function (message)
          if type (message) ~= 'table' then
            return
          end
          if message.type == 'ready' then
            load ()
          elseif
            message.type == 'change'
            and type (message.text) == 'string'
            and original
          then
            current = message.text
            if tab then
              tab.set_dirty (current ~= original)
            end
          elseif message.type == 'save' then
            save ()
          elseif message.type == 'reload' then
            if current ~= original then
              ui.confirm ({
                message = 'Discard unsaved edits and reload this resource?',
                on_yes = load,
              })
            else
              load ()
            end
          elseif message.type == 'text' then
            if current ~= original then
              status ('Save or discard edits before opening the file as text.')
            else
              editor.open (path, { as_text = true })
            end
          end
        end,
      })
      tab = tabs.open ({
        id = id,
        title = path:match ('[^/\\]+$') or path,
        tooltip = path,
        icon = 'sliders-horizontal',
        content = page,
        on_close = function (choice)
          if busy then
            status ('Wait for the file operation to finish.')
            return false
          end
          if current ~= original and choice == 'save' then
            close_after_save = true
            save ()
            return false
          end
          if current ~= original and choice ~= 'discard' then
            ui.confirm ({
              message = 'Close this resource and discard unsaved edits?',
              on_yes = function ()
                closed = true
                saves[id] = nil
                if tab then
                  tab.close (true)
                end
              end,
            })
            return false
          end
          closed = true
          saves[id] = nil
          return true
        end,
      })
      saves[id] = save
      return true
    end)
    if commands then
      commands.register ({
        id = 'tres.save',
        title = 'Save Godot Resource',
        category = 'Godot',
        key = 'ctrl+s',
        when = function ()
          local active = tabs.active ()
          return active ~= nil and saves[active.id] ~= nil
        end,
        run = function ()
          local active = tabs.active ()
          if active and saves[active.id] then
            saves[active.id] ()
          end
        end,
      })
    end
  end,
}
