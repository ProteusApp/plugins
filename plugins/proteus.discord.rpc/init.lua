-- proteus.discord.rpc: shows what you are doing in Proteus on your Discord profile, the way the
-- Discord extensions for VS Code do.
--
-- Each app has its own lines, picked from the plugins that run. The editor shows the file
-- being edited, Git shows the branch, Notes shows "Writing notes", and so on. The lines
-- live in discord_presence.lua. Any plugin can add its own:
--
--   local discord = app.try_use ('discord')
--   if discord then
--     discord.set ({ details = 'Reviewing a diff', state = 'On branch {branch}' })
--     discord.vars ({ branch = 'main' })
--   end
--
-- List 'proteus.discord.rpc' in `optional` so it starts first. The service needs the `net`
-- permission, since what a plugin sets shows on the user's Discord profile. What a plugin set
-- goes away when that plugin stops. The settings live in data/proteus.discord.rpc/discord.json,
-- shared by every profile, and the commands in the Discord category change them.
--
-- It runs restricted. `process` starts the PowerShell script that talks to Discord, and
-- `files` lets it follow the editor, which shows the file being edited and opens the
-- settings file.

local drpc = require ('drpc') --[[@as Discord.RpcModule]]
local presence = require ('discord_presence') --[[@as Discord.PresenceModule]]

local CONFIG = 'data/proteus.discord.rpc/discord.json'
-- The Proteus application on Discord. Its name is what shows after "Playing".
local CLIENT_ID = '562297553253564438'
-- Discord takes about five updates every 20 seconds, so updates wait at least this long.
local GAP_SECONDS = 4

local LANGUAGES = {
  lua = 'Lua',
  json = 'JSON',
  markdown = 'Markdown',
  javascript = 'JavaScript',
  typescript = 'TypeScript',
  css = 'CSS',
  html = 'HTML',
  yaml = 'YAML',
  toml = 'TOML',
  shell = 'shell script',
  jsx = 'JavaScript',
  tsx = 'TypeScript',
  python = 'Python',
  rust = 'Rust',
  go = 'Go',
  haskell = 'Haskell',
  c = 'C',
  cpp = 'C++',
  csharp = 'C#',
  java = 'Java',
  kotlin = 'Kotlin',
  scala = 'Scala',
  dart = 'Dart',
  sql = 'SQL',
  xml = 'XML',
  ruby = 'Ruby',
  swift = 'Swift',
  powershell = 'PowerShell',
  dockerfile = 'a Dockerfile',
  elm = 'Elm',
  clojure = 'Clojure',
  erlang = 'Erlang',
  ocaml = 'OCaml',
  fsharp = 'F#',
  text = 'text',
}

-- Words that name the user's own files and projects. They stay out while names are hidden.
local PRIVATE =
  { file = true, plugin = true, repo = true, branch = true, project = true }

---The settings in data/proteus.discord.rpc/discord.json.
---@class Discord.Config
---@field enabled boolean
---@field client_id string
---@field show_names boolean False keeps file, plugin and repository names off Discord.
---@field idle_minutes number Minutes without activity before the presence says Idle. 0 never does.
---@field images table<string, string> An art asset name or image URL by app id, such as `editor`, or `default` for every app.

---The settings file as saved, or an empty table.
---@param app Proteus.App
---@return table<string, any>
local function read_raw (app)
  local raw = app.fs.read_json (CONFIG, {})
  return type (raw) == 'table' and raw or {}
end

---@param app Proteus.App
---@return Discord.Config
local function read_config (app)
  local raw = read_raw (app)
  local id = raw.client_id
  return {
    enabled = raw.enabled == true,
    client_id = type (id) == 'string' and id ~= '' and id or CLIENT_ID,
    show_names = raw.show_names ~= false,
    idle_minutes = tonumber (raw.idle_minutes) or 10,
    images = type (raw.images) == 'table' and raw.images or {},
  }
end

---@param path string
---@return string
local function basename (path)
  return path:match ('[^/\\]+$') or path
end

