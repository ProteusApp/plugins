-- lang.python: Python in the code editor.
--
-- basedpyright gives completion with documentation, hover help, go to definition (F12 or
-- Ctrl+click) and type problems. Ruff runs as a second server for lint problems, and its
-- Organize Imports and Fix All. `ruff format` formats Python files. Both servers start with
-- the first Python file, and each lists its problems under its own source.
--
-- The project's Python comes from the `python.interpreter` setting, the folder's pick in
-- Select Interpreter, a `.venv` or `venv` folder, or the PATH, in that order.
--
-- The parts live in lib/:
--   python    finds the project's Python
--   venv      where a virtual environment keeps its programs
--   select    the Select Interpreter command
--   pyright   basedpyright, through the app's shared client
--   config    the settings basedpyright asks for
--   program   finds basedpyright, from pip, npm or the PATH
--   launch    where npm puts basedpyright's script
--   ruff      Ruff's server, built from the app's lsp modules, minus the editor help
--   release   the Ruff download for Windows
--   edits     applies Ruff's edits to a file's text
--   format    Format Document with ruff format

local config = require ('lib.config') --[[@as LangPython.ConfigModule]]
local disk = require ('disk_paths') --[[@as DiskPaths]]
local format_module = require ('lib.format') --[[@as LangPython.FormatModule]]
local pyright_module = require ('lib.pyright') --[[@as LangPython.PyrightModule]]
local python_module = require ('lib.python') --[[@as LangPython.PythonModule]]
local ruff_module = require ('lib.ruff') --[[@as LangPython.RuffModule]]
local select_module = require ('lib.select') --[[@as LangPython.SelectModule]]

---A document, open or in front, as far as finding its folder goes.
---@class LangPython.DocPath
---@field path string
---@field external boolean

---What the parts of the plugin share.
---@class LangPython.Context
---@field app Proteus.App
---@field settings Proteus.Settings
---@field editor Proteus.Editor
---@field python LangPython.Python
---@field desktop boolean True in the desktop app, which can run programs.
---@field full_path fun(doc: LangPython.DocPath): string A document's full path on disk.
---@field root_for fun(doc: LangPython.DocPath?): string? The open folder, or else the file's folder.
---@field first_doc fun(): Proteus.DocInfo? The first open Python file.
---@field current_doc fun(): Proteus.CurrentDoc? The file in front.
---@field notify fun(level: 'info'|'warn'|'error', text: string) A pop-up, when ui.notify runs.

---@type Proteus.Plugin
return {
  name = 'Python',
  description = "Python with basedpyright and Ruff: completion, hover help, go to definition, type and lint problems, formatting, and the project's own interpreter.",
  version = '1.1.1',
  requires = { proteus = '>=0.3.0', features = { 'permissions' } },
  -- basedpyright, Ruff and Python are programs it runs, on files anywhere on disk. The
  -- tools registry downloads Ruff for it.
  permissions = { 'files', 'process' },
  depends = {
    'proteus.core.settings',
    'proteus.core.commands',
    'proteus.editor.core',
    'proteus.tools.registry',
    'proteus.tools.diagnostics',
  },
  optional = {
    'proteus.code.project',
    'proteus.ui.notify',
    'proteus.ui.palette',
  },
  activate = function (app)
    local settings = app.use ('settings')
    settings.define ('python.enabled', {
      title = 'Run basedpyright',
      type = 'boolean',
      default = true,
      description = 'Completion, hover help, go to definition and type problems in Python files.',
    })
    settings.define ('python.interpreter', {
      title = 'Python interpreter',
      type = 'string',
      default = '',
      description = "The full path of the Python to check code against, for every folder. Leave empty to use the folder's pick in Select Interpreter, then a .venv or venv folder, then the PATH.",
      sensitive = true,
    })
    settings.define ('python.type_checking', {
      title = 'Type checking',
      type = 'select',
      options = config.MODES,
      default = config.DEFAULT_MODE,
      description = "How strictly basedpyright checks types. A project's pyrightconfig.json or [tool.basedpyright] in pyproject.toml wins over this.",
    })
    settings.define ('python.ruff', {
      title = 'Run Ruff',
      type = 'boolean',
      default = true,
      description = "Lint problems from Ruff, with the project's ruff.toml or pyproject.toml.",
    })
    settings.define ('python.format', {
      title = 'Format Python with Ruff',
      type = 'boolean',
      default = true,
      description = 'Runs ruff format on Python files when they are formatted or saved.',
    })

    local editor = app.use ('editor')
    local workspace = disk.normalize (app.kernel.launch.workspace or '')

    ---@param doc LangPython.DocPath
    ---@return string
    local function full_path (doc)
      return doc.external and disk.normalize (doc.path)
        or disk.join (workspace, doc.path)
    end

    ---@type LangPython.Context
    local ctx = {
      app = app,
      settings = settings,
      editor = editor,
      python = python_module.new (app, settings),
      desktop = app.platform == 'tauri',
      full_path = full_path,
      root_for = function (doc)
        local project = app.try_use ('project')
        local root = project and project.root ()
        if root then
          return root
        end
        return doc and disk.parent (full_path (doc)) or nil
      end,
      first_doc = function ()
        for _, doc in ipairs (editor.docs ()) do
          if doc.language == 'python' then
            return doc
          end
        end
        return nil
      end,
      current_doc = function ()
        return editor.current ()
      end,
      notify = function (level, text)
        local n = app.try_use ('notify')
        if n then
          n[level] (text)
        end
      end,
    }

    local pyright = pyright_module.install (ctx)
    local ruff = ruff_module.install (ctx)
    format_module.install (ctx, ruff)

    ---True when the file in front is Python.
    ---@return boolean
    local function python_in_front ()
      local doc = editor.current ()
      return doc ~= nil and doc.language == 'python'
    end

    local commands = app.use ('commands')
    commands.register ({
      id = 'python.restart',
      category = 'Python',
      title = 'Restart the Language Servers',
      icon = 'rotate-cw',
      run = function ()
        pyright.restart ()
        ruff.restart ()
      end,
    })
    commands.register ({
      id = 'python.select_interpreter',
      category = 'Python',
      title = 'Select Interpreter',
      icon = 'terminal',
      run = select_module.new (ctx, function ()
        pyright.restart ()
        ruff.restart ()
      end),
    })
    commands.register ({
      id = 'python.organize_imports',
      category = 'Python',
      title = 'Organize Imports',
      icon = 'list-ordered',
      when = python_in_front,
      run = function ()
        ruff.action ('source.organizeImports.ruff', 'Organize Imports')
      end,
    })
    commands.register ({
      id = 'python.fix_all',
      category = 'Python',
      title = 'Fix All Ruff Problems',
      icon = 'wand-sparkles',
      when = python_in_front,
      run = function ()
        ruff.action ('source.fixAll.ruff', 'Fix All')
      end,
    })

    pyright.start (nil)
    ruff.start (nil)
  end,
}
