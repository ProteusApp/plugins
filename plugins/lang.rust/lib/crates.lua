-- crates: finds the crate a file belongs to, and the Rust edition it uses, by reading
-- Cargo.toml files. Each Cargo.toml is read once, until one changes on disk.

local disk = require ('disk_paths') --[[@as DiskPaths]]

-- Folders never searched for a crate.
local SKIP = { node_modules = true, target = true, dist = true }

---@class LangRust.Crates
---@field of fun(dir: string, cb: fun(crate: string?)) The folder of the nearest Cargo.toml at or above `dir`.
---@field below fun(root: string, cb: fun(crate: string?)) A crate in `root` or one folder down, such as a Tauri app's `src-tauri`.
---@field edition fun(dir: string, cb: fun(edition: string)) The edition that applies in `dir`.

---@class LangRust.CratesModule
local M = {}

-- The edition for a file with no Cargo.toml edition above it. rustfmt would assume 2015,
-- which cannot parse async code.
M.DEFAULT_EDITION = '2021'

---The edition a Cargo.toml sets, as in `edition = "2021"`. A crate that takes it from its
---workspace, with `edition.workspace = true`, sets none.
---@param text string
---@return string?
function M.edition_of (text)
  for line in (text .. '\n'):gmatch ('([^\n]*)\n') do
    local edition = line:match ('^%s*edition%s*=%s*"(%d+)"')
    if edition then
      return edition
    end
  end
  return nil
end

---@param app Proteus.App
---@return LangRust.Crates
function M.new (app)
  -- Folder to the Cargo.toml text there, or false when there is none.
  local manifests = {} ---@type table<string, string|false>

  ---@param changes any
  local function forget (changes)
    for _, change in
      ipairs (changes or {} --[[@as Proteus.DirChange[] ]])
    do
      if disk.name (change.path) == 'Cargo.toml' then
        manifests = {}
        return
      end
    end
  end
  -- The Code Editor sends code:disk_changed from Proteus 0.3.0, and disk:changed before.
  app.on ('code:disk_changed', forget)
  app.on ('disk:changed', forget)

  ---@param dir string
  ---@param cb fun(text: string?)
  local function read (dir, cb)
    local known = manifests[dir]
    if known ~= nil then
      cb (known or nil)
      return
    end
    app.fs.read_file (dir .. '/Cargo.toml', function (text)
      manifests[dir] = text or false
      cb (text)
    end)
  end

  ---Walks up from `dir` until `accept` takes a Cargo.toml, then calls `done` with its folder.
  ---@param dir string
  ---@param accept fun(text: string): boolean
  ---@param done fun(dir: string?, text: string?)
  local function find_up (dir, accept, done)
    read (dir, function (text)
      if text and accept (text) then
        done (dir, text)
        return
      end
      local up = disk.parent (dir)
      if up == dir then
        done (nil, nil)
        return
      end
      find_up (up, accept, done)
    end)
  end

  ---@type LangRust.Crates
  return {
    of = function (dir, cb)
      find_up (dir, function ()
        return true
      end, function (found)
        cb (found)
      end)
    end,

    below = function (root, cb)
      read (root, function (text)
        if text then
          cb (root)
          return
        end
        app.fs.list_dir (root, function (names)
          local dirs = {} ---@type string[]
          for _, name in ipairs (names or {}) do
            local dir = name:match ('^(.+)/$')
            if dir and dir:sub (1, 1) ~= '.' and not SKIP[dir] then
              dirs[#dirs + 1] = disk.join (root, dir)
            end
          end
          ---@param i integer
          local function try (i)
            local dir = dirs[i]
            if not dir then
              cb (nil)
              return
            end
            read (dir, function (found)
              if found then
                cb (dir)
              else
                try (i + 1)
              end
            end)
          end
          try (1)
        end)
      end)
    end,

    -- The first edition set on the way up. That also finds the `[workspace.package]` edition
    -- of a workspace whose crates inherit it.
    edition = function (dir, cb)
      find_up (dir, function (text)
        return M.edition_of (text) ~= nil
      end, function (_, text)
        cb (text and M.edition_of (text) or M.DEFAULT_EDITION)
      end)
    end,
  }
end

return M
