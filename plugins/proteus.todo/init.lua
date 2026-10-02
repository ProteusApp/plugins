-- proteus.todo: a to-do list that draws the whole window. It uses no shell, menu or toolbar,
-- which shows that the layout plugins are optional. Colors still come from the theme.

-- lang=css
local CSS = [[
.todo { height: 100%; overflow: auto; display: flex; justify-content: center; padding: 8vh 16px 40px;
  background: var(--bg); font-family: var(--font-ui); }
.todo-card { width: min(560px, 100%); }
.todo h1 { font-size: 40px; font-weight: 300; letter-spacing: .12em; text-transform: lowercase; margin: 0 0 18px;
  color: var(--accent); }
.todo-new { width: 100%; padding: 14px 16px; font-size: 16px; border-radius: var(--radius);
  border: 1px solid var(--border); background: var(--bg-alt); color: var(--fg); outline: none; }
.todo-new:focus { border-color: var(--accent); }
.todo-list { list-style: none; margin: 14px 0 0; padding: 0; }
.todo-item { display: flex; align-items: center; gap: 12px; padding: 10px 6px; border-bottom: 1px solid var(--border); }
.todo-item input[type=checkbox] { width: 18px; height: 18px; accent-color: var(--accent); cursor: pointer; }
.todo-item .text { flex: 1; font-size: 15px; word-break: break-word; cursor: text; }
.todo-item.done .text { text-decoration: line-through; color: var(--fg-faint); }
.todo-item .del { border: none; background: none; color: var(--fg-faint); cursor: pointer; opacity: 0; }
.todo-item:hover .del { opacity: 1; }
.todo-item .del:hover { color: var(--danger); }
.todo-item .edit { flex: 1; font: inherit; font-size: 15px; background: var(--bg-alt); color: var(--fg);
  border: 1px solid var(--accent); border-radius: var(--radius); padding: 2px 6px; outline: none; }
.todo-foot { display: flex; align-items: center; gap: 8px; margin-top: 14px; color: var(--fg-muted); font-size: 13px; flex-wrap: wrap; }
.todo-foot .grow { flex: 1; }
.todo-foot button { font: inherit; border: 1px solid transparent; background: none; color: inherit; padding: 2px 8px;
  border-radius: var(--radius); cursor: pointer; }
.todo-foot button:hover { border-color: var(--border); }
.todo-foot button.on { border-color: var(--accent); color: var(--accent); }
.todo-apps { margin-top: 48px; display: flex; gap: 8px; flex-wrap: wrap; align-items: center; color: var(--fg-faint); font-size: 12px; }
.todo-apps button { font: inherit; font-size: 12px; border: 1px solid var(--border); background: var(--bg-alt);
  color: var(--fg-muted); padding: 3px 10px; border-radius: 99px; cursor: pointer; }
.todo-apps button:hover { color: var(--fg); border-color: var(--accent); }
]]

---@class Todo.Item
---@field text string
---@field done? boolean

-- A row on screen, kept so a right-click can find its item.
---@class Todo.Row
---@field row Proteus.El
---@field item Todo.Item
---@field text Proteus.El

