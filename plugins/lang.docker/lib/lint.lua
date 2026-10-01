-- lint: runs Hadolint on each Dockerfile as it opens and each time it is saved, while
-- `docker.hadolint` is on. Its findings go to the Problems panel under `hadolint`, beside the
-- language server's own. Hadolint runs in the file's folder, so it finds a `.hadolint.yaml`
-- there.

local disk = require ('disk_paths') --[[@as DiskPaths]]
local hadolint = require ('lib.hadolint') --[[@as LangDocker.HadolintModule]]

-- The diagnostics source, and the editor's language for Dockerfiles.
local SOURCE = 'hadolint'
local LANGUAGE = 'dockerfile'

---@class LangDocker.Lint
---@field check fun() Looks for Hadolint again, then checks every open Dockerfile.

---@class LangDocker.LintModule
local M = {}

---@param ctx LangDocker.Context
---@param tool Proteus.ToolHandle The Hadolint tool.
---@return LangDocker.Lint
function M.install (ctx, tool)
  local app, settings, editor = ctx.app, ctx.settings, ctx.editor
  local diagnostics = app.use ('diagnostics')
  local reported = {} ---@type table<string, true> Paths with findings shown.

  ---@return boolean
  local function enabled ()
    return settings.get ('docker.hadolint') == true
  end

  ---@param path string
  ---@param list Proteus.Diagnostic[]
  local function report (path, list)
    reported[path] = true
    diagnostics.set (SOURCE, path, list)
  end

  local function clear_all ()
    for path in pairs (reported) do
      diagnostics.set (SOURCE, path, {})
    end
    reported = {}
  end

  ---Runs Hadolint on the document's text, and shows what it finds.
  ---@param doc Proteus.DocInfo
  ---@param program string
  local function run (doc, program)
    local text = doc.text ()
    local opts = { cwd = disk.parent (ctx.paths.to_disk (doc)), stdin = text }
    local args = { '--format', 'json', '-' }
    app.process.run (program, args, opts, function (result, err)
      if err or not result then
        tool.log ('err', tostring (err))
        return
      end
      -- Hadolint exits with 1 when it finds an error, so the output counts, not the code.
      local ok, findings = pcall (app.json.decode, result.stdout)
      if not ok or type (findings) ~= 'table' then
        tool.log ('err', doc.path .. ': ' .. result.stderr:gsub ('%s+$', ''))
        return
      end
      if enabled () then
        report (doc.path, hadolint.diagnostics (findings, text))
      end
    end)
  end

  ---Checks one document, when it is a Dockerfile and the setting is on.
  ---@param doc Proteus.DocInfo
  local function lint (doc)
    if doc.language ~= LANGUAGE or not enabled () then
      return
    end
    tool.locate (function (program)
      if not program then
        tool.set_state ('missing', 'hadolint is not on the PATH')
        return
      end
      tool.set_path (program)
      tool.set_state ('ready')
      run (doc, program)
    end)
  end

  local function lint_all ()
    for _, doc in ipairs (editor.docs ()) do
      lint (doc)
    end
  end

  ---Shows whether Hadolint is there, without offering the download.
  local function look ()
    app.process.which ('hadolint', function (found)
      if found then
        tool.set_path (found)
        tool.set_state ('ready')
        return
      end
      tool.cached (function (cached)
        tool.set_path (cached)
        if cached then
          tool.set_state ('ready')
        else
          tool.set_state ('missing', 'hadolint is not on the PATH')
        end
      end)
    end)
  end

  app.on ('editor:opened', function (doc)
    lint (doc --[[@as Proteus.DocInfo]])
  end)

  app.on ('editor:saved', function (path)
    for _, doc in ipairs (editor.docs ()) do
      if doc.path == path then
        lint (doc)
      end
    end
  end)

  app.on ('editor:closed', function (path)
    if reported[path] then
      reported[path] = nil
      diagnostics.set (SOURCE, path, {})
    end
  end)

  local first = true
  settings.watch ('docker.hadolint', function ()
    if first then
      first = false
      return
    end
    if enabled () then
      lint_all ()
    else
      clear_all ()
    end
  end)

  -- Findings stay in the panel after a plugin stops, unless it takes them away.
  app.dispose (clear_all)

  look ()
  lint_all ()

  ---@type LangDocker.Lint
  return {
    check = function ()
      look ()
      lint_all ()
    end,
  }
end

return M
