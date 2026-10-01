-- commands: "Add a .gitignore Template…" and "Add This File to .gitignore". Both add lines to
-- a .gitignore and open it. A line the file already holds is not added twice.

local disk = require ('disk_paths') --[[@as DiskPaths]]
local ignore = require ('lib.ignore') --[[@as LangGitfiles.IgnoreModule]]
local templates = require ('lib.templates') --[[@as LangGitfiles.TemplatesModule]]

---@class LangGitfiles.CommandsModule
local M = {}

---@param ctx LangGitfiles.Context
function M.install (ctx)
  local app, editor = ctx.app, ctx.editor
  local commands = app.use ('commands')

  ---@param level 'info'|'success'|'warn'
  ---@param text string
  local function notify (level, text)
    local n = app.try_use ('notify')
    if n then
      n[level] (text)
    else
      app.log (text)
    end
  end

  ---@return string?
  local function project_root ()
    local project = app.try_use ('project')
    local root = project and project.root ()
    return root and disk.normalize (root) or nil
  end

  ---The document open at a full path, or nil.
  ---@param path string
  ---@return Proteus.DocInfo?
  local function open_doc (path)
    for _, doc in ipairs (editor.docs ()) do
      if disk.same (ctx.full_path (doc), path, app.os) then
        return doc
      end
    end
    return nil
  end

  ---Changes a file and shows it. `change` gets the text and returns the new text, or nil
  ---when there is nothing to add. The file in front changes as an edit that Ctrl+Z undoes.
  ---Any other file changes on disk, and its tab, if it has one, reads it again.
  ---@param path string A full path.
  ---@param change fun(text: string): string?
  ---@param done fun(changed: boolean)
  local function update (path, change, done)
    local current = editor.current ()
    if current and disk.same (ctx.full_path (current), path, app.os) then
      local text = change (current.text ())
      if text then
        current.replace (text)
      end
      done (text ~= nil)
      return
    end
    local doc = open_doc (path)
    if doc and doc.dirty () then
      notify ('warn', disk.name (path) .. ' has unsaved changes. Save it first.')
      return
    end
    ---@param text string
    local function write (text)
      local new = change (text)
      if not new then
        done (false)
        return
      end
      app.fs.write_file (path, new, function (_, err)
        if err then
          notify ('warn', 'Could not write ' .. path .. ': ' .. tostring (err))
          return
        end
        editor.open_file (path)
        done (true)
      end)
    end
    -- A file that is not there starts empty. One that is there but cannot be read is left
    -- alone, so nothing in it is lost.
    app.fs.stat_path (path, function (stat)
      if not stat then
        write ('')
        return
      end
      app.fs.read_file (path, function (text, err)
        if not text then
          notify ('warn', 'Could not read ' .. path .. ': ' .. tostring (err))
          return
        end
        write (text)
      end)
    end)
  end

  ---The .gitignore a template goes into: the one in front, or else the open folder's.
  ---@return string?
  local function template_target ()
    local current = editor.current ()
    if current and disk.name (current.path) == '.gitignore' then
      return ctx.full_path (current)
    end
    local root = project_root ()
    return root and disk.join (root, '.gitignore') or nil
  end

  commands.register ({
    id = 'gitfiles.add_template',
    category = 'Git Files',
    title = 'Add a .gitignore Template…',
    icon = 'eye-off',
    run = function ()
      local target = template_target ()
      if not target then
        notify ('info', 'Open a folder, or a .gitignore file, first.')
        return
      end
      local picker = app.try_use ('picker')
      if not picker then
        notify ('warn', 'Picking a template needs the command palette.')
        return
      end
      local items = {} ---@type Proteus.PickItem[]
      for _, t in ipairs (templates.list) do
        items[#items + 1] = {
          label = t.name,
          detail = t.detail,
          icon = 'file-plus',
          value = t.name,
        }
      end
      picker.pick ({
        prompt = 'Add to ' .. target,
        placeholder = 'A language, an editor or a system',
        items = items,
        on_pick = function (item)
          local template = templates.get (tostring (item.value))
          if not template then
            return
          end
          update (target, function (text)
            return templates.add (text, template)
          end, function (changed)
            if not changed then
              notify (
                'info',
                'The .gitignore holds every line of the '
                  .. template.name
                  .. ' template already.'
              )
            end
          end)
        end,
      })
    end,
  })

  ---The folder whose .gitignore covers a file: the nearest folder above it that holds a
  ---`.git` folder or file, or else the open folder when the file is inside it.
  ---@param path string
  ---@param cb fun(root: string?)
  local function repository_root (path, cb)
    local fallback = project_root ()
    if fallback and not disk.inside (path, fallback, app.os) then
      fallback = nil
    end
    ---@param folder string
    local function look (folder)
      app.fs.stat_path (disk.join (folder, '.git'), function (stat)
        if stat then
          cb (folder)
          return
        end
        local above = disk.parent (folder)
        if above == folder then
          cb (fallback)
        else
          look (above)
        end
      end)
    end
    look (disk.parent (path))
  end

  commands.register ({
    id = 'gitfiles.ignore_file',
    category = 'Git Files',
    title = 'Add This File to .gitignore',
    icon = 'eye-off',
    when = function ()
      return editor.current () ~= nil
    end,
    run = function ()
      local current = editor.current ()
      if not current then
        return
      end
      local path = ctx.full_path (current)
      repository_root (path, function (root)
        local rel = root and disk.relative (root, path, app.os)
        if not root or not rel or rel == '' then
          notify (
            'info',
            disk.name (path)
              .. ' is not inside a Git repository or the open folder.'
          )
          return
        end
        local line = ignore.entry (rel)
        update (disk.join (root, '.gitignore'), function (text)
          return templates.append (text, nil, { line })
        end, function (changed)
          if changed then
            notify (
              'success',
              'Added '
                .. line
                .. ' to .gitignore. A file Git tracks already stays tracked until `git rm --cached` removes it.'
            )
          else
            notify ('info', '.gitignore lists ' .. line .. ' already.')
          end
        end)
      end)
    end,
  })
end

return M
