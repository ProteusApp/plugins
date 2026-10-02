local exclude = require ('exclude') --[[@as CodeProject.Exclude]]

-- The rules of the app's lib/file_glob.lua, which the registry does not have.
local file_glob = {}
local function body (glob)
  local out = glob:gsub ('[%^%$%(%)%%%.%[%]%+%-]', '%%%0')
  out = out:gsub ('%*%*', '\1'):gsub ('%*', '[^/]*'):gsub ('%?', '[^/]')
  return (out:gsub ('\1', '.*'))
end
function file_glob.matches (glob, path, fold_case)
  local subject = path:gsub ('\\', '/')
  if fold_case then
    glob, subject = glob:lower (), subject:lower ()
  end
  if not glob:find ('/', 1, true) then
    local name = subject:match ('([^/]*)$') or subject
    return name:find ('^' .. body (glob) .. '$') ~= nil
  end
  if glob:sub (1, 1) == '/' then
    return subject:find ('^' .. body (glob) .. '$') ~= nil
  end
  local b = body (glob:match ('^%*%*/(.*)$') or glob)
  return subject:find ('^' .. b .. '$') ~= nil
    or subject:find ('/' .. b .. '$') ~= nil
end

---@param p string[]
---@param rel string
---@param dir? boolean
---@param fold? boolean
---@return boolean
local function matches (p, rel, dir, fold)
  return exclude.matches (file_glob, p, rel, dir, fold)
end

test (
  'a name matches a file or folder anywhere, and what is inside it',
  function ()
    local p = { 'node_modules', '*.min.js', '.DS_Store' }
    ok (matches (p, 'node_modules', true))
    ok (matches (p, 'web/node_modules/pkg/index.js'))
    ok (matches (p, 'web/app.min.js'))
    ok (matches (p, 'a/.DS_Store'))
    ok (not matches (p, 'src/node_modules.txt'))
    ok (not matches (p, 'web/app.js'))
    ok (not matches (p, ''))
    ok (not matches ({}, 'node_modules'))
  end
)

test ('a pattern with folders matches the end of a path', function ()
  local p = { 'docs/build', '/out' }
  ok (matches (p, 'docs/build/index.html'))
  ok (matches (p, 'site/docs/build', true))
  ok (matches (p, 'out/a.txt'))
  ok (not matches (p, 'src/out/a.txt'))
  ok (not matches (p, 'build/a.txt'))
end)

test ('a pattern that ends in a slash matches folders only', function ()
  local p = { 'build/' }
  ok (matches (p, 'build', true))
  ok (matches (p, 'build/a.txt'))
  ok (not matches (p, 'build'))
  ok (not matches (p, 'src/build'))
end)

test ('case matters only where the system says so', function ()
  ok (not matches ({ 'Thumbs.db' }, 'pics/thumbs.db'))
  ok (matches ({ 'Thumbs.db' }, 'pics/thumbs.db', false, true))
end)

test (
  'for_walk makes a pattern with folders match anywhere, as it does here',
  function ()
    eq (
      exclude.for_walk ({
        'node_modules',
        'docs/build',
        '/out',
        '**/gen',
        'tmp/',
      }),
      { 'node_modules', '**/docs/build', '/out', '**/gen', 'tmp/' }
    )
  end
)

test ('clean keeps the strings that say something', function ()
  eq (exclude.clean ({ ' dist ', '', 'a\\b', 3, '/' }), { 'dist', 'a/b' })
  eq (exclude.clean ('dist'), {})
end)

test ('migrate keeps what the user had set in either setting', function ()
  eq (exclude.migrate (nil, nil), nil)
  eq (exclude.migrate ({ 'node_modules', 'vendor' }, nil), {
    'node_modules',
    'vendor',
    '.git',
    '.DS_Store',
    'Thumbs.db',
    'desktop.ini',
  })
  local with_hide = exclude.migrate (nil, { '.git', 'tmp' }) or {}
  eq (with_hide[#with_hide], 'tmp')
  eq (#with_hide, #exclude.DEFAULT + 1)
end)
