-- pyright: runs basedpyright through the app's shared language server client. It gives the
-- editor completion, hover help and go to definition for Python, and lists type problems
-- under the `python` source. It starts with the first Python file. Changing the interpreter
-- restarts it, and changing the type checking mode tells the running server.

local client_module = require ('lsp.client') --[[@as Lsp.ClientModule]]
local config = require ('lib.config') --[[@as LangPython.ConfigModule]]
local program_module = require ('lib.program') --[[@as LangPython.ProgramModule]]

---@class LangPython.Pyright
---@field start fun(doc: Proteus.DocInfo?)
---@field stop fun()
---@field restart fun()

---@class LangPython.PyrightModule
local M = {}

-- How each way of finding Python reads in the log.
local HOW = {
  setting = 'the python.interpreter setting',
  picked = 'Select Interpreter',
  venv = "the project's virtual environment",
  path = 'the PATH',
}

---@param ctx LangPython.Context
---@return LangPython.Pyright
function M.install (ctx)
  local app, settings = ctx.app, ctx.settings
  local starting = false
  local server ---@type LangPython.Pyright

  ---@type LangPython.ConfigState
  local state = { mode = config.mode (settings.get ('python.type_checking')) }

  local tool = app.use ('tools').register ({
    id = 'basedpyright',
    name = 'basedpyright',
    description = 'Completion, hover help, go to definition and type problems for Python.',
    program = 'basedpyright-langserver',
    kind = 'server',
    install = 'npm install --global basedpyright, or pip install basedpyright',
    npm = {
      packages = { 'basedpyright@1.40.1' },
      bin = 'basedpyright-langserver',
    },
    languages = { 'python' },
    homepage = 'https://docs.basedpyright.com',
    settings = {
      'python.enabled',
      'python.interpreter',
      'python.type_checking',
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

  local client = client_module.new (app, {
    name = 'basedpyright',
    language = 'python',
    source = 'python',
    tool = tool,
    config = function (section)
      return config.section (section, state)
    end,
  })

  server = {
    start = function (doc)
      if client.running () or starting then
        return
      end
      if settings.get ('python.enabled') ~= true then
        tool.set_state ('stopped', 'switched off in Settings (python.enabled)')
        return
      end
      if not ctx.desktop then
        tool.set_state ('missing', 'running programs needs the desktop app')
        return
      end
      doc = doc or ctx.first_doc ()
      local root = doc and ctx.root_for (doc)
      if not root then
        tool.set_state ('stopped', 'starts when a Python file opens')
        return
      end
      starting = true
      ctx.python.find (root, function (found)
        state.python = found and found.path or nil
        if found then
          tool.log (
            'info',
            'Python ' .. found.path .. ' from ' .. HOW[found.how]
          )
        else
          tool.log ('info', 'no Python found, so imports cannot be followed')
        end
        if ctx.untrusted then
          tool.log (
            'info',
            "the folder's .venv and node_modules wait until you trust the folder (File: Trust This Folder)"
          )
        end
        program_module.find (
          app,
          tool,
          not ctx.untrusted and root or nil,
          state.python,
          function (launch, why)
            starting = false
            if not launch then
              tool.set_path (nil)
              tool.set_state ('missing', why)
              return
            end
            tool.set_path (launch.script)
            client.start (launch.program, launch.args, root)
          end
        )
      end)
    end,
    stop = function ()
      client.stop ()
    end,
    restart = function ()
      client.stop ()
      server.start (nil)
    end,
  }

  app.on ('editor:opened', function (doc)
    ---@cast doc Proteus.DocInfo
    if doc.language == 'python' and not client.running () then
      server.start (doc)
    end
  end)

  for _, key in ipairs ({ 'python.enabled', 'python.interpreter' }) do
    local first = true
    settings.watch (key, function ()
      if first then
        first = false
        return
      end
      server.restart ()
    end)
  end

  -- The server reads the mode again when told its settings changed, with no restart.
  settings.watch ('python.type_checking', function (value)
    state.mode = config.mode (value)
    if client.ready () then
      client.notify (
        'workspace/didChangeConfiguration',
        { settings = config.all (state) }
      )
    end
  end)

  return server
end

return M
