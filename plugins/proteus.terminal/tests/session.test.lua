local groups = require ('terminal_groups') --[[@as Terminal.Groups]]
local session = require ('terminal_session') --[[@as Terminal.Session]]

test ('place says where a terminal sits', function ()
  local state = groups.new ()
  groups.add (state, 1)
  groups.split (state, 2, 1)
  groups.add (state, 3)
  groups.focus (state, 1)
  eq (
    session.place (state, 1),
    { group = 1, pane = 1, front = true, focus = true }
  )
  eq (
    session.place (state, 2),
    { group = 1, pane = 2, front = true, focus = false }
  )
  eq (
    session.place (state, 3),
    { group = 2, pane = 1, front = false, focus = true }
  )
  eq (session.place (state, 9), nil)
end)

test ('read keeps what it can of the saved text', function ()
  eq (session.read (nil), nil)
  eq (session.read ('text'), nil)
  eq (session.read ({}), {
    group = 1,
    pane = 1,
    front = false,
    focus = false,
    title = 'Terminal',
    cwd = '',
    profile = '',
  })
  eq (
    session.read ({
      group = 2,
      pane = 3.7,
      front = true,
      focus = true,
      name = 'Server',
      title = 'bash',
      cwd = '/code',
      profile = 'Git Bash',
      task = 'Build',
    }),
    {
      group = 2,
      pane = 3,
      front = true,
      focus = true,
      name = 'Server',
      title = 'bash',
      cwd = '/code',
      profile = 'Git Bash',
      task = 'Build',
    }
  )
  eq (session.read ({ name = '', task = '', group = -1 }).name, nil)
end)

test ('layout builds the tabs again in their order', function ()
  ---@param id integer
  ---@param group integer
  ---@param pane integer
  ---@param flags? { front?: boolean, focus?: boolean }
  ---@return Terminal.Waiting
  local function waiting (id, group, pane, flags)
    local f = flags or {}
    return {
      id = id,
      ended = false,
      saved = session.read ({
        group = group,
        pane = pane,
        front = f.front,
        focus = f.focus,
      }),
    }
  end
  local list = {
    waiting (10, 2, 2, { front = true, focus = true }),
    waiting (11, 1, 1, { focus = true }),
    waiting (12, 2, 1),
    { id = 13, ended = true },
    waiting (14, 5, 1),
  }
  local saved_groups, front = session.layout (list)
  local ids = {} ---@type integer[][]
  for i, g in ipairs (saved_groups) do
    ids[i] = {}
    for _, w in ipairs (g.items) do
      ids[i][#ids[i] + 1] = w.id
    end
  end
  eq (ids, { { 11 }, { 12, 10 }, { 14 }, { 13 } })
  eq (saved_groups[2].focus, 2)
  eq (front, 2)

  local none, no_front = session.layout ({})
  eq ({ none, no_front }, { {}, nil })
  local _, first = session.layout ({ waiting (1, 1, 1) })
  eq (first, 1)
end)
