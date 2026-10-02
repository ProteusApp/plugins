-- Starts the plugin on a stand-in for the app, to follow tasks and reloads through init.lua.

---@class Fake.El
---@field kind string
---@field spec any
---@field children Fake.El[]
---@field calls any[][]
---@field removed boolean
---@field opts? table

local ALL = {} ---@type Fake.El[]

---@param kind string
---@param spec any
---@return Fake.El
local function element (kind, spec)
  local el = {
    kind = kind,
    spec = spec,
    children = {},
    calls = {},
    removed = false,
  }
  local methods = {}
  function methods.append (self, child)
    self.children[#self.children + 1] = child
    return self
  end
  function methods.on ()
    return function () end
  end
  function methods.class (self)
    return self
  end
  function methods.attr (self)
    return self
  end
  function methods.text (self)
    return self
  end
  function methods.show (self)
    return self
  end
  function methods.remove (self)
    self.removed = true
  end
  function methods.widget (self, method, ...)
    self.calls[#self.calls + 1] = { method, ... }
  end
  ALL[#ALL + 1] = el
  return setmetatable (el, { __index = methods })
end

---The pane that holds a terminal widget.
---@param widget Fake.El
---@return Fake.El?
local function pane_of (widget)
  for _, el in ipairs (ALL) do
    if
      type (el.spec) == 'table'
      and el.spec.class == 'term-pane'
      and el.spec[1] == widget
    then
      return el
    end
  end
  return nil
end

---A small JSON writer with sorted keys, and a reader for the texts it wrote or was told.
---@param known table<string, any>
---@return table
local function fake_json (known)
  local function encode (v)
    local t = type (v)
    if t == 'string' then
      return string.format ('%q', v)
    elseif t ~= 'table' then
      return tostring (v)
    end
    local keys = {}
    for k in pairs (v) do
      keys[#keys + 1] = tostring (k)
    end
    table.sort (keys)
    local parts = {}
    for _, k in ipairs (keys) do
      parts[#parts + 1] = k .. '=' .. encode (v[k])
    end
    return '{' .. table.concat (parts, ',') .. '}'
  end
  return {
    encode = function (v)
      local text = encode (v)
      known[text] = v
      return text
    end,
    decode = function (text)
      local v = known[text]
      if v == nil then
        error ('not JSON')
      end
      return v
    end,
  }
end

---@param opts { project?: table<string, string>, disk?: table<string, table>, settings?: table, json?: table<string, any> }
local function boot (opts)
  local env = setmetatable ({
    require = function (name)
      if name == 'disk_paths' then
        return {
          native = function (p)
            return p
          end,
        }
      end
      return require (name)
    end,
  }, { __index = _G })
  local plugin = assert (
    load (read ('plugins/proteus.terminal/init.lua'), '@init.lua', 't', env)
  ) ()
  local run = {
    made = {}, ---@type Fake.El[]
    commands = {},
    views = {},
    said = {},
    problems = {},
    picks = {},
    timers = {},
    services = {},
    waiting = nil, ---@type fun(list: table)?
  }
  local values = opts.settings or {}
  local defaults = {}
  local ui = setmetatable ({
    css = function () end,
    icon = function (name)
      return element ('icon', name)
    end,
    widget = function (kind, wopts)
      local el = element (kind, nil)
      el.opts = wopts
      run.made[#run.made + 1] = el
      return el
    end,
  }, {
    __index = function (_, tag)
      return function (spec)
        return element (tag, spec)
      end
    end,
  })
  local services = {
    ui = ui,
    views = {
      add = function (_, spec)
        run.views[spec.id] = spec
      end,
      show = function (id)
        local spec = run.views[id]
        if spec and spec.on_show then
          spec.on_show ()
        end
        return spec ~= nil
      end,
    },
    settings = {
      define = function (key, spec)
        defaults[key] = spec.default
      end,
      get = function (key)
        local v = values[key]
        if v == nil then
          return defaults[key]
        end
        return v
      end,
      watch = function () end,
    },
    commands = {
      register = function (spec)
        run.commands[spec.id] = spec
      end,
    },
    picker = {
      pick = function (popts)
        run.picks[#run.picks + 1] = popts
      end,
    },
    diagnostics = {
      set = function (source, path, list)
        run.problems[source] = run.problems[source] or {}
        run.problems[source][path] = #list > 0 and list or nil
      end,
    },
    notify = {
      info = function (text)
        run.said[#run.said + 1] = 'info: ' .. text
      end,
      warn = function (text)
        run.said[#run.said + 1] = 'warn: ' .. text
      end,
      error = function (text)
        run.said[#run.said + 1] = 'error: ' .. text
      end,
    },
    project = {
      root = function ()
        return '/code/site'
      end,
    },
  }
  local layers = { project = opts.project or {} }
  local app = {
    platform = 'tauri',
    os = 'linux',
    warn = function () end,
    use = function (name)
      return assert (services[name], name)
    end,
    try_use = function (name)
      return services[name]
    end,
    provide = function (name, value)
      run.services[name] = value
    end,
    json = fake_json (opts.json or {}),
    timer = {
      after = function (_, fn)
        run.timers[#run.timers + 1] = fn
      end,
    },
    fs = {
      read = function (path, layer)
        return (layers[layer or 'all'] or {})[path]
      end,
      disk_path = function (path)
        return '/home/me/.proteus/' .. path
      end,
      stat_path = function (path, cb)
        cb ((opts.disk or {})[path])
      end,
    },
    process = {
      waiting_terminals = function (cb)
        run.waiting = cb
      end,
    },
    system = {},
  }
  function run.flush ()
    while #run.timers > 0 do
      local list = run.timers
      run.timers = {}
      for _, fn in ipairs (list) do
        fn ()
      end
    end
  end
  plugin.activate (app)
  return run
end

---@param el Fake.El
---@param method string
---@return any[][]
local function calls (el, method)
  local out = {}
  for _, c in ipairs (el.calls) do
    if c[1] == method then
      out[#out + 1] = c
    end
  end
  return out
end

local TASKS_JSON = '{"tasks": [...]}'
local TASKS = {
  tasks = {
    { label = 'Build', command = 'make', group = 'build', problems = 'gcc' },
    { label = 'Serve', program = 'npm', args = { 'start' }, cwd = 'web' },
  },
}

test (
  'a task runs in a terminal of its own, and its problems reach the Problems panel',
  function ()
    local run = boot ({
      project = { ['tasks.json'] = TASKS_JSON },
      json = { [TASKS_JSON] = TASKS },
      settings = {
        ['terminal.tasks'] = { { label = 'Lint', command = 'selene .' } },
      },
    })
    run.waiting ({})
    eq (run.services.terminal.tasks (), { 'Build', 'Serve', 'Lint' })

    run.commands['terminal.run_task'].run ()
    local pick = run.picks[1]
    eq (#pick.items, 3)
    eq (pick.items[1].detail, 'make · from the folder')
    eq (pick.items[3].detail, 'selene . · from settings')
    pick.on_pick (pick.items[1])
    local term = run.made[1]
    eq (term.opts.program, '/bin/sh')
    eq (term.opts.args, { '-c', 'make' })
    eq (term.opts.cwd, '/code/site')
    eq (term.opts.keep, true)
    eq (type (term.opts.on_line), 'function')

    term.opts.on_started ()
    term.opts.on_line ('main.c:3:5: error: expected ;')
    term.opts.on_line ('make: *** [all] Error 1')
    run.flush ()
    eq (run.problems['task: Build'], {
      ['/code/site/main.c'] = {
        {
          line = 2,
          character = 4,
          severity = 'error',
          message = 'expected ;',
          source = 'task: Build',
        },
      },
    })
    term.opts.on_exit (2)
    eq (run.said, { 'warn: Build stopped with code 2, with 1 problem.' })

    -- Running it again reuses its terminal and starts its problems over.
    eq (run.services.terminal.run_task ('build'), true)
    eq (#run.made, 1)
    eq (calls (term, 'set_program'), {
      { 'set_program', '/bin/sh', { '-c', 'make' }, '/code/site' },
    })
    eq (#calls (term, 'restart'), 1)
    run.flush ()
    eq (run.problems['task: Build'], {})

    -- Run Build Task runs the build group's only task. A task's folder is inside the open one.
    run.services.terminal.run_task ('Serve')
    eq (run.made[2].opts.args, { 'start' })
    eq (run.made[2].opts.cwd, '/code/site/web')
    eq (run.services.terminal.run_task ('nope'), false)
  end
)

test ("an untrusted folder's tasks never run", function ()
  -- The folder has a .proteus/tasks.json on disk, but no layer: the user has not trusted it.
  local run = boot ({
    disk = {
      ['/code/site/.proteus/tasks.json'] = { exists = true, dir = false },
    },
  })
  run.waiting ({})
  eq (run.services.terminal.tasks (), {})
  eq (run.services.terminal.run_task ('Build'), false)
  run.commands['terminal.run_build_task'].run ()
  eq (run.said, {
    "info: The open folder's .proteus/tasks.json runs only once you trust the folder.",
    'info: There are no tasks. Add them to .proteus/tasks.json in the open folder, or to the terminal.tasks setting.',
  })
  eq (#run.made, 0)
end)

test ('the terminals come back into their tabs after a reload', function ()
  local known = {}
  local first = boot ({ json = known })
  first.waiting ({})
  first.services.terminal.open ({ name = 'Server' })
  first.services.terminal.open ({ split = true })
  first.services.terminal.open ({ cwd = '/tmp' })
  local metas = {} ---@type string[]
  for i, el in ipairs (first.made) do
    local sent = calls (el, 'set_meta')
    metas[i] = sent[#sent][2]
  end
  eq (known[metas[1]].name, 'Server')
  eq ({ known[metas[2]].group, known[metas[2]].pane }, { 1, 2 })
  eq ({ known[metas[3]].group, known[metas[3]].front }, { 2, true })

  -- The window reloads. The panel shows before the app has said what waits.
  local again = boot ({ json = known })
  again.views.terminal.on_show ()
  eq (#again.made, 0)
  again.waiting ({
    { id = 7, meta = metas[3], ended = false },
    { id = 5, meta = metas[1], ended = false },
    { id = 6, meta = metas[2], ended = true },
  })
  eq (#again.made, 3)
  local attached = {} ---@type integer[]
  for i, el in ipairs (again.made) do
    attached[i] = el.opts.attach
    eq (el.opts.autostart, false)
  end
  eq (attached, { 5, 6, 7 })
  eq (again.made[3].opts.cwd, '/tmp')
  -- Each sits where it sat, so what each kept stays the same.
  for _, el in ipairs (again.made) do
    eq (calls (el, 'set_meta'), {})
  end

  -- One that has gone since the reload goes from its tab too, and one that is back stays.
  again.made[1].opts.on_attach (true)
  again.made[3].opts.on_attach (false)
  eq ((pane_of (again.made[1]) or {}).removed, false)
  eq ((pane_of (again.made[3]) or {}).removed, true)
  -- Only a terminal that had nothing to come back to opens a new one when the panel shows.
  eq (#again.made, 3)
end)
