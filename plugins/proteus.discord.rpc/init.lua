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
-- goes away when that plugin stops. Its settings, under `discord.` in Settings, follow the
-- profile, and the commands in the Discord category change them. It talks to Discord on
-- Windows only.
--
-- It runs restricted. `process` starts the PowerShell script that talks to Discord, and
-- `files` lets it follow the editor, which shows the file being edited.

local config_m = require ('discord_config') --[[@as Discord.ConfigModule]]
local drpc = require ('drpc') --[[@as Discord.RpcModule]]
local presence = require ('discord_presence') --[[@as Discord.PresenceModule]]

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

---The older settings file as saved, or an empty table.
---@param app Proteus.App
---@return table<string, any>
local function read_old (app)
  local raw = app.fs.read_json (config_m.OLD_FILE, {})
  return type (raw) == 'table' and raw or {}
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
  version = '1.1.0',
  permissions = { 'files', 'process' },
  requires = { proteus = '>=0.3.0', features = { 'permissions' } },
  optional = {
    'proteus.core.settings',
    'proteus.core.commands',
    'proteus.ui.notify',
    'proteus.editor.core',
  },
  activate = function (app)
    local profile = app.kernel.profile ()
    local editor = app.try_use ('editor')
    local settings = app.try_use ('settings')
    ---@param key string
    ---@return any
    local function get (key)
      if settings then
        return settings.get (key)
      end
      return config_m.default (key)
    end
    if settings then
      for _, s in ipairs (config_m.SETTINGS) do
        settings.define (s.key, s.spec)
      end
      -- The older settings file, which every profile shared, moves into this profile's
      -- settings once.
      if app.fs.exists (config_m.OLD_FILE) then
        local moved = config_m.moved (read_old (app), settings.is_set)
        for key, value in pairs (moved) do
          settings.set (key, value)
        end
        app.fs.remove (config_m.OLD_FILE)
      end
    end
    -- The PowerShell script that talks to Discord runs on Windows only.
    local supported = app.os == 'windows'
    local config = config_m.read (get)
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
      if config.enabled and supported and not rpc then
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
    app.on ('fs:changed', function (_, remote)
      if not remote then
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
      ---@param key string
      ---@param value any
      ---@param message string
      local function change (key, value, message)
        if settings then
          settings.set (key, value)
        end
        local notify = app.try_use ('notify')
        if notify then
          if supported then
            notify.info (message)
          else
            notify.warn ('Discord Rich Presence works on Windows only.')
          end
        end
      end

      commands.register ({
        id = 'discord.toggle',
        category = 'Discord',
        title = 'Turn Rich Presence On or Off',
        icon = 'radio',
        run = function ()
          local on = not config.enabled
          change (
            'discord.enabled',
            on,
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
          change (
            'discord.show_names',
            on,
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
          return settings ~= nil
        end,
        run = function ()
          commands.run ('settings.open')
        end,
      })
    end

    app.dispose (disconnect)
    detect ()
    follow_editor ()
    apply ()
    -- A change in Settings applies at once.
    if settings then
      for _, s in ipairs (config_m.SETTINGS) do
        app.dispose (settings.watch (s.key, function ()
          config = config_m.read (get)
          apply ()
        end))
      end
    end
  end,
}
