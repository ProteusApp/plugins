-- rustfmt: formats Rust files. It runs in the file's folder, so rustfmt finds the crate's
-- rustfmt.toml there or above, and it takes the edition from the nearest Cargo.toml. The
-- tools registry finds it, reads its version and runs it. In a folder that is not trusted it
-- formats nothing, since a rust-toolchain.toml there can name the program rustup starts.

local disk = require ('disk_paths') --[[@as DiskPaths]]

---@class LangRust.RustfmtModule
local M = {}

---@param ctx LangRust.Context
function M.install (ctx)
  local rustfmt = ctx.tools.command ({
    id = 'rustfmt',
    name = 'rustfmt',
    description = 'Formats Rust code the same way every time.',
    program = 'rustfmt',
    kind = 'command',
    install = 'rustup component add rustfmt',
    homepage = 'https://github.com/rust-lang/rustfmt',
    settings = { 'rust.rustfmt_enabled' },
    enabled = 'rust.rustfmt_enabled',
  })

  local told = false
  ctx.editor.add_formatter (
    'rust',
    rustfmt.formatter ({
      in_folder = true,
      args = function (_, path, cb)
        if ctx.untrusted then
          if not told then
            told = true
            rustfmt.tool.log (
              'info',
              'waits until you trust this folder (File: Trust This Folder)'
            )
          end
          cb (nil)
          return
        end
        ctx.crates.edition (disk.parent (path), function (edition)
          cb ({ '--edition', edition, '--emit', 'stdout' })
        end)
      end,
    })
  )
  ctx.settings.watch ('rust.rustfmt_enabled', function ()
    rustfmt.check ()
  end)
end

return M
