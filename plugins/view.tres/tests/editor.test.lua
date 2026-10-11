local plugin = require ('init')

local function setup ()
  local disk = '[gd_resource format=3]\n[resource]\nx = 1\n'
  local state = { disk = disk, posts = {}, writes = 0 }
  local opener, message, spec
  local tab = {
    id = 'test',
    set_dirty = function (value)
      state.dirty = value
    end,
    focus = function ()
      state.focused = true
    end,
    close = function (force)
      if force or spec.on_close () then
        state.closed = true
      end
    end,
  }
  local app = {
    fs = {
      read_file = function (_, cb)
        cb (state.disk, state.read_error)
      end,
      write_file = function (_, text, cb)
        state.writes = state.writes + 1
        if not state.write_error then
          state.disk = text
        end
        cb (nil, state.write_error)
      end,
    },
    use = function (name)
      if name == 'ui' then
        return {
          webview = function (opts)
            message = opts.on_message
            return {
              widget = function (_, _, data)
                state.posts[#state.posts + 1] = data
              end,
            }
          end,
          confirm = function (opts)
            state.confirm = opts
          end,
        }
      elseif name == 'editor' then
        return {
          add_opener = function (fn)
            opener = fn
          end,
          open = function (_, opts)
            state.as_text = opts.as_text
          end,
        }
      else
        return {
          get = function ()
            return nil
          end,
          open = function (opts)
            spec = opts
            return tab
          end,
        }
      end
    end,
    try_use = function ()
      return nil
    end,
  }
  plugin.activate (app)
  state.open = function (path)
    return opener (path)
  end
  state.send = function (msg)
    message (msg)
  end
  state.close = function (choice)
    return spec.on_close (choice)
  end
  return state
end

test ('opens disk resources and saves edited text', function ()
  local s = setup ()
  eq (s.open ('/project/test.tres'), true)
  s.send ({ type = 'ready' })
  eq (s.posts[#s.posts].type, 'load')
  s.send ({ type = 'change', text = 'changed' })
  eq (s.dirty, true)
  s.send ({ type = 'save' })
  eq (s.disk, 'changed')
  eq (s.dirty, false)
end)

test ('keeps edits when saving fails or disk content changes', function ()
  local s = setup ()
  s.open ('/project/test.tres')
  s.send ({ type = 'ready' })
  s.send ({ type = 'change', text = 'changed' })
  s.write_error = 'Read only'
  s.send ({ type = 'save' })
  eq (s.dirty, true)
  s.write_error = nil
  s.disk = 'external edit'
  s.send ({ type = 'save' })
  eq (s.disk, 'external edit')
  eq (s.writes, 1)
  eq (s.dirty, true)
end)

test ('asks before closing or reloading unsaved edits', function ()
  local s = setup ()
  s.open ('/project/test.tres')
  s.send ({ type = 'ready' })
  s.send ({ type = 'change', text = 'changed' })
  eq (s.close (), false)
  ok (s.confirm)
  s.send ({ type = 'text' })
  eq (s.as_text, nil)
  s.send ({ type = 'reload' })
  s.confirm.on_yes ()
  eq (s.dirty, false)
  s.send ({ type = 'text' })
  eq (s.as_text, true)
end)

test ('leaves other files and workspace paths to the editor', function ()
  local s = setup ()
  eq (s.open ('/project/file.tscn'), false)
  eq (s.open ('plugins/example/test.tres'), false)
  eq (s.open ('C:\\project\\TEST.TRES'), true)
end)

test ('saves before closing when the tab service requests save', function ()
  local s = setup ()
  s.open ('/project/test.tres')
  s.send ({ type = 'ready' })
  s.send ({ type = 'change', text = 'changed' })
  s.close ('save')
  eq (s.disk, 'changed')
  eq (s.closed, true)
end)
