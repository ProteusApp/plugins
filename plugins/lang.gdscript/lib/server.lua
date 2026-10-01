-- server: connects the editor to the language server inside the Godot editor.
--
-- Godot does not run its language server as a program of its own. The Godot editor listens on
-- a port on this computer, 6005 unless its settings say otherwise, and serves the project it
-- has open. So the plugin connects to that port when the first GDScript file opens, with the
-- folder that holds `project.godot` as the root.
--
-- When nothing listens there and `gdscript.start_godot` is on, the plugin starts Godot itself:
-- the editor with no window, on the project, with its language server on the port. Then it
-- tries the port once a second until Godot answers, and stops Godot when the plugin stops.
--
-- The app's client reports what happens to the connection through the tool. It gets a stand-in
-- for the tool, so a refused connection turns into a plain message, or the next try, rather
-- than an error.

local client_module = require ('lsp.client') --[[@as Lsp.ClientModule]]
local disk = require ('disk_paths') --[[@as DiskPaths]]
local godot = require ('lib.godot') --[[@as LangGdscript.GodotModule]]
local project = require ('lib.project') --[[@as LangGdscript.ProjectModule]]
local provider = require ('lib.provider') --[[@as LangGdscript.ProviderModule]]

-- How long to wait between tries while Godot starts, and how many tries it gets. A large
-- project takes a while to scan the first time Godot opens it.
local RETRY_MS = 1000
local RETRIES = 90
-- How long Godot has to answer once the connection is made.
local ANSWER_MS = 15000

---@alias LangGdscript.Phase
---| 'idle' # Not connected, and not trying.
---| 'finding' # Looking for project.godot.
---| 'connecting' # Waiting for Godot to answer.
---| 'running' # Connected.
---| 'stopping' # Closing on purpose, so what the client reports is not news.

---The app's client, with the way to connect that came with the `tcp` feature. An older
---Proteus has no `connect`.
---@class LangGdscript.Client: Lsp.Client
---@field connect? fun(port: integer, root: string, init_options?: table)

---@class LangGdscript.Server
---@field start fun(doc: Proteus.DocInfo?)
---@field stop fun()
---@field restart fun()
---@field open_res LangGdscript.OpenRes

---@class LangGdscript.ServerModule
local M = {}

