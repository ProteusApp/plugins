-- lang.rust: Rust in the code editor.
--
-- rust-analyzer gives completion with documentation, hover help, go to definition (F12 or
-- Ctrl+click) and problems, and checks the crate with Cargo after each save. rustfmt formats
-- Rust files. The Cargo panel runs check, build, run, test and clippy. Cargo.toml and Rust's
-- other TOML files get their JSON schemas as file associations, which lang.toml uses.
--
-- The parts live in lib/:
--   server    rust-analyzer, through the shared client in the app's lsp library
--   release   the rust-analyzer download for each platform
--   crates    finds a file's crate and edition from Cargo.toml files
--   rustfmt   the formatter
--   cargo     the Cargo panel and its commands
--   registry  crate names and versions in Cargo.toml, from crates.io

local cargo_module = require ('lib.cargo') --[[@as LangRust.CargoModule]]
local crates_module = require ('lib.crates') --[[@as LangRust.CratesModule]]
local disk = require ('disk_paths') --[[@as DiskPaths]]
local registry_module = require ('lib.registry') --[[@as LangRust.RegistryModule]]
local rustfmt_module = require ('lib.rustfmt') --[[@as LangRust.RustfmtModule]]
local server_module = require ('lib.server') --[[@as LangRust.ServerModule]]

-- JSON schemas for Rust's own TOML files, from schemastore.org.
local SCHEMAS = {
  ['Cargo.toml'] = 'https://www.schemastore.org/cargo.json',
  ['.cargo/config.toml'] = 'https://www.schemastore.org/cargo-config.json',
  ['.cargo/config'] = 'https://www.schemastore.org/cargo-config.json',
  ['rustfmt.toml'] = 'https://www.schemastore.org/rustfmt.json',
  ['.rustfmt.toml'] = 'https://www.schemastore.org/rustfmt.json',
  ['rust-toolchain.toml'] = 'https://www.schemastore.org/rust-toolchain.json',
}

---What the parts of the plugin share.
---@class LangRust.Context
---@field app Proteus.App
---@field settings Proteus.Settings
---@field editor Proteus.Editor
---@field tools Proteus.Tools
---@field commands Proteus.Commands
---@field ui Proteus.UI
---@field views Proteus.Views
---@field desktop boolean True in the desktop app, which can run programs.
---@field workspace string The workspace folder, with `/`.
---@field project_root? string The folder open in the Code Editor.
---@field crates LangRust.Crates
---@field full_path fun(doc: Proteus.DocInfo): string A document's full path on disk.
---@field notify fun(level: 'info'|'warn'|'error', text: string) A pop-up, when ui.notify runs.

---@type Proteus.Plugin
return {
  name = 'Rust',
  description = 'Rust with rust-analyzer, rustfmt and Cargo: completion, hover help, go to definition, problems, formatting and a Cargo panel.',
  version = '1.0.2',
  requires = { proteus = '>=0.2.0', features = { 'permissions' } },
  -- The language server and Cargo are programs it runs and downloads, on files anywhere on disk.
  permissions = { 'net', 'files', 'process' },
  depends = {
    'core.settings',
    'core.commands',
    'core.files',
    'lib.ui',
    'ui.views',
    'editor.core',
    'tools.registry',
    'tools.diagnostics',
  },
  optional = { 'code.project', 'ui.notify' },
  activate = function (app)
    local settings = app.use ('settings')
    settings.define ('rust.analyzer_enabled', {
      title = 'Run rust-analyzer',
      type = 'boolean',
      default = true,
      description = 'Completion, hover help, go to definition and problems in Rust files.',
    })
    settings.define ('rust.analyzer_path', {
      title = 'rust-analyzer program',
      type = 'string',
      default = '',
      description = 'Leave empty to use the one on the PATH, or else a download.',
    })
    settings.define ('rust.check_command', {
      title = 'Check on save with',
      type = 'select',
      options = { 'check', 'clippy' },
      default = 'check',
      description = 'The Cargo command rust-analyzer runs after each save to find problems.',
    })
    settings.define ('rust.rustfmt_enabled', {
      title = 'Format Rust with rustfmt',
      type = 'boolean',
      default = true,
      description = 'Runs rustfmt on Rust files when they are formatted or saved.',
    })

    local project = app.try_use ('project')
    local workspace = disk.normalize (app.kernel.launch.workspace or '')

    ---@type LangRust.Context
    local ctx = {
      app = app,
      settings = settings,
      editor = app.use ('editor'),
      tools = app.use ('tools'),
      commands = app.use ('commands'),
      ui = app.use ('ui'),
      views = app.use ('views'),
      desktop = app.platform == 'tauri',
      workspace = workspace,
      project_root = project and project.root () or nil,
      crates = crates_module.new (app),
      full_path = function (doc)
        return doc.external and disk.normalize (doc.path)
          or disk.join (workspace, doc.path)
      end,
      notify = function (level, text)
        local n = app.try_use ('notify')
        if n then
          n[level] (text)
        end
      end,
    }

    local server = server_module.install (ctx)
    rustfmt_module.install (ctx)
    cargo_module.install (ctx)
    local files = app.use ('files')
    for pattern, schema in pairs (SCHEMAS) do
      files.associate ({ kind = 'schema', pattern = pattern, value = schema })
    end
    files.associate ({
      kind = 'completion',
      pattern = 'Cargo.toml',
      value = registry_module.new (app),
    })

    ctx.commands.register ({
      id = 'rust.restart',
      category = 'Rust',
      title = 'Restart rust-analyzer',
      icon = 'rotate-cw',
      menu = 'Run',
      group = 'tools',
      order = 51,
      run = function ()
        server.stop ()
        server.start (nil)
      end,
    })

    -- The server starts now for a Rust file already open, or for a folder that holds a crate.
    -- Otherwise it waits for the first Rust file.
    local rust_open = false
    for _, doc in ipairs (ctx.editor.docs ()) do
      rust_open = rust_open or doc.language == 'rust'
    end
    if rust_open or not ctx.project_root then
      server.start (nil)
    elseif ctx.desktop then
      ctx.crates.below (ctx.project_root, function (crate)
        if crate then
          server.start (nil)
        end
      end)
    end
  end,
}
