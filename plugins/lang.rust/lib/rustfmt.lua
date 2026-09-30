-- rustfmt: formats Rust files. It runs in the file's folder, so rustfmt finds the crate's
-- rustfmt.toml there or above, and it takes the edition from the nearest Cargo.toml.

local disk = require ('disk_paths') --[[@as DiskPaths]]

---@class LangRust.RustfmtModule
local M = {}

---@param ctx LangRust.Context
function M.install (ctx)
  local app, settings = ctx.app, ctx.settings
  local program = nil ---@type string?
  local check ---@type fun()

  local tool = ctx.tools.register ({
    id = 'rustfmt',
    name = 'rustfmt',
    description = 'Formats Rust code the same way every time.',
    program = 'rustfmt',
    kind = 'command',
    install = 'rustup component add rustfmt',
    homepage = 'https://github.com/rust-lang/rustfmt',
    settings = { 'rust.rustfmt_enabled' },
    check = function ()
      check ()
    end,
  })

  check = function ()
    program = nil
    if not ctx.desktop then
      tool.set_state ('missing', 'running programs needs the desktop app')
      return
    end
    app.process.which ('rustfmt', function (found)
      tool.set_path (found)
      if not found then
        tool.set_state ('missing', 'rustfmt is not on the PATH')
        return
      end
      app.process.run (found, { '--version' }, nil, function (result)
        if not result or result.code ~= 0 then
          tool.set_state (
            'missing',
            result and result.stderr:match ('[^\r\n]+') or nil
          )
          return
        end
        program = found
        tool.set_version ((result.stdout:gsub ('%s+$', '')))
        if settings.get ('rust.rustfmt_enabled') == true then
          tool.set_state ('ready')
        else
          tool.set_state (
            'stopped',
            'switched off in Settings (rust.rustfmt_enabled)'
          )
        end
      end)
    end)
  end

  ---@param doc Proteus.DocInfo
  ---@param text string
  ---@param done fun(text: string?)
  local function format (doc, text, done)
    local exe = program
    if not exe or settings.get ('rust.rustfmt_enabled') ~= true then
      done (nil)
      return
    end
    local dir = disk.parent (ctx.full_path (doc))
    ctx.crates.edition (dir, function (edition)
      local args = { '--edition', edition, '--emit', 'stdout' }
      app.process.run (
        exe,
        args,
        { cwd = dir, stdin = text },
        function (result, err)
          if err or not result then
            tool.log ('err', tostring (err))
            done (nil)
          elseif result.code ~= 0 then
            tool.log ('err', doc.path .. ': ' .. result.stderr:gsub ('%s+$', ''))
            ctx.notify (
              'warn',
              'rustfmt could not format '
                .. disk.name (doc.path)
                .. '. The Tools panel has its message.'
            )
            done (nil)
          else
            tool.log (
              'info',
              'formatted ' .. doc.path .. ' as edition ' .. edition
            )
            done (result.stdout)
          end
        end
      )
    end)
  end

  ctx.editor.add_formatter ('rust', format)
  settings.watch ('rust.rustfmt_enabled', check)
end

return M