---@type Proteus.Plugin
return {
  name = 'Discord Rich Presence',
  description = 'Shows what you are doing in Proteus on your Discord profile.',
  version = '1.0.0',
  permissions = { 'files', 'process' },
  requires = { proteus = '>=0.3.0', features = { 'permissions' } },
  optional = {
    'proteus.core.commands',
    'proteus.ui.notify',
    'proteus.editor.core',
  },
  activate = function (app)
    local profile = app.kernel.profile ()
    local editor = app.try_use ('editor')
    local config = read_config (app)
    local started = os.time ()
    local rpc = nil ---@type Discord.Client?
    local rpc_id = nil ---@type string?
    local stop_ticks = nil ---@type fun()?
    local preset = presence.FALLBACK
    local layers = {} ---@type Discord.Layer[]
    local plugin_vars = {} ---@type table<string, table<string, string>> By plugin id.
    local editor_vars = {} ---@type table<string, string>
    local quiet = 0 -- Seconds since the last activity.
    local wait = 0 -- Seconds before another update may go out.
    local dirty = true
    local sent = nil ---@type string? The last presence sent, as JSON.

    local function update ()
      dirty = true
    end

    ---@return boolean
    local function idle ()
      return config.idle_minutes > 0 and quiet >= config.idle_minutes * 60
    end

    local function touch ()
      if idle () then
        update ()
      end
      quiet = 0
    end

    ---@return table<string, string>
    local function vars ()
      local all = { profile = profile.name } ---@type table<string, string>
      -- The Code Editor's folder, read here so the Code Editor needs no `net` to name it.
      local project = app.try_use ('project') --[[@as { name: fun(): string? }?]]
      local folder = project and project.name ()
      if folder then
        all.project = folder
      end
      for _, owned in pairs (plugin_vars) do
        for word, value in pairs (owned) do
          all[word] = value
        end
      end
      for word, value in pairs (editor_vars) do
        all[word] = value
      end
      if not config.show_names then
        for word in pairs (PRIVATE) do
          all[word] = nil
        end
      end
      return all
    end

    local function send ()
      if not rpc then
        return
      end
      local p = presence.build (preset, layers, vars (), {
        idle = idle (),
        start = started,
        image = config.images[preset.id] or config.images.default,
      })
      local json = app.json.encode (p)
      if json ~= sent then
        sent = json
        rpc.set (p)
      end
    end

    local function tick ()
      quiet = quiet + 1
      wait = math.max (0, wait - 1)
      if config.idle_minutes > 0 and quiet == config.idle_minutes * 60 then
        update ()
      end
      if dirty and wait == 0 then
        dirty = false
        wait = GAP_SECONDS
        send ()
      end
    end

    local function disconnect ()
      if stop_ticks then
        stop_ticks ()
        stop_ticks = nil
      end
      if rpc then
        rpc.close ()
        rpc = nil
      end
      sent = nil
    end

    local function apply ()
      if rpc and (not config.enabled or rpc_id ~= config.client_id) then
        disconnect ()
      end
      if config.enabled and not rpc then
        rpc = drpc.connect (app, config.client_id)
        rpc_id = config.client_id
        stop_ticks = app.timer.every (1000, tick)
      end
      update ()
    end

    local function detect ()
      local active = {} ---@type table<string, boolean>
      for _, id in ipairs (app.kernel.active ()) do
        active[id] = true
      end
      preset = presence.detect (profile.id, active)
      update ()
    end

    local function follow_editor ()
      local doc = editor and editor.current ()
      editor_vars = {}
      if doc then
        editor_vars.file = basename (doc.path)
        editor_vars.language = LANGUAGES[doc.language] or doc.language
        local owner = not doc.external and app.kernel.plugin_of (doc.path)
        if owner then
          editor_vars.plugin = owner
        end
      end
      update ()
    end

    for _, event in ipairs ({
      'kernel:ready',
      'kernel:plugin_started',
      'kernel:plugin_stopped',
    }) do
      app.on (event, detect)
    end
    for _, event in ipairs ({ 'tabs:changed', 'editor:opened', 'editor:closed' }) do
      app.on (event, function ()
        touch ()
        follow_editor ()
      end)
    end
    for _, event in ipairs ({
      'editor:changed',
      'editor:saved',
      'views:shown',
      'commands:before_run',
    }) do
      app.on (event, touch)
    end
    app.on ('fs:changed', function (path, remote)
      if path == CONFIG then
        config = read_config (app)
        apply ()
      elseif not remote then
        touch ()
      end
    end)

    app.provide_scoped ('discord', function (consumer)
      local owner = consumer.id
      local function remove ()
        for i = #layers, 1, -1 do
          if layers[i].owner == owner then
            table.remove (layers, i)
          end
        end
      end
      consumer.dispose (function ()
        remove ()
        plugin_vars[owner] = nil
        update ()
      end)
      ---@type Proteus.Discord
      return {
        set = function (p)
          remove ()
          layers[#layers + 1] = { owner = owner, presence = p }
          update ()
        end,
        clear = function ()
          remove ()
          update ()
        end,
        ---@param values table<string, string|number|false>
        vars = function (values)
          local owned = plugin_vars[owner] or {}
          for word, value in pairs (values) do
            owned[word] = value ~= false and tostring (value) or nil
          end
          plugin_vars[owner] = owned
          update ()
        end,
        connected = function ()
          return rpc ~= nil and rpc.connected ()
        end,
      }
    end, { needs = 'net' })

    local commands = app.try_use ('commands')
    if commands then
      ---@param changes table<string, any>
      ---@param message string
      local function save (changes, message)
        local raw = read_raw (app)
        for key, value in pairs (changes) do
          raw[key] = value
        end
        app.fs.write_json (CONFIG, raw)
        config = read_config (app)
        apply ()
        local notify = app.try_use ('notify')
        if notify then
          notify.info (message)
        end
      end

      commands.register ({
        id = 'discord.toggle',
        category = 'Discord',
        title = 'Turn Rich Presence On or Off',
        icon = 'radio',
        run = function ()
          local on = not config.enabled
          save (
            { enabled = on },
            on and 'Discord now shows what you are doing.'
              or 'Discord no longer shows what you are doing.'
          )
        end,
      })
      commands.register ({
        id = 'discord.names',
        category = 'Discord',
        title = 'Show or Hide Names in Rich Presence',
        icon = 'eye-off',
        run = function ()
          local on = not config.show_names
          save (
            { show_names = on },
            on and 'Discord now shows file, plugin and repository names.'
              or 'Discord no longer shows file, plugin or repository names.'
          )
        end,
      })
      commands.register ({
        id = 'discord.settings',
        category = 'Discord',
        title = 'Open Rich Presence Settings',
        icon = 'settings',
        when = function ()
          return editor ~= nil
        end,
        run = function ()
          if not app.fs.exists (CONFIG) then
            app.fs.write_json (CONFIG, {
              enabled = config.enabled,
              client_id = config.client_id,
              show_names = config.show_names,
              idle_minutes = config.idle_minutes,
            })
          end
          if editor then
            editor.open_file (CONFIG)
          end
        end,
      })
    end

    app.dispose (disconnect)
    detect ()
    follow_editor ()
    apply ()
  end,
}
