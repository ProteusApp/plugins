-- lang.luau-lsp: Luau, Roblox's typed Lua, in the code editor.
--
-- `.luau` files become a language the editor colors. luau-lsp gives them completion, hover
-- help, go to definition (F12 or Ctrl+click) and type problems. In a Roblox project it loads
-- Roblox's types and API documentation, and runs Rojo to keep `sourcemap.json` up to date.
-- StyLua formats Luau files when it is on the PATH. When luau-lsp is not on the PATH, the
-- Tools panel offers its official release, checked against a pinned checksum.
--
-- `.lua` files stay with the app's own `lua` language and its Lua language server.
--
-- The parts live in lib/:
--   language     the colors for `.luau` files
--   server       luau-lsp, through the app's language server client
--   release      the luau-lsp download for each platform
--   project      whether a folder is a Roblox project
--   definitions  Roblox's types and the API documentation, kept in the data folder
--   sourcemap    runs Rojo while the server runs
--   format       the StyLua formatter
--   launch       the command lines and the server's settings

local disk = require ('disk_paths') --[[@as DiskPaths]]
local format_module = require ('lib.format') --[[@as LangLuau.FormatModule]]
local language = require ('lib.language') --[[@as Proteus.LanguageSpec]]
local release = require ('lib.release') --[[@as Proteus.ToolRelease]]
local server_module = require ('lib.server') --[[@as LangLuau.ServerModule]]

---What the parts of the plugin share.
---@class LangLuau.Context
---@field app Proteus.App
---@field settings Proteus.Settings
---@field editor Proteus.Editor
---@field desktop boolean True in the desktop app, which can run programs.
---@field workspace string The workspace folder, with `/`.
---@field project_root? string The folder open in the Code Editor.
---@field to_disk fun(doc: Proteus.DocInfo): string A document's full path.
---@field notify fun(text: string) A warning, when ui.notify runs.

---@type Proteus.Plugin
return {
  name = 'Luau',
  description = 'Luau with luau-lsp: completion, hover help, go to definition and type problems, with Roblox types, Rojo sourcemaps and StyLua formatting.',
  version = '1.0.1',
  requires = { proteus = '>=0.3.0', features = { 'permissions', 'languages' } },
  -- `files` for the editor service and the files on disk, `process` to run luau-lsp, Rojo and
  -- StyLua, and `net` to download Roblox's types and the API documentation.
  permissions = { 'net', 'files', 'process' },
  depends = {
    'proteus.lib.ui',
    'proteus.core.settings',
    'proteus.core.commands',
    'proteus.editor.core',
    'proteus.tools.registry',
    'proteus.tools.diagnostics',
  },
  optional = { 'proteus.code.project', 'proteus.ui.notify' },
  activate = function (app)
    local settings = app.use ('settings')

    settings.define ('luau-lsp.enabled', {
      title = 'Run the Luau language server',
      type = 'boolean',
      default = true,
      description = 'Completion, hover help, go to definition and type problems in Luau files, from luau-lsp.',
    })
    settings.define ('luau-lsp.roblox', {
      title = 'Roblox mode',
      type = 'select',
      options = { 'auto', 'on', 'off' },
      default = 'auto',
      description = "Loads Roblox's types and API documentation. Auto turns it on for a folder with a Rojo project file or a .luaurc.",
    })
    settings.define ('luau-lsp.sourcemap', {
      title = 'Keep sourcemap.json up to date with Rojo',
      type = 'boolean',
      default = true,
      description = 'In Roblox mode, runs rojo sourcemap --watch on default.project.json while the server runs, so it knows the project.',
    })
    settings.define ('luau-lsp.format', {
      title = 'Format Luau with StyLua',
      type = 'boolean',
      default = true,
      description = 'Runs StyLua on Luau files when they are formatted or saved, when stylua is on the PATH.',
    })

    app.use ('ui').language (language)

    local project = app.try_use ('project')
    local workspace = disk.normalize (app.kernel.launch.workspace or '')

    ---@type LangLuau.Context
    local ctx = {
      app = app,
      settings = settings,
      editor = app.use ('editor'),
      desktop = app.platform == 'tauri',
      workspace = workspace,
      project_root = project and project.root () or nil,
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

    local server ---@type LangLuau.Server
    local formatter ---@type LangLuau.Formatter
    local tool = app.use ('tools').register ({
      id = 'luau-lsp',
      name = 'luau-lsp',
      description = 'Completion, hover help, go to definition and type problems for Luau.',
      program = 'luau-lsp',
      kind = 'server',
      install = 'rokit add JohnnyMorganz/luau-lsp',
      languages = { 'luau' },
      homepage = 'https://github.com/JohnnyMorganz/luau-lsp',
      settings = {
        'luau-lsp.enabled',
        'luau-lsp.roblox',
        'luau-lsp.sourcemap',
        'luau-lsp.format',
      },
      release = release,
      start = function ()
        server.start (nil)
      end,
      stop = function ()
        server.stop ()
      end,
      check = function ()
        formatter.reset ()
        server.stop ()
        server.start (nil)
      end,
    })
    server = server_module.install (ctx, tool)
    formatter = format_module.install (ctx, tool)

    app.use ('commands').register ({
      id = 'luau-lsp.restart',
      category = 'Luau',
      title = 'Restart the Language Server',
      icon = 'rotate-cw',
      run = function ()
        formatter.reset ()
        server.stop ()
        server.start (nil)
      end,
    })

    server.start (nil)
  end,
}
