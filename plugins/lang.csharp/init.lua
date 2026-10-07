-- lang.csharp: C# for Godot 4 .NET projects in the Code Editor.
--
-- csharp-ls gives completion with documentation, hover help, go to definition (F12) and
-- problems as you type. It loads the project's .sln after `dotnet restore`, so Godot's own
-- API completes along with your scripts. The plugin installs csharp-ls with dotnet when it is
-- not on the PATH.
--
-- The Godot side: Build puts `dotnet build` errors in the Problems panel, Run builds and
-- starts the game, and Open in Godot starts the Godot editor on the project. Godot can open
-- scripts here too: its external editor setting starts Proteus with `--goto file:line:col`,
-- and Use Proteus as Godot's Editor shows what to type there.
--
-- The parts live in lib/:
--   godot    project.godot, .csproj, `--goto` and build output, with nothing that calls the host
--   project  finds the Godot project above a file
--   program  finds or installs csharp-ls
--   server   csharp-ls, through the shared client in the app's lsp library
--   build    dotnet build, the game and the Godot editor

local build_module = require ('lib.build') --[[@as LangCsharp.BuildModule]]
local disk = require ('disk_paths')
local godot = require ('lib.godot') --[[@as LangCsharp.GodotModule]]
local project_module = require ('lib.project') --[[@as LangCsharp.ProjectModule]]
local server_module = require ('lib.server') --[[@as LangCsharp.ServerModule]]

---What the parts of the plugin share.
---@class LangCsharp.Context
---@field app Proteus.App
---@field settings Proteus.Settings
---@field editor Proteus.Editor
---@field tools Proteus.Tools
---@field projects LangCsharp.Projects
---@field workspace string The workspace folder, with `/`.
---@field project_root? string The folder open in the Code Editor.
---@field notify fun(level: 'info'|'success'|'warn'|'error', text: string, opts?: Proteus.NotifyOptions) A pop-up, when ui.notify runs.

