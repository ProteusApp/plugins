-- lang.tailwind: Tailwind CSS class names in the code editor, with Tailwind's own language
-- server.
--
-- Classes live in files that other plugins serve: HTML, CSS, JavaScript, TypeScript, JSX,
-- TSX, Vue, Svelte and Markdown. The editor keeps one helper per language, and those plugins
-- own it. So this plugin runs the Tailwind server beside theirs, as a guest. It keeps the
-- server's copy of every such file in step, and adds class completion through `completion`
-- file associations, which each host plugin asks and shows before its own items. The
-- server's problems, such as two classes that set the same property, go to the Problems
-- panel.
--
-- The server starts only when the open folder uses Tailwind: a `tailwind.config` file, or a
-- stylesheet that imports `tailwindcss`, or `tailwindcss` in a package.json.
--
-- The parts live in lib/:
--   detect      whether a folder uses Tailwind
--   languages   which files the server hears about, and what it calls each one
--   config      the server's settings, from the plugin's
--   documents   keeps the server's copy of each open file in step
--   client      the conversation with the server
--   server      starts and stops the server
--   completion  the completion associations
--   items       turns the server's items into the editor's
--   program     finds node and the server's script
--   launch      where the server's script may be

local client_module = require ('lib.client') --[[@as LangTailwind.ClientModule]]
local completion = require ('lib.completion') --[[@as LangTailwind.CompletionModule]]
local config = require ('lib.config') --[[@as LangTailwind.ConfigModule]]
local disk = require ('disk_paths') --[[@as DiskPaths]]
local server_module = require ('lib.server') --[[@as LangTailwind.ServerModule]]

-- The server asks for its settings under this name, which comes from its VS Code extension.
local SECTION = 'tailwindCSS'

---What the parts of the plugin share.
---@class LangTailwind.Context
---@field app Proteus.App
---@field settings Proteus.Settings
---@field editor Proteus.Editor
---@field to_disk fun(doc: Proteus.DocInfo): string A document's full path.

---@type Proteus.Plugin
return {
  name = 'Tailwind CSS',
  description = 'Tailwind CSS class completion, with the CSS each class makes, and problems such as conflicting classes, in HTML, CSS, JSX, TSX, Vue and Svelte files.',
  version = '1.1.0',
  requires = { proteus = '>=0.3.0', features = { 'permissions' } },
  -- The language server is a program it runs. It reads files anywhere on disk, and the
  -- plugin searches the open folder for Tailwind.
  permissions = { 'files', 'process' },
  depends = {
    'proteus.core.settings',
    'proteus.core.commands',
    'proteus.core.files',
    'proteus.editor.core',
    'proteus.tools.registry',
    'proteus.tools.diagnostics',
  },
  optional = { 'proteus.code.project', 'proteus.ui.notify' },
  activate = function (app)
    local settings = app.use ('settings')
    local editor = app.use ('editor')

    settings.define ('tailwind.enabled', {
      title = 'Run the Tailwind CSS language server',
      type = 'boolean',
      default = true,
      description = 'Class completion and problems in folders that use Tailwind CSS.',
    })
    settings.define ('tailwind.class_attributes', {
      title = 'Class attributes',
      type = 'json',
      default = { 'class', 'className', 'ngClass', 'class:list' },
      description = 'The attributes whose values hold classes, such as ["class", "className"].',
    })
    settings.define ('tailwind.class_regex', {
      title = 'Class patterns',
      type = 'json',
      default = {},
      description = 'Regular expressions for other places classes go, such as calls to cva or clsx. Each one captures the classes. A pair of them finds the call first, then the classes inside it.',
    })
    settings.define ('tailwind.lint', {
      title = 'Problem levels',
      type = 'json',
      default = {},
      description = 'A level for each kind of problem: "ignore", "warning" or "error", such as {"cssConflict": "error"}. A kind left out keeps the server\'s level.',
    })

    ---@return table
    local function section ()
      return config.section (
        settings.get ('tailwind.class_attributes'),
        settings.get ('tailwind.class_regex'),
        settings.get ('tailwind.lint')
      )
    end

    local workspace = disk.normalize (app.kernel.launch.workspace or '')

    ---@type LangTailwind.Context
    local ctx = {
      app = app,
      settings = settings,
      editor = editor,
      to_disk = function (doc)
        return doc.external and disk.normalize (doc.path)
          or disk.join (workspace, doc.path)
      end,
    }

    local server ---@type LangTailwind.Server
    local tool = app.use ('tools').register ({
      id = 'tailwindcss-language-server',
      name = 'Tailwind CSS',
      description = 'Class completion and problems for Tailwind CSS.',
      program = 'tailwindcss-language-server',
      kind = 'server',
      install = 'npm install --global @tailwindcss/language-server',
      npm = {
        packages = { '@tailwindcss/language-server@0.16.0' },
        bin = 'tailwindcss-language-server',
      },
      -- None until the open folder turns out to use Tailwind CSS.
      languages = {},
      homepage = 'https://github.com/tailwindlabs/tailwindcss-intellisense',
      settings = {
        'tailwind.enabled',
        'tailwind.class_attributes',
        'tailwind.class_regex',
        'tailwind.lint',
      },
      start = function ()
        server.start (nil)
      end,
      stop = function ()
        server.stop ()
      end,
      check = function ()
        server.stop ()
        server.forget ()
        server.start (nil)
      end,
    })

    local client = client_module.new (app, {
      tool = tool,
      config = function (name)
        return name == SECTION and section () or nil
      end,
      notify = function (text)
        local n = app.try_use ('notify')
        if n then
          n.warn (text)
        end
      end,
    })
    server = server_module.install (ctx, tool, client)
    completion.install (app, app.use ('files'), client)

    -- The server keeps the settings it asked for, until it hears they changed.
    for _, key in ipairs ({
      'tailwind.class_attributes',
      'tailwind.class_regex',
      'tailwind.lint',
    }) do
      local first = true
      settings.watch (key, function ()
        if first then
          first = false
          return
        end
        if client.ready () then
          client.notify ('workspace/didChangeConfiguration', {
            settings = { [SECTION] = section () },
          })
        end
      end)
    end

    app.use ('commands').register ({
      id = 'tailwind.restart',
      category = 'Tailwind CSS',
      title = 'Restart the Language Server',
      icon = 'rotate-cw',
      run = function ()
        server.stop ()
        server.forget ()
        server.start (nil)
      end,
    })

    server.start (nil)
  end,
}
