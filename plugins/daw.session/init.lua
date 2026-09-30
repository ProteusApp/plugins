-- daw.session: the open song. It keeps the song, its file in songs/, the undo history and
-- what is selected, and it is the only place a song changes. Every change goes through
-- `apply`, which sends `daw:changed` with the new song, so each view redraws from the same
-- value and never keeps a song of its own.
--
-- Events it sends:
--   daw:changed (song, change)   the song changed, see Daw.Change
--   daw:selection ()             the selected track or clips changed
--   daw:edit (clip_id)           the piano roll should edit this clip
--   daw:saved (path)             the song was written to its file

-- The workspace folder this plugin claims in `folders`, so songs sit where people find them.
local DIR = 'songs'
local AUTOSAVE_MS = 1500
local RECENT = 10

---@param text string
---@return string
local function safe_name (text)
  local base = (text:gsub ('[\\/:%*%?"<>|]', '-')):match ('^%s*(.-)%s*$') or ''
  if base == '' or base:sub (1, 1) == '.' then
    return 'Untitled'
  end
  return base
end

---@type Proteus.Plugin
return {
  name = 'DAW session',
  description = 'The open song: its file, undo and redo, and what is selected.',
  version = '1.0.0',
  requires = { proteus = '>=0.2.0', features = { 'permissions' } },
  permissions = {},
  folders = { 'songs' },
  depends = { 'daw.core', 'core.commands' },
  optional = {
    'core.settings',
    'ui.palette',
    'ui.notify',
    'ui.statusbar',
    'core.keys',
  },
  activate = function (app)
    local daw = app.use ('daw') --[[@as Daw.Core]]
    local commands = app.use ('commands')
    local settings = app.try_use ('settings')
    local picker = app.try_use ('picker')
    local notify = app.try_use ('notify')
    local status = app.try_use ('status')
    local EXT = daw.file.EXT

    if settings then
      settings.define ('daw.autosave', {
        title = 'Save songs as they change',
        type = 'boolean',
        default = true,
        description = 'Writes a song that has a file after each change, a moment after the last one.',
      })
    end

    local song = daw.song.new () ---@type Daw.Song
    local path = nil ---@type string?
    local dirty = false
    local history = daw.history.new (300, app.util.now)
    local selected_track = nil ---@type string?
    local selected_clips = {} ---@type string[]
    local editing = nil ---@type string?
    local cancel_save = nil ---@type fun()?

    local item = status
      and status.add ({
        id = 'daw.song',
        icon = 'music',
        text = '',
        align = 'left',
        order = 1,
        command = 'daw.open',
        tooltip = 'Open another song',
      })

    local function show_state ()
      if item then
        item.set (song.name .. (dirty and ' •' or ''))
      end
    end

    ---@return boolean
    local function typing ()
      return app.dom.focus_info ().editable
    end

    -- Files -----------------------------------------------------------------------------------

    ---@param target string
    ---@return boolean
    local function write (target)
      app.fs.mkdir (DIR)
      local ok, err =
        pcall (app.fs.write_json, target, daw.file.for_save (song))
      if not ok then
        if notify then
          notify.error ('Could not save the song: ' .. tostring (err))
        end
        return false
      end
      dirty = false
      show_state ()
      app.emit ('daw:saved', target)
      return true
    end

    ---@param target string
    local function remember (target)
      local recent = { target } ---@type string[]
      for _, p in
        ipairs (app.store.get ('recent', {}) --[[@as string[] ]])
      do
        if p ~= target and #recent < RECENT then
          recent[#recent + 1] = p
        end
      end
      app.store.set ('recent', recent)
      app.store.set ('last', target)
    end

    local function schedule_save ()
      if cancel_save then
        cancel_save ()
        cancel_save = nil
      end
      if not path or (settings and settings.get ('daw.autosave') == false) then
        return
      end
      cancel_save = app.timer.after (AUTOSAVE_MS, function ()
        cancel_save = nil
        if dirty and path then
          write (path)
        end
      end)
    end

    -- Changes ---------------------------------------------------------------------------------

    ---@param next_song Daw.Song
    ---@param change Daw.Change
    local function replace (next_song, change)
      song = next_song
      -- Selections that point at something gone are dropped.
      if selected_track and not daw.song.track (song, selected_track) then
        selected_track = song.tracks[1] and song.tracks[1].id or nil
      end
      local keep = {} ---@type string[]
      for _, id in ipairs (selected_clips) do
        if daw.song.clip (song, id) then
          keep[#keep + 1] = id
        end
      end
      selected_clips = keep
      if editing and not daw.song.clip (song, editing) then
        editing = nil
        app.emit ('daw:edit', nil)
      end
      show_state ()
      app.emit ('daw:changed', song, change)
    end

    ---@param next_song Daw.Song
    ---@param change? Daw.Change
    ---@param coalesce? string
    local function apply (next_song, change, coalesce)
      if next_song == song then
        return
      end
      history.push (song, coalesce)
      dirty = true
      replace (next_song, change or { kind = 'edit' })
      schedule_save ()
    end

    ---@param next_song Daw.Song
    ---@param target string?
    ---@param kind 'open'|'new'
    local function load (next_song, target, kind)
      if cancel_save then
        cancel_save ()
        cancel_save = nil
      end
      if dirty and path then
        write (path)
      end
      history.clear ()
      path = target
      dirty = false
      selected_clips = {}
      editing = nil
      selected_track = next_song.tracks[1] and next_song.tracks[1].id or nil
      replace (next_song, { kind = kind })
      app.emit ('daw:selection')
      app.emit ('daw:edit', nil)
    end

    ---@param target string
    ---@return boolean
    local function open (target)
      local data = app.fs.read_json (target, nil)
      if type (data) ~= 'table' then
        if notify then
          notify.error ('Could not read ' .. target)
        end
        return false
      end
      load (daw.file.normalize (data), target, 'open')
      remember (target)
      return true
    end

    ---@return { path: string, name: string }[]
    local function list ()
      local out = {} ---@type { path: string, name: string }[]
      local seen = {} ---@type table<string, boolean>
      local recent = app.store.get ('recent', {}) --[[@as string[] ]]
      for _, p in ipairs (recent) do
        if app.fs.exists (p) and not seen[p] then
          seen[p] = true
          out[#out + 1] =
            { path = p, name = (p:match ('([^/]+)$') or p):sub (1, -#EXT - 1) }
        end
      end
      local rest = {} ---@type { path: string, name: string }[]
      for _, entry in ipairs (app.fs.list (DIR)) do
        if
          not entry.dir
          and entry.name:sub (-#EXT) == EXT
          and not seen[entry.path]
        then
          rest[#rest + 1] =
            { path = entry.path, name = entry.name:sub (1, -#EXT - 1) }
        end
      end
      table.sort (rest, function (a, b)
        return a.name:lower () < b.name:lower ()
      end)
      for _, r in ipairs (rest) do
        out[#out + 1] = r
      end
      return out
    end

    ---@param done? fun(path: string)
    local function save_as (done)
      if not picker then
        local target = DIR .. '/' .. safe_name (song.name) .. EXT
        if write (target) then
          path = target
          remember (target)
          if done then
            done (target)
          end
        end
        return
      end
      picker.input ({
        prompt = 'Save the song as',
        value = song.name,
        validate = function (text)
          if safe_name (text) == 'Untitled' and text:match ('^%s*$') then
            return 'Type a name'
          end
          return nil
        end,
        on_submit = function (text)
          local name = safe_name (text)
          local target = DIR .. '/' .. name .. EXT
          local function go ()
            if name ~= song.name then
              song = daw.song.set (song, { name = name })
              replace (song, { kind = 'edit', label = 'Rename' })
            end
            if write (target) then
              path = target
              remember (target)
              if done then
                done (target)
              end
            end
          end
          if target ~= path and app.fs.exists (target) then
            picker.confirm ({
              message = name .. ' already exists. Replace it?',
              yes = 'Replace',
              on_yes = go,
            })
          else
            go ()
          end
        end,
      })
    end

    ---@param done? fun(path: string)
    local function save (done)
      if path then
        if write (path) and done then
          done (path)
        end
      else
        save_as (done)
      end
    end

    ---@param next_song? Daw.Song
    local function new (next_song)
      load (next_song or daw.demo.empty (), nil, 'new')
    end

    ---@param fn fun()
    local function unless_lost (fn)
      if not dirty or path or not picker then
        fn ()
        return
      end
      picker.confirm ({
        message = song.name .. ' has not been saved. Leave it?',
        yes = 'Leave It',
        no = 'Keep Working',
        on_yes = fn,
      })
    end

    local function undo ()
      local prev = history.undo (song)
      if prev then
        dirty = true
        replace (prev, { kind = 'undo' })
        schedule_save ()
      end
    end

    local function redo ()
      local next_song = history.redo (song)
      if next_song then
        dirty = true
        replace (next_song, { kind = 'undo' })
        schedule_save ()
      end
    end

    ---@type Daw.Session
    local service = {
      song = function ()
        return song
      end,
      apply = apply,
      seal = function ()
        history.seal ()
      end,
      undo = undo,
      redo = redo,
      can_undo = function ()
        return history.can_undo ()
      end,
      can_redo = function ()
        return history.can_redo ()
      end,
      path = function ()
        return path
      end,
      dirty = function ()
        return dirty
      end,
      new = new,
      open = open,
      save = save,
      save_as = save_as,
      list = list,
      selected_track = function ()
        return selected_track
      end,
      select_track = function (id)
        if id ~= selected_track then
          selected_track = id
          app.emit ('daw:selection')
        end
      end,
      selected_clips = function ()
        return selected_clips
      end,
      select_clips = function (ids)
        selected_clips = ids
        local first = ids[1] and daw.song.clip (song, ids[1])
        local _, owner = daw.song.clip (song, ids[1] or '')
        if first and owner then
          selected_track = owner.id
        end
        app.emit ('daw:selection')
      end,
      editing = function ()
        return editing
      end,
      edit_clip = function (id)
        editing = id
        app.emit ('daw:edit', id)
      end,
    }
    app.provide ('daw.session', service)

    -- Commands --------------------------------------------------------------------------------

    commands.register ({
      id = 'daw.new',
      category = 'DAW',
      title = 'New Song',
      -- The browser's New button runs it too.
      shared = true,
      key = 'ctrl+n',
      icon = 'file-music',
      menu = 'File',
      group = '1',
      run = function ()
        unless_lost (function ()
          new ()
        end)
      end,
    })
    commands.register ({
      id = 'daw.open',
      category = 'DAW',
      title = 'Open Song',
      key = 'ctrl+o',
      icon = 'folder-open',
      menu = 'File',
      group = '1',
      run = function ()
        if not picker then
          return
        end
        local items = {} ---@type Proteus.PickItem[]
        for _, s in ipairs (list ()) do
          items[#items + 1] = {
            label = s.name,
            detail = s.path == path and 'open now' or nil,
            icon = 'music',
            value = s.path,
          }
        end
        picker.pick ({
          placeholder = 'Open a song',
          items = items,
          empty = 'No songs yet. New Song starts one.',
          on_pick = function (it)
            unless_lost (function ()
              open (it.value --[[@as string]])
            end)
          end,
        })
      end,
    })
    commands.register ({
      id = 'daw.save',
      category = 'DAW',
      title = 'Save Song',
      shared = true,
      key = 'ctrl+s',
      icon = 'save',
      menu = 'File',
      group = '2',
      run = function ()
        save (function (target)
          if notify then
            notify.success ('Saved ' .. target)
          end
        end)
      end,
    })
    commands.register ({
      id = 'daw.save_as',
      category = 'DAW',
      title = 'Save Song As',
      key = 'ctrl+shift+s',
      icon = 'save',
      menu = 'File',
      group = '2',
      run = function ()
        save_as ()
      end,
    })
    commands.register ({
      id = 'daw.demo',
      category = 'DAW',
      title = 'Open the Demo Song',
      icon = 'sparkles',
      menu = 'File',
      group = '3',
      run = function ()
        unless_lost (function ()
          new (daw.demo.song ())
        end)
      end,
    })
    commands.register ({
      id = 'daw.rename',
      category = 'DAW',
      title = 'Rename Song',
      icon = 'pencil',
      run = function ()
        if not picker then
          return
        end
        picker.input ({
          prompt = 'Song name',
          value = song.name,
          on_submit = function (text)
            local name = safe_name (text)
            local old = path
            apply (
              daw.song.set (song, { name = name }),
              { kind = 'edit', label = 'Rename' }
            )
            if old then
              local target = DIR .. '/' .. name .. EXT
              if target ~= old and not app.fs.exists (target) then
                app.fs.rename (old, target)
                path = target
                remember (target)
              end
            end
          end,
        })
      end,
    })
    commands.register ({
      id = 'daw.undo',
      category = 'DAW',
      title = 'Undo',
      key = 'ctrl+z',
      icon = 'undo-2',
      menu = 'Edit',
      group = '1',
      when = function ()
        return not typing () and history.can_undo ()
      end,
      run = undo,
    })
    commands.register ({
      id = 'daw.redo',
      category = 'DAW',
      title = 'Redo',
      key = { 'ctrl+y', 'ctrl+shift+z' },
      icon = 'redo-2',
      menu = 'Edit',
      group = '1',
      when = function ()
        return not typing () and history.can_redo ()
      end,
      run = redo,
    })

    -- Start: the last song, or the demo the first time ----------------------------------------

    local last = app.store.get ('last') --[[@as string?]]
    if not (last and app.fs.exists (last) and open (last)) then
      local songs = list ()
      if #songs > 0 then
        open (songs[1].path)
      else
        load (daw.demo.song (), nil, 'new')
        local target = DIR .. '/Demo' .. EXT
        if write (target) then
          path = target
          remember (target)
        end
      end
    end

    app.dispose (function ()
      if dirty and path then
        write (path)
      end
    end)
  end,
}
