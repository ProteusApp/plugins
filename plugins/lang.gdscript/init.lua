-- lang.gdscript: GDScript, the language of Godot 4, in the code editor.
--
-- The Godot editor has a language server built in, which gives completion, hover help, go to
-- definition and problems. It listens on a port on this computer rather than running as a
-- program of its own, so the plugin connects to it while Godot has the project open. It can
-- also start Godot itself, with no window, when the `gdscript.start_godot` setting is on.
--
-- Godot's scenes and resources, `.tscn` and `.tres`, and its `project.godot` and `.import`
-- files get colors of their own. F12 on a `res://` path in them, or in a script, opens the
-- file it names.
--
-- The parts live in lib/:
--   languages  the two languages, as data
--   server     the connection to Godot, and starting Godot
--   godot      the Godot program: its names, versions and command line
--   project    project.godot, and the files `res://` paths name
--   provider   tidier hover help, and F12 on `res://` paths
--   hover      Godot's hover help as plain Markdown

local disk = require ('disk_paths') --[[@as DiskPaths]]
local editor_module = require ('lib.editor') --[[@as LangGdscript.EditorModule]]
local godot = require ('lib.godot') --[[@as LangGdscript.GodotModule]]
local languages = require ('lib.languages') --[[@as LangGdscript.LanguagesModule]]
local project = require ('lib.project') --[[@as LangGdscript.ProjectModule]]
local server_module = require ('lib.server') --[[@as LangGdscript.ServerModule]]

---What the parts of the plugin share.
---@class LangGdscript.Context
---@field app Proteus.App
---@field settings Proteus.Settings
---@field editor Proteus.Editor
---@field to_disk fun(doc: Proteus.DocInfo): string A document's full path.
---@field folder? string The folder open in the Code Editor.
---@field folder_trusted boolean True when the user trusts that folder, so Godot may start on a project in it.
---@field notify fun(text: string) A warning, when ui.notify runs.

---@type Proteus.Plugin
return {
  name = 'GDScript',
  description = "GDScript for Godot 4: completion, hover help, go to definition and problems from the Godot editor's language server.",
  version = '1.2.0',
  requires = {
    proteus = '>=0.3.1',
    features = { 'permissions', 'languages', 'tcp' },
  },
  -- `net` connects to the Godot editor's language server on this computer. `files` lets it
  -- use the `editor` service and find project.godot anywhere on disk. `process` starts Godot
  -- when `gdscript.start_godot` is on.
  permissions = { 'net', 'files', 'process' },
  depends = {
    'proteus.lib.ui',
    'proteus.core.settings',
    'proteus.core.commands',
    'proteus.editor.core',
    'proteus.tools.registry',
    'proteus.tools.diagnostics',
  },
  optional = {
    'proteus.code.project',
    'proteus.ui.notify',
    -- Nests Godot's .uid files and adds Open in the Godot Editor to a scene's menu.
    'proteus.code.explorer',
  },
  activate = function (app)
    local ui = app.use ('ui')
    local settings = app.use ('settings')
    local editor = app.use ('editor')

    ui.language (languages.gdscript)
    ui.language (languages.resource)

    settings.define ('gdscript.port', {
      title = "Port of Godot's language server",
      type = 'number',
      default = godot.DEFAULT_PORT,
      description = "The port the Godot editor listens on. Godot's own setting is Network > Language Server > Remote Port.",
    })
    settings.define ('gdscript.start_godot', {
      title = 'Start Godot when it is not running',
      type = 'boolean',
      default = false,
      description = 'Starts the Godot editor with no window on the project, for its language server, and stops it with Proteus. Needs Godot 4.2 or newer.',
      sensitive = true,
    })
    settings.define ('gdscript.godot_path', {
      title = 'Godot program',
      type = 'string',
      default = '',
      description = 'The full path of the Godot program. When empty, godot or godot4 on the PATH.',
      sensitive = true,
    })

    local workspace = disk.normalize (app.kernel.launch.workspace or '')
    local open = app.try_use ('project')
    local folder = open and open.root () or nil
    local folder_trusted = false
    if folder and open then
      if open.trusted then
        folder_trusted = open.trusted ()
      else
        folder_trusted = app.kernel.project ().trusted == true
      end
    end

    ---@type LangGdscript.Context
    local ctx = {
      app = app,
      settings = settings,
      editor = editor,
      folder = folder,
      folder_trusted = folder_trusted,
      to_disk = function (doc)
        return doc.external and disk.normalize (doc.path)
          or disk.join (workspace, doc.path)
      end,
      notify = function (text)
        local n = app.try_use ('notify')
        if n then
          n.warn (text)
        end
      end,
    }

    local server ---@type LangGdscript.Server
    local tool = app.use ('tools').register ({
      id = 'godot',
      name = 'Godot',
      description = 'Completion, hover help, go to definition and problems for GDScript, from the Godot editor.',
      program = 'godot',
      kind = 'server',
      install = 'Install Godot 4 from godotengine.org, then open the project in it.',
      languages = { 'gdscript' },
      homepage = 'https://godotengine.org',
      settings = {
        'gdscript.port',
        'gdscript.start_godot',
        'gdscript.godot_path',
      },
      start = function ()
        server.start (nil)
      end,
      stop = function ()
        server.stop ()
      end,
      check = function ()
        server.restart ()
      end,
    })
    server = server_module.install (ctx, tool)

    -- F12 on a `res://` path in a scene or resource opens the file.
    editor.set_provider ('godotresource', function (doc)
      ---@type Proteus.CodeProvider
      return {
        definition = function (pos)
          local line = project.line_at (doc.text (), pos.line)
          local res = line and project.res_path_at (line, pos.character)
          if res then
            server.open_res (doc, res)
          end
        end,
      }
    end)

    app.use ('commands').register ({
      id = 'gdscript.restart',
      category = 'GDScript',
      title = 'Reconnect to Godot',
      icon = 'rotate-cw',
      run = function ()
        server.restart ()
      end,
    })

    -- A new port, program or choice to start Godot takes effect at once. `watch` also runs
    -- straight away, which the plugin skips.
    for _, key in ipairs ({
      'gdscript.port',
      'gdscript.start_godot',
      'gdscript.godot_path',
    }) do
      local first = true
      settings.watch (key, function ()
        if first then
          first = false
          return
        end
        server.restart ()
      end)
    end

    -- Godot writes a .uid file beside each script and shader. It sits under that file in the
    -- Code Editor's file tree, and a scene's right-click menu opens it in the Godot editor.
    local explorer = app.try_use ('code.explorer')
    if explorer and explorer.add_nesting then
      explorer.add_nesting ({ ['*'] = { '${capture}.uid' } })
      explorer.add_menu_item ({
        label = 'Open in the Godot Editor',
        icon = 'app-window',
        when = godot.is_scene,
        run = editor_module.opener (app, settings, ctx.notify),
      })
    end

    server.start (nil)
  end,
}
