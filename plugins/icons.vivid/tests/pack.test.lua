-- The Vivid pack: what it registers, and the icons some well known files get.

local plugin = require ('init')
local PACK = 'vivid'

---What the plugin registers when it starts: its pack and its associations.
---@return table pack
---@return table[] associations
local function start ()
  local pack, list = nil, {}
  local app = {
    use = function (name)
      if name == 'icons' then
        return {
          register = function (spec)
            assert (pack == nil, 'registers one pack')
            pack = spec
          end,
        }
      end
      assert (
        name == 'files',
        'uses only icons and files, not ' .. tostring (name)
      )
      return {
        associate = function (a)
          list[#list + 1] = a
        end,
      }
    end,
  }
  plugin.activate (app)
  return pack, list
end

---The icon core.icons would show for a file or folder: the whole name first, then the longest
---extension, then the pack's default. Case does not matter.
---@param path string
---@param folder? boolean
---@return table?
local function find (path, folder)
  local pack, list = start ()
  local name = (path:match ('([^/]*)$') or path):lower ()
  local names, exts = {}, {}
  for _, a in ipairs (list) do
    local p = a.pattern:lower ()
    local ext = p:match ('^%*%.(.+)$')
    if ext and not a.value.folder then
      exts[ext] = a.value
    elseif (a.value.folder == true) == (folder == true) then
      names[p] = a.value
    end
  end
  if names[name] then
    return names[name]
  end
  if not folder then
    local start_at = 1
    while true do
      local dot = name:find ('.', start_at, true)
      if not dot then
        break
      end
      if exts[name:sub (dot + 1)] then
        return exts[name:sub (dot + 1)]
      end
      start_at = dot + 1
    end
  end
  return folder and pack.folder or pack.file
end

test ('it registers the pack', function ()
  local pack = start ()
  eq (pack.id, PACK)
  ok (type (pack.name) == 'string' and pack.name ~= '')
  ok (pack.file and pack.file.icon, 'a default file icon')
  ok (
    pack.folder and pack.folder.icon and pack.folder.open,
    'default folder icons'
  )
end)

test ('every association is a well formed icon of this pack', function ()
  local _, list = start ()
  ok (#list > 50, 'covers many kinds of files')
  local seen = {}
  for _, a in ipairs (list) do
    local v = a.value
    local where = a.pattern .. (v.folder and ' (folder)' or '')
    eq (a.kind, 'icon', where)
    eq (v.pack, PACK, where)
    ok (not seen[where:lower ()], where .. ' is associated once')
    seen[where:lower ()] = true
    ok (not a.pattern:find ('[/\\]'), where .. ' names a file, not a path')
    ok (
      (type (v.icon) == 'string' and v.icon:match ('^[a-z][a-z0-9-]*$'))
        or (type (v.text) == 'string' and #v.text >= 1 and #v.text <= 3),
      where .. ' has a Lucide icon or a badge of one to three letters'
    )
    ok (
      v.color == nil
        or v.color:match ('^#%x%x%x%x%x%x$')
        or v.color:match ('^var%(%-%-[a-z-]+%)$'),
      where
        .. ': '
        .. tostring (v.color)
        .. ' is a hex color or a theme variable'
    )
    if v.folder then
      ok (type (v.open) == 'string', where .. ' has an open icon')
    end
  end
end)

test ('well known files get their icons', function ()
  eq (find ('src/main.rs').icon, 'cog')
  eq (find ('plugins/app/init.lua').icon, 'moon')
  eq (find ('web/index.d.ts').icon, 'file-type')
  eq (
    find ('web/app.test.ts').icon,
    'flask-conical',
    'a test beats its language'
  )
  eq (find ('graphs/todo.ndg').icon, 'workflow', 'a graph has its own icon')
  eq (find ('data.json').icon, 'braces')
  eq (find ('Cargo.toml').icon, 'package', 'a name beats its extension')
  eq (find ('readme.md').icon, 'info', 'case does not matter')
  eq (find ('photo.JPG').icon, 'image')
  eq (find ('notes.xyz').icon, 'file', 'the pack default')
end)

test ('well known folders get their icons', function ()
  eq (find ('app/src', true).icon, 'folder-code')
  eq (find ('.git', true).icon, 'folder-git')
  eq (find ('node_modules', true).icon, 'folder-archive')
  eq (find ('stuff', true).icon, 'folder', 'the pack default')
  eq (find ('src').icon, 'file', 'a file named src is still a file')
end)
