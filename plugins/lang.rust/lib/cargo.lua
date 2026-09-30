-- cargo: the Cargo panel in the bottom dock. Its buttons, and the Cargo commands, run check,
-- build, run, test or clippy in a real terminal, in the crate of the file in front.

local CSS = require ('lib.cargo_style') --[[@as string]]
local disk = require ('disk_paths') --[[@as DiskPaths]]

---@class LangRust.Job
---@field id string
---@field title string
---@field icon string
---@field args string[]

---@type LangRust.Job[]
local JOBS = {
  { id = 'check', title = 'Check', icon = 'circle-check', args = { 'check' } },
  { id = 'build', title = 'Build', icon = 'hammer', args = { 'build' } },
  { id = 'run', title = 'Run', icon = 'play', args = { 'run' } },
  { id = 'test', title = 'Test', icon = 'flask-conical', args = { 'test' } },
  { id = 'clippy', title = 'Clippy', icon = 'sparkles', args = { 'clippy' } },
}

---@class LangRust.CargoModule
local M = {}

---@param ctx LangRust.Context
function M.install (ctx)
  local app, ui, editor = ctx.app, ctx.ui, ctx.editor
  ui.css (CSS)
  local program = nil ---@type string?
  local term = nil ---@type Proteus.El?
  local buttons = {} ---@type table<string, Proteus.El>
  local check ---@type fun()
  local where = ui.span ({ class = 'cargo-where' })
  local body = ui.div ({
    class = 'cargo-body',
    ui.div ({
      class = 'cargo-empty',
      'Pick a job. It runs in the crate of the file in front.',
    }),
  })

  local tool = ctx.tools.register ({
    id = 'cargo',
    name = 'Cargo',
    description = 'Builds, runs and tests Rust crates from the Cargo panel.',
    program = 'cargo',
    kind = 'command',
    install = 'Install Rust from https://rustup.rs',
    homepage = 'https://doc.rust-lang.org/cargo/',
    check = function ()
      check ()
    end,
  })

  ---The crate to run a job in: the one the file in front belongs to, or the open folder's.
  ---@param cb fun(crate: string?)
  local function current_crate (cb)
    local doc = editor.current ()
    local dir = ctx.project_root
    if doc then
      dir = disk.parent (
        doc.external and disk.normalize (doc.path)
          or disk.join (ctx.workspace, doc.path)
      )
    end
    if not dir then
      cb (nil)
      return
    end
    ctx.crates.of (dir, function (crate)
      if not crate and ctx.project_root then
        ctx.crates.below (ctx.project_root, cb)
      else
        cb (crate)
      end
    end)
  end

  ---@param job LangRust.Job
  local function run (job)
    local exe = program
    if not exe then
      ctx.notify (
        'error',
        'Cargo is not on the PATH. Install Rust from rustup.rs.'
      )
      return
    end
    current_crate (function (crate)
      if not crate then
        ctx.notify (
          'warn',
          'There is no Cargo.toml above the file in front, so there is nothing to '
            .. job.id
            .. '.'
        )
        return
      end
      ctx.views.show ('cargo')
      where:text (disk.native (crate, app.os))
      for id, button in pairs (buttons) do
        button:class ('active', id == job.id)
      end
      local args = { table.unpack (job.args) }
      -- The panel is a real terminal, so colour stays on.
      args[#args + 1] = '--color=always'
      if term then
        term:widget ('set_program', exe, args, crate)
        term:widget ('restart')
        return
      end
      term = ui.widget ('terminal', { program = exe, args = args, cwd = crate })
      body:set_children ({ ui.div ({ class = 'cargo-pane', term }) })
    end)
  end

  local bar = ui.div ({ class = 'cargo-bar' })
  for i, job in ipairs (JOBS) do
    buttons[job.id] = ui.button ({
      class = 'cargo-job',
      title = 'cargo ' .. table.concat (job.args, ' '),
      ui.icon (job.icon, 13),
      job.title,
      onclick = function ()
        run (job)
        return nil
      end,
    })
    bar:append (buttons[job.id])
    ctx.commands.register ({
      id = 'rust.cargo_' .. job.id,
      category = 'Cargo',
      title = job.title,
      icon = job.icon,
      menu = 'Run',
      group = 'cargo',
      order = 60 + i,
      when = function ()
        return program ~= nil
      end,
      run = function ()
        run (job)
      end,
    })
  end
  bar:append (where)
  bar:append (ui.button ({
    class = 'cargo-job',
    title = 'Stop the job',
    ui.icon ('square', 13),
    onclick = function ()
      if term then
        term:widget ('stop')
      end
      return nil
    end,
  }))

  ctx.views.add ('bottom', {
    id = 'cargo',
    title = 'Cargo',
    icon = 'package',
    order = 30,
    content = ctx.desktop and ui.div ({ class = 'cargo', bar, body })
      or ui.div ({ class = 'cargo-empty', 'Cargo needs the desktop app.' }),
  })

  -- Looks for Cargo, now and again from the Tools panel, such as after Rust was installed.
  check = function ()
    program = nil
    if not ctx.desktop then
      tool.set_state ('missing', 'running programs needs the desktop app')
      return
    end
    app.process.which ('cargo', function (found)
      tool.set_path (found)
      if not found then
        tool.set_state ('missing', 'cargo is not on the PATH')
        return
      end
      program = found
      app.process.run (found, { '--version' }, nil, function (result)
        tool.set_version (result and (result.stdout:gsub ('%s+$', '')) or nil)
        tool.set_state ('ready')
      end)
    end)
  end
  check ()
end

return M
