-- lang.react: JSX and TSX in the code editor, on lang.typescript's language server.
--
-- The server gives .jsx and .tsx files completion with documentation, hover help, go to
-- definition (F12 or Ctrl+click) and problems. It is the same server the plain TypeScript
-- and JavaScript files use, so a component knows the modules it imports. A word alone on its
-- line also offers the common hooks as whole statements, and a component named after the
-- file. New React Component asks for a name and makes the component's file.
--
-- The parts live in lib/:
--   hooks      the hook and component completion
--   component  the text of a new component

local component = require ('lib.component') --[[@as LangReact.ComponentModule]]
local disk = require ('disk_paths') --[[@as DiskPaths]]
local hooks = require ('lib.hooks') --[[@as LangReact.HooksModule]]

-- The languages a file in front may have, and whether a new component next to it is TSX.
local TYPESCRIPT = { typescript = true, tsx = true }
local JAVASCRIPT = { javascript = true, jsx = true }

---@type Proteus.Plugin
return {
  name = 'React',
  description = 'JSX and TSX on the TypeScript language server, with completion for React hooks and components, and New React Component.',
  version = '1.0.0',
  requires = { proteus = '>=0.3.0', features = { 'permissions' } },
  -- The editor service, and writing a new component's file next to the file in front.
  permissions = { 'files' },
  depends = {
    'lang.typescript',
    'proteus.core.commands',
    'proteus.core.files',
    'proteus.editor.core',
    'proteus.ui.palette',
  },
  optional = { 'proteus.code.project', 'proteus.ui.notify' },
  activate = function (app)
    local editor = app.use ('editor')
    local workspace = disk.normalize (app.kernel.launch.workspace or '')

    local typescript = app.use ('typescript') --[[@as LangTypescript.Service]]
    typescript.serve ({ language = 'jsx', language_id = 'javascriptreact' })
    typescript.serve ({ language = 'tsx', language_id = 'typescriptreact' })

    local files = app.use ('files')
    for _, pattern in ipairs ({ '*.jsx', '*.tsx' }) do
      files.associate ({
        kind = 'completion',
        pattern = pattern,
        value = function (doc, pos, respond)
          ---@cast doc Proteus.DocInfo
          ---@cast pos Proteus.CodePosition
          respond (hooks.complete (doc.text (), pos, doc.path))
        end,
      })
    end

    ---@param level 'info'|'warn'
    ---@param text string
    local function notify (level, text)
      local n = app.try_use ('notify')
      if n then
        n[level] (text)
      else
        app.log (text)
      end
    end

    ---Where a new component goes: beside the file in front, or else in the open folder.
    ---`shown` is the folder as the editor opens files in it.
    ---@return { folder: string, shown: string, external: boolean }?
    local function target ()
      local doc = editor.current ()
      if doc then
        local full = doc.external and disk.normalize (doc.path)
          or disk.join (workspace, doc.path)
        return {
          folder = disk.parent (full),
          shown = doc.external and disk.parent (full) or disk.parent (doc.path),
          external = doc.external,
        }
      end
      local project = app.try_use ('project')
      local root = project and project.root ()
      if root then
        return { folder = root, shown = root, external = true }
      end
      return nil
    end

    ---Whether a new component is TSX: like the file in front, or else when the folder has
    ---a tsconfig.json.
    ---@param folder string
    ---@param cb fun(tsx: boolean)
    local function wants_tsx (folder, cb)
      local doc = editor.current ()
      local language = doc and doc.language or ''
      if TYPESCRIPT[language] or JAVASCRIPT[language] then
        cb (TYPESCRIPT[language] == true)
        return
      end
      app.fs.stat_path (disk.join (folder, 'tsconfig.json'), function (stat)
        cb (stat ~= nil and stat.exists == true)
      end)
    end

    ---@param name string
    local function create (name)
      local place = target ()
      if not place then
        notify ('warn', 'Open a file or a folder first.')
        return
      end
      wants_tsx (place.folder, function (tsx)
        local file = name .. (tsx and '.tsx' or '.jsx')
        local path = disk.join (place.folder, file)
        local shown = place.external and path or (place.shown .. '/' .. file)
        ---@param where string
        local function open (where)
          if place.external then
            editor.open_external (where)
          else
            editor.open_file (where)
          end
        end
        app.fs.stat_path (path, function (stat)
          if stat and stat.exists then
            notify ('warn', file .. ' is there already, so it opens instead.')
            open (shown)
            return
          end
          app.fs.write_file (
            path,
            component.source (name, tsx),
            function (done, err)
              if not done then
                notify (
                  'warn',
                  'Could not write ' .. file .. ': ' .. tostring (err)
                )
                return
              end
              open (shown)
            end
          )
        end)
      end)
    end

    app.use ('commands').register ({
      id = 'react.new_component',
      category = 'React',
      title = 'New React Component…',
      icon = 'atom',
      run = function ()
        app.use ('picker').input ({
          prompt = 'Name of the new component',
          placeholder = 'Such as Button',
          validate = component.problem,
          on_submit = create,
        })
      end,
    })
  end,
}
