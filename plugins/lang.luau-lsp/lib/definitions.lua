-- definitions: the files luau-lsp loads at start, kept in the plugin's data folder. They are
-- the same files VS Code's extension uses. Roblox mode needs Roblox's type definitions and
-- their documentation. Plain Luau needs only the documentation for Luau's own library, which
-- gives hover help for names such as `print` and `table.insert`.
--
-- A file that is missing downloads before the server starts. A file older than a day stays in
-- use while a new copy downloads, and the new copy counts from the next start. So the server
-- never waits for the network once each file is there.

-- Where luau-lsp publishes the files. The definitions are for code that runs with plugin
-- security, as VS Code's extension loads them by default.
local BASE = 'https://luau-lsp.pages.dev/'
local DAY = 24 * 60 * 60 * 1000

---One file to keep.
---@class LangLuau.DefinitionFile
---@field name string Its name in the data folder.
---@field url string
---@field kind 'definitions'|'docs' How the server takes it.

---@class LangLuau.Definitions
---@field ensure fun(roblox: boolean, cb: fun(files: LangLuau.LaunchFiles)) Calls `cb` with the files that are there.

---@class LangLuau.DefinitionsModule
local M = {}

---The files the server loads, in Roblox mode or out of it.
---@param roblox boolean
---@return LangLuau.DefinitionFile[]
function M.files (roblox)
  if roblox then
    return {
      {
        name = 'globalTypes.PluginSecurity.d.luau',
        url = BASE .. 'type-definitions/globalTypes.PluginSecurity.d.luau',
        kind = 'definitions',
      },
      {
        name = 'api-docs.json',
        url = BASE .. 'api-docs/en-us.json',
        kind = 'docs',
      },
    }
  end
  return {
    {
      name = 'luau-api-docs.json',
      url = BASE .. 'api-docs/luau-en-us.json',
      kind = 'docs',
    },
  }
end

---True when a file is older than a day, so a new copy is due.
---@param modified number When it last changed, in milliseconds since 1970. 0 when unknown.
---@param now number
---@return boolean
function M.stale (modified, now)
  return now - modified > DAY
end

---@param app Proteus.App
---@param dir string The plugin's data folder, as a full path with `/`.
---@param log fun(level: 'info'|'err', text: string) Writes to the tool's log.
---@return LangLuau.Definitions
function M.install (app, dir, log)
  local fetching = {} ---@type table<string, fun(ok: boolean)[]>

  ---Downloads one file into the data folder, once at a time, and tells every caller.
  ---@param file LangLuau.DefinitionFile
  ---@param cb fun(ok: boolean)
  local function download (file, cb)
    if fetching[file.name] then
      table.insert (fetching[file.name], cb)
      return
    end
    fetching[file.name] = { cb }
    local path = dir .. '/' .. file.name
    ---@param ok boolean
    local function finish (ok)
      local list = fetching[file.name] or {}
      fetching[file.name] = nil
      for _, fn in ipairs (list) do
        app.try (fn, ok)
      end
    end
    log ('info', 'downloading ' .. file.url)
    app.net.fetch ({ url = file.url }, function (reply, err)
      if not reply or reply.status ~= 200 then
        log (
          'err',
          file.url
            .. ' did not download: '
            .. tostring (err or (reply and reply.status))
        )
        finish (false)
        return
      end
      app.fs.make_dir (dir, function (_, dir_err)
        if dir_err then
          log ('err', 'cannot make ' .. dir .. ': ' .. tostring (dir_err))
          finish (false)
          return
        end
        -- This writes the file to disk before it calls back, so the server never starts
        -- before the file is there.
        app.fs.write_file (path, reply.body, function (_, write_err)
          if write_err then
            log ('err', 'cannot save ' .. path .. ': ' .. tostring (write_err))
          end
          finish (write_err == nil)
        end)
      end)
    end)
  end

  ---@type LangLuau.Definitions
  return {
    ensure = function (roblox, cb)
      local files = M.files (roblox)
      local found = {} ---@type LangLuau.LaunchFiles
      local waiting = #files
      local function done ()
        waiting = waiting - 1
        if waiting == 0 then
          cb (found)
        end
      end
      for _, file in ipairs (files) do
        local path = dir .. '/' .. file.name
        app.fs.stat_path (path, function (stat)
          if stat and stat.exists then
            found[file.kind] = path
            if M.stale (stat.modified, app.util.now ()) then
              download (file, function () end)
            end
            done ()
            return
          end
          download (file, function (ok)
            found[file.kind] = ok and path or nil
            done ()
          end)
        end)
      end
    end,
  }
end

return M