---@type Proteus.Plugin
return {
  name = 'Todo',
  description = 'A single-screen to-do list.',
  version = '1.0.1',
  requires = { proteus = '>=0.3.0', features = { 'permissions' } },
  -- It keeps the list in app.store, and needs nothing more.
  permissions = {},
  depends = { 'proteus.lib.ui' },
  optional = {
    'proteus.core.themes',
    'proteus.ui.menus',
  },
  -- It draws the whole window, so it cannot share the window with the layout plugin.
  conflicts = { 'proteus.ui.shell' },
  activate = function (app)
    local ui = app.use ('ui')
    ui.css (CSS)

    ---@type Todo.Item[]
    local items = app.store.get ('items', {})
    ---@type string
    local filter = app.store.get ('filter', 'all')
    local list = ui.ul ({ class = 'todo-list' })
    local foot = ui.div ({ class = 'todo-foot' })
    ---@type fun()
    local render
    ---@type Todo.Row[]
    local todo_rows = {}

    local function save ()
      app.store.set ('items', items)
      render ()
    end

    ---@param item Todo.Item
    ---@param row Proteus.El
    ---@param text_el Proteus.El
    local function edit (item, row, text_el)
      local box = ui.input ({ class = 'edit', value = item.text })
      box:set ('className', 'edit')
      local finished = false
      ---@param keep boolean
      local function finish (keep)
        -- Enter re-renders the list, which removes the box and fires blur a second time.
        if finished then
          return
        end
        finished = true
        if keep then
          local t = box:value ():gsub ('^%s+', ''):gsub ('%s+$', '')
          if t == '' then
            for i, x in ipairs (items) do
              if x == item then
                table.remove (items, i)
                break
              end
            end
          else
            item.text = t
          end
        end
        save ()
      end
      box:on ('keydown', function (ev)
        -- Enter that confirms an IME composition belongs to the composition.
        if ev.composing then
          return
        end
        if ev.key == 'Enter' then
          finish (true)
          return true
        end
        if ev.key == 'Escape' then
          finish (false)
          return true
        end
      end)
      box:on ('blur', function ()
        finish (true)
      end)
      row:insert_before (box, text_el)
      text_el:remove ()
      box:focus ()
      box:select ()
    end

    render = function ()
      ---@type Proteus.El[]
      local rows = {}
      local left = 0
      todo_rows = {}
      for _, item in ipairs (items) do
        if not item.done then
          left = left + 1
        end
        local show = filter == 'all'
          or (filter == 'active' and not item.done)
          or (filter == 'done' and item.done)
        if show then
          local text = ui.span ({
            class = 'text',
            title = 'Double-click to edit',
            item.text,
          })
          ---@type Proteus.El
          local row
          row = ui.li ({
            class = 'todo-item' .. (item.done and ' done' or ''),
            ui.h ('input', {
              type = 'checkbox',
              checked = item.done == true,
              onchange = function (ev)
                item.done = ev.checked
                save ()
              end,
            }),
            text,
            ui.button ({
              class = 'del',
              title = 'Delete',
              ui.icon ('x', 16),
              onclick = function ()
                for i, x in ipairs (items) do
                  if x == item then
                    table.remove (items, i)
                    break
                  end
                end
                save ()
              end,
            }),
          })
          text:on ('dblclick', function ()
            edit (item, row, text)
          end)
          todo_rows[#todo_rows + 1] = { row = row, item = item, text = text }
          rows[#rows + 1] = row
        end
      end
      list:set_children (rows)

      ---@param name string
      ---@param label string
      ---@return Proteus.El
      local function tab (name, label)
        return ui.button ({
          class = filter == name and 'on' or '',
          label,
          onclick = function ()
            filter = name
            app.store.set ('filter', filter)
            render ()
          end,
        })
      end
      foot:set_children ({
        ui.span ({ left .. (left == 1 and ' thing' or ' things') .. ' left' }),
        ui.span ({ class = 'grow' }),
        tab ('all', 'All'),
        tab ('active', 'Active'),
        tab ('done', 'Done'),
        ui.button ({
          'Clear done',
          onclick = function ()
            ---@type Todo.Item[]
            local keep = {}
            for _, x in ipairs (items) do
              if not x.done then
                keep[#keep + 1] = x
              end
            end
            items = keep
            save ()
          end,
        }),
      })
    end

    local new = ui.input ({ placeholder = 'What needs doing?' })
    new:set ('className', 'todo-new')
    new:on ('keydown', function (ev)
      -- Enter that confirms an IME composition belongs to the composition.
      if ev.key ~= 'Enter' or ev.composing then
        return
      end
      local text = (new:value () or ''):gsub ('^%s+', ''):gsub ('%s+$', '')
      if text == '' then
        return true
      end
      items[#items + 1] = { text = text, done = false }
      new:value ('')
      save ()
      return true
    end)

    local menus = app.try_use ('menus')
    if menus then
      menus.attach (list, function (ev)
        for _, tr in ipairs (todo_rows) do
          if app.dom.contains (tr.row.id, ev.target) then
            local item = tr.item
            return {
              {
                label = 'Edit',
                icon = 'pencil',
                run = function ()
                  edit (item, tr.row, tr.text)
                end,
              },
              {
                label = item.done and 'Mark Not Done' or 'Mark Done',
                icon = item.done and 'circle' or 'circle-check',
                run = function ()
                  item.done = not item.done
                  save ()
                end,
              },
              { separator = true },
              {
                label = 'Delete',
                icon = 'trash-2',
                danger = true,
                run = function ()
                  for i, x in ipairs (items) do
                    if x == item then
                      table.remove (items, i)
                      break
                    end
                  end
                  save ()
                end,
              },
            }
          end
        end
        return nil
      end)
    end

    -- This app has no palette, so it offers its own way to reach the other apps.
    local apps = ui.div ({ class = 'todo-apps', 'Other apps:' })
    for _, p in ipairs (app.kernel.profiles ()) do
      if p.id ~= app.kernel.profile ().id then
        apps:append (ui.button ({
          p.name,
          title = p.description,
          onclick = function ()
            app.kernel.switch_profile (p.id)
          end,
        }))
      end
    end
    local themes = app.try_use ('themes')
    if themes then
      apps:append (ui.span ({ style = { marginLeft = '12px' }, 'Theme:' }))
      for _, t in ipairs (themes.list ()) do
        apps:append (ui.button ({
          t.name,
          onclick = function ()
            themes.choose (t.id)
          end,
        }))
      end
    end

    ui.mount (ui.div ({
      class = 'todo',
      ui.div ({ class = 'todo-card', ui.h1 ({ 'todo' }), new, list, foot, apps }),
    }))
    render ()
    new:focus ()
  end,
}