---@param ctx LangGdscript.Context
---@param tool Proteus.ToolHandle
---@return LangGdscript.Server
function M.install (ctx, tool)
  local app, settings, editor = ctx.app, ctx.settings, ctx.editor

  local phase = 'idle' ---@type LangGdscript.Phase
  -- Goes up with each start and stop, so a timer or answer from an earlier one does nothing.
  local round = 0
  -- Goes up with each try of the port, so the wait for an earlier try's answer ends quietly.
  local attempt = 0
  local root = nil ---@type string?
  local has_project = false
  local tries = 0
  -- True once this round tried to start Godot, so it does not start a second one.
  local spawned = false
  -- True after an error, so opening another file does not try again until a restart.
  local gave_up = false
  local proc = nil ---@type Proteus.ProcessHandle?
  local proc_round = 0
  local failed ---@type fun(detail: string?)

  ---@return integer
  local function port ()
    return godot.port (settings.get ('gdscript.port'))
  end

  ---@param state Proteus.ToolState
  ---@param detail string?
  local function give_up (state, detail)
    phase = 'idle'
    gave_up = state == 'error' or state == 'missing'
    tool.set_state (state, detail)
  end

  -- Finding the project ----------------------------------------------------------------------

  local roots = {} ---@type table<string, string|false> The project of each folder, once known.

  ---The folder that holds `project.godot`, for a file anywhere below it.
  ---@param file string
  ---@param cb fun(root: string?)
  local function find_root (file, cb)
    local folders = project.folders_up (file)
    local known = folders[1] and roots[folders[1]]
    if known ~= nil then
      cb (known or nil)
      return
    end
    local i = 0
    local function look ()
      i = i + 1
      local folder = folders[i]
      if not folder then
        roots[folders[1] or ''] = false
        cb (nil)
        return
      end
      app.fs.stat_path (disk.join (folder, 'project.godot'), function (stat)
        if stat and stat.exists and not stat.dir then
          roots[folders[1]] = folder
          cb (folder)
        else
          look ()
        end
      end)
    end
    look ()
  end

  ---@param doc Proteus.DocInfo
  ---@param res string
  ---@return boolean
  local function open_res (doc, res)
    if not res:match ('^res://') then
      return false
    end
    local file = ctx.to_disk (doc)
    find_root (file, function (found)
      if not found then
        ctx.notify (
          'No project.godot above ' .. file .. ', so res:// has no folder.'
        )
        return
      end
      local path = project.res_to_disk (res, found)
      if path then
        editor.open_file (path)
      end
    end)
    return true
  end

  -- The client -------------------------------------------------------------------------------

  -- What the client reports goes through here. While it connects, a closed or refused
  -- connection is a failed try. While it runs, one means Godot went away.
  ---@type Proteus.ToolHandle
  local relay = {
    set_state = function (state, detail)
      if state == 'running' then
        if phase == 'connecting' or phase == 'running' then
          phase = 'running'
          tries = 0
          tool.set_state ('running', detail)
        end
      elseif state == 'starting' then
        if phase == 'connecting' then
          tool.set_state ('starting', 'connecting to Godot on port ' .. port ())
        end
      elseif phase == 'connecting' then
        phase = 'idle'
        failed (detail)
      elseif phase == 'running' then
        phase = 'idle'
        tool.set_state (
          'stopped',
          'Godot closed the connection. Restart GDScript to connect again.'
        )
      end
    end,
    set_version = tool.set_version,
    set_path = tool.set_path,
    log = tool.log,
    locate = tool.locate,
    cached = tool.cached,
    offer = tool.offer,
  }

  local client = client_module.new (provider.wrap_app (app, open_res), {
    name = 'Godot',
    language = 'gdscript',
    source = 'gdscript',
    tool = relay,
  }) --[[@as LangGdscript.Client]]

  ---Closes the connection without reporting it.
  local function close_quietly ()
    local was = phase
    phase = 'stopping'
    client.stop ()
    phase = was
  end

  ---Tries the port once. This is the one place that calls `client.connect`, which came in
  ---the same Proteus as the `tcp` feature.
  local function connect_once ()
    attempt = attempt + 1
    local mine = attempt
    close_quietly ()
    phase = 'connecting'
    tool.set_state ('starting', 'connecting to Godot on port ' .. port ())
    local connect = client.connect
    local done, err = pcall (connect, port (), root or '')
    if not done then
      if mine == attempt and phase == 'connecting' then
        phase = 'idle'
        failed (tostring (err))
      end
      return
    end
    app.timer.after (ANSWER_MS, function ()
      if mine == attempt and phase == 'connecting' then
        phase = 'idle'
        close_quietly ()
        failed ('Godot did not answer on port ' .. port ())
      end
    end)
  end

  -- Starting Godot ---------------------------------------------------------------------------

  local function kill_godot ()
    proc_round = proc_round + 1
    local p = proc
    proc = nil
    if p and p.alive () then
      p.kill ()
      tool.log ('info', 'stopped Godot')
    end
  end

  ---Tries the port again in a moment, while the Godot this plugin started gets ready.
  local function wait_for_godot ()
    local mine = round
    tries = tries + 1
    if tries > RETRIES then
      kill_godot ()
      give_up (
        'error',
        'Godot did not open port '
          .. port ()
          .. ' in time. The log says what it printed.'
      )
      return
    end
    tool.set_state ('starting', 'waiting for Godot to open port ' .. port ())
    app.timer.after (RETRY_MS, function ()
      if mine == round and phase == 'idle' and proc then
        connect_once ()
      end
    end)
  end

  ---Finds the Godot program: the path in the settings, or else `godot` or `godot4` on the PATH.
  ---@param cb fun(program: string?)
  local function find_godot (cb)
    local names = godot.programs (settings.get ('gdscript.godot_path'))
    local i = 0
    local function look ()
      i = i + 1
      local name = names[i]
      if not name then
        cb (nil)
        return
      end
      app.process.which (name, function (path)
        if path then
          cb (path)
        else
          look ()
        end
      end)
    end
    look ()
  end

  ---@param program string
  ---@param folder string
  local function spawn_godot (program, folder)
    kill_godot ()
    local mine = proc_round
    local args = godot.args (folder, port ())
    tool.log ('info', 'starting ' .. program .. ' ' .. table.concat (args, ' '))
    proc = app.process.spawn (program, args, {
      cwd = folder,
      on_message = function (line)
        tool.log ('out', line)
      end,
      on_stderr = function (line)
        tool.log ('err', line)
      end,
      on_exit = function (code)
        if mine ~= proc_round then
          return
        end
        proc = nil
        tool.log ('info', 'Godot exited with code ' .. tostring (code))
        if phase ~= 'running' then
          round = round + 1
          give_up (
            'error',
            'Godot exited with code '
              .. tostring (code)
              .. '. The log says what it printed.'
          )
        end
      end,
      on_error = function (err)
        if mine ~= proc_round then
          return
        end
        proc = nil
        round = round + 1
        give_up ('error', 'Godot did not start: ' .. tostring (err))
      end,
    })
  end

  local function start_godot ()
    local mine = round
    local folder = root
    if not has_project or not folder then
      give_up (
        'stopped',
        'no project.godot above this file, so Godot has no project to open'
      )
      return
    end
    spawned = true
    tool.set_state ('starting', 'looking for Godot')
    find_godot (function (program)
      if mine ~= round then
        return
      end
      if not program then
        local set = godot.programs (settings.get ('gdscript.godot_path'))[1]
        give_up (
          'missing',
          set ~= 'godot'
              and ('there is no program at ' .. set .. ' (gdscript.godot_path)')
            or 'Godot is not on the PATH. Set gdscript.godot_path to the Godot program.'
        )
        return
      end
      tool.set_path (program)
      app.process.run (program, { '--version' }, nil, function (result)
        if mine ~= round then
          return
        end
        -- Godot on Windows may print nothing here. Then the version stays unknown, and the
        -- start goes ahead.
        local major, minor = godot.version (result and result.stdout or '')
        if major and minor and not godot.serves_headless (major, minor) then
          give_up (
            'error',
            'Godot '
              .. major
              .. '.'
              .. minor
              .. ' needs its window for the language server. Godot 4.2 or newer runs without one.'
          )
          return
        end
        spawn_godot (program, folder)
        tries = 0
        wait_for_godot ()
      end)
    end)
  end

  failed = function (detail)
    if detail then
      tool.log ('info', 'no connection: ' .. tostring (detail))
    end
    if proc then
      wait_for_godot ()
      return
    end
    if settings.get ('gdscript.start_godot') == true and not spawned then
      start_godot ()
      return
    end
    give_up (
      'stopped',
      'Godot is not listening on port '
        .. port ()
        .. '. Open the project in the Godot editor, or turn on gdscript.start_godot.'
    )
  end

  -- Starting and stopping --------------------------------------------------------------------

  ---@return Proteus.DocInfo?
  local function first_script ()
    for _, doc in ipairs (editor.docs ()) do
      if doc.language == 'gdscript' then
        return doc
      end
    end
    return nil
  end

  ---The folder to use when no project.godot was found: the open folder, or the file's own.
  ---@param file string
  ---@return string
  local function fallback_root (file)
    local open = app.try_use ('project')
    return open and open.root () or disk.parent (file)
  end

  local server ---@type LangGdscript.Server
  server = {
    start = function (doc)
      if phase ~= 'idle' then
        return
      end
      if type (client.connect) ~= 'function' then
        give_up (
          'error',
          'this Proteus cannot connect to Godot. GDScript needs a newer Proteus.'
        )
        return
      end
      doc = doc or first_script ()
      if not doc then
        tool.set_state ('stopped', 'connects when a GDScript file opens')
        return
      end
      round = round + 1
      local mine = round
      phase = 'finding'
      spawned = false
      gave_up = false
      tries = 0
      local file = ctx.to_disk (doc)
      tool.set_state ('starting', 'looking for project.godot')
      find_root (file, function (found)
        if mine ~= round then
          return
        end
        has_project = found ~= nil
        root = found or fallback_root (file)
        if not found then
          tool.log (
            'info',
            'no project.godot above ' .. file .. ', so the root is ' .. root
          )
        end
        connect_once ()
      end)
    end,

    stop = function ()
      round = round + 1
      phase = 'stopping'
      client.stop ()
      kill_godot ()
      phase = 'idle'
      tool.set_state ('stopped')
    end,

    restart = function ()
      server.stop ()
      server.start (nil)
    end,

    open_res = open_res,
  }

  app.on ('editor:opened', function (doc)
    ---@cast doc Proteus.DocInfo
    if doc.language == 'gdscript' and phase == 'idle' and not gave_up then
      server.start (doc)
    end
  end)

  -- A Godot this plugin started stops with it.
  app.dispose (kill_godot)

  return server
end

return M