---@type Proteus.Plugin
return {
  name = 'C# for Godot',
  description = 'C# for Godot 4 .NET projects: completion of your scripts and the Godot API with csharp-ls, build errors in Problems, run the game, and open scripts from Godot.',
  version = '1.0.0',
  requires = { proteus = '>=0.3.0', features = { 'permissions' } },
  -- csharp-ls, dotnet and Godot are programs it runs, on project files anywhere on disk.
  permissions = { 'files', 'process' },
  depends = {
    'proteus.lib.ui',
    'proteus.core.settings',
    'proteus.core.commands',
    'proteus.editor.core',
    'proteus.tools.registry',
    'proteus.tools.diagnostics',
    -- The Code Editor profile does not list it, and Use Proteus as Godot's Editor needs it.
    'proteus.ui.overlays',
  },
  optional = {
    'proteus.code.project',
    'proteus.ui.notify',
  },
  activate = function (app)
    local ui = app.use ('ui')
    local settings = app.use ('settings')
    local commands = app.use ('commands')
    local editor = app.use ('editor')

    settings.define ('csharp.server_enabled', {
      title = 'Run csharp-ls',
      type = 'boolean',
      default = true,
      description = 'Completion, hover help, go to definition and problems in C# files.',
    })
    settings.define ('csharp.server_path', {
      title = 'csharp-ls program',
      type = 'string',
      default = '',
      description = 'Leave empty to use the one on the PATH, or else the copy this plugin installs.',
    })
    settings.define ('csharp.dotnet_path', {
      title = 'dotnet program',
      type = 'string',
      default = '',
      description = 'Leave empty to use dotnet on the PATH.',
    })
    settings.define ('csharp.godot_args', {
      title = 'Extra Godot arguments',
      type = 'string',
      default = '',
      description = 'Added when Proteus starts the game or the Godot editor, such as --rendering-driver opengl3 on a computer without Vulkan.',
    })
    settings.define ('csharp.godot_path', {
      title = 'Godot program',
      type = 'string',
      default = '',
      description = 'The full path of the .NET build of Godot 4. When empty, godot-mono, godot4-mono, godot or godot4 on the PATH.',
    })

    local project = app.try_use ('project')
    ---@type LangCsharp.Context
    local ctx = {
      app = app,
      settings = settings,
      editor = editor,
      tools = app.use ('tools'),
      projects = project_module.new (app),
      workspace = disk.normalize (app.kernel.launch.workspace or ''),
      project_root = project and project.root () or nil,
      notify = function (level, text, opts)
        local n = app.try_use ('notify')
        if n then
          n[level] (text, opts)
        else
          app.log (text)
        end
      end,
    }

    local server = server_module.install (ctx)
    local build = build_module.install (ctx, server)

    ---Shows what to type into Godot's Editor Settings so that it opens scripts here.
    ---@param exec string The Proteus program.
    local function show_setup (exec)
      local profile = app.kernel.profile ()
      local args = godot.exec_args (profile and profile.id or 'code')
      local overlays = app.use ('overlays')
      ---@param label string
      ---@param value string
      ---@return Proteus.El
      local function field (label, value)
        return ui.div ({
          style = { margin = '10px 0 0' },
          ui.div ({
            style = { ['font-size'] = '12px', color = 'var(--fg-muted)' },
            label,
          }),
          ui.div ({
            style = {
              display = 'flex',
              gap = '8px',
              ['align-items'] = 'center',
            },
            ui.code ({
              style = {
                flex = '1',
                ['min-width'] = '0',
                ['overflow-wrap'] = 'anywhere',
                padding = '6px 8px',
                ['border-radius'] = '6px',
                background = 'var(--bg-alt)',
              },
              value,
            }),
            ui.button ({
              'Copy',
              icon = 'copy',
              onclick = function ()
                app.system.clipboard (value)
                ctx.notify ('success', 'Copied ' .. label .. '.')
                return nil
              end,
            }),
          }),
        })
      end
      overlays.modal ({
        title = "Use Proteus as Godot's Editor",
        width = 560,
        body = {
          ui.p ({
            style = { margin = '0', ['line-height'] = '1.5' },
            'In Godot, open Editor > Editor Settings, turn on Advanced Settings, and go to Dotnet > Editor. Set External Editor to Custom, then fill in these two. Godot then opens a C# script here at the line you clicked.',
          }),
          field ('Exec Path', exec),
          not disk.is_absolute (exec)
              and ui.p ({
                style = {
                  margin = '6px 0 0',
                  ['font-size'] = '12px',
                  color = 'var(--warning)',
                },
                'This is how Proteus was started, which Godot cannot follow. Use the full path of the Proteus program instead.',
              })
            or nil,
          field ('Exec Path Args', args),
        },
        buttons = { { label = 'Done', variant = 'primary' } },
      })
    end

    ---Shows what to type into Godot, with the full path of a Proteus started by name.
    local function setup ()
      local exec = tostring (app.kernel.launch.args[1] or 'proteus')
      if disk.is_absolute (exec) or exec:find ('[/\\]') then
        show_setup (exec)
        return
      end
      app.process.which (exec, function (found)
        show_setup (found or exec)
      end)
    end

    for _, spec in ipairs ({
      {
        id = 'csharp.build',
        title = 'Godot: Build C#',
        icon = 'hammer',
        run = function ()
          build.build ()
        end,
      },
      {
        id = 'csharp.run',
        title = 'Godot: Run the Game',
        icon = 'play',
        run = build.run,
      },
      {
        id = 'csharp.stop',
        title = 'Godot: Stop the Game',
        icon = 'square',
        run = build.stop,
      },
      {
        id = 'csharp.editor',
        title = 'Godot: Open in the Godot Editor',
        icon = 'app-window',
        run = build.open_editor,
      },
      {
        id = 'csharp.setup',
        title = "Godot: Use Proteus as Godot's Editor…",
        icon = 'link',
        run = setup,
      },
      {
        id = 'csharp.install',
        title = 'C#: Install csharp-ls',
        icon = 'download',
        run = server.install,
      },
      {
        id = 'csharp.restart',
        title = 'C#: Restart csharp-ls',
        icon = 'rotate-cw',
        run = server.restart,
      },
    }) do
      commands.register ({
        id = spec.id,
        category = 'C#',
        title = spec.title,
        icon = spec.icon,
        menu = 'Run',
        group = 'csharp',
        run = spec.run,
      })
    end

    -- Godot started this window to open a script: `--goto <file>:<line>:<col>`.
    local target = godot.goto_arg (app.kernel.launch.args or {})
    if target then
      editor.open_external (disk.normalize (target.path), {
        line = target.line,
        col = target.col,
      })
    end

    server.start (nil)
  end,
}
