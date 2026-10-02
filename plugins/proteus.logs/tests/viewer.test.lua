-- Runs the log viewer against a stand-in for the app: elements that keep their children and
-- handlers, timers the test runs, and programs whose lines the test sends.

---@class LogsFake.El
---@field props table<string, any>
---@field handlers table<string, fun(ev: table): any>
---@field kids LogsFake.El[]
---@field visible boolean
---@field shown_text string
---@field classes table<string, boolean>
local El = {}

local el_meta = {
  __index = function (_, key)
    return El[key] or function () end
  end,
}

---@param props? table<string, any>
---@return LogsFake.El
local function element (props)
  local kids = {} ---@type LogsFake.El[]
  for _, v in ipairs (type (props) == 'table' and props or {}) do
    if type (v) == 'table' and getmetatable (v) == el_meta then
      kids[#kids + 1] = v
    end
  end
  return setmetatable ({
    props = type (props) == 'table' and props or {},
    handlers = {},
    kids = kids,
    visible = true,
    shown_text = '',
    classes = {},
  }, el_meta)
end

function El:on (name, fn)
  self.handlers[name] = fn
end
function El:append (child)
  self.kids[#self.kids + 1] = child
end
function El:clear ()
  self.kids = {}
end
function El:set_children (list)
  self.kids = list
end
function El:remove ()
  self.removed = true
end
function El:show (on)
  self.visible = on ~= false
end
function El:text (t)
  self.shown_text = tostring (t)
end
function El:class (name, on)
  self.classes[name] = on ~= false
end
function El:get ()
  return 0
end
function El:value ()
  return ''
end
-- The kernel refuses a restricted plugin the DOM methods that reach past its elements.
function El:call (method)
  if method == 'insertAdjacentHTML' or method == 'setAttribute' then
    error ('a restricted plugin may not call ' .. method)
  end
end
---@param name string
---@param ev? table
function El:fire (name, ev)
  local fn = self.handlers[name]
  assert (fn, 'no ' .. name .. ' handler')
  return fn (ev or {})
end

---@return table app
---@return table world
local function fake_app ()
  local world = {
    made = {}, ---@type table<string, LogsFake.El[]>
    commands = {}, ---@type table<string, Proteus.CommandSpec>
    timers = {}, ---@type fun()[]
    spawned = {}, ---@type { program: string, args: string[], opts: Proteus.SpawnOptions }[]
    picks = {}, ---@type string[]
    said = {}, ---@type string[]
  }
  local store = {} ---@type table<string, any>
  local ui = setmetatable ({
    css = function ()
      return element ()
    end,
  }, {
    __index = function (_, name)
      return function (a, b)
        local props = type (a) == 'table' and a or b
        local el = element (props)
        if name == 'widget' then
          el = element (b)
        end
        local class = type (props) == 'table' and props.class or nil
        if type (class) == 'string' then
          for c in class:gmatch ('%S+') do
            world.made[c] = world.made[c] or {}
            table.insert (world.made[c], el)
          end
        end
        return el
      end
    end,
  })
  local app = {
    platform = 'desktop',
    os = 'linux',
    log = function () end,
    warn = function (...)
      world.said[#world.said + 1] = table.concat ({ ... }, ' ')
    end,
    util = {
      icon = function ()
        return ''
      end,
    },
    store = {
      get = function (k, default)
        if store[k] == nil then
          return default
        end
        return store[k]
      end,
      set = function (k, v)
        store[k] = v
      end,
    },
    timer = {
      after = function (_, fn)
        world.timers[#world.timers + 1] = fn
        return function () end
      end,
    },
    system = { clipboard = function () end, clipboard_read = function () end },
    fs = {
      pick_open = function (_, cb)
        cb ({ table.remove (world.picks, 1) })
      end,
    },
    process = {
      spawn = function (program, args, opts)
        world.spawned[#world.spawned + 1] =
          { program = program, args = args, opts = opts }
        return { kill = function () end, write = function () end }
      end,
    },
  }
  local services = {
    ui = ui,
    shell = { mount = function () end },
    views = { add = function () end, show = function () end },
    commands = {
      register = function (spec)
        world.commands[spec.id] = spec
      end,
      run = function (id)
        world.commands[id].run ()
      end,
    },
    status = {
      add = function ()
        return { set = function () end }
      end,
    },
    notify = {
      info = function (t)
        world.said[#world.said + 1] = t
      end,
      error = function (t)
        world.said[#world.said + 1] = t
      end,
    },
  }
  app.use = function (name)
    return services[name]
  end
  app.try_use = function (name)
    return services[name]
  end
  return app, world
end

---@return table world
local function start ()
  local app, world = fake_app ()
  local plugin = require ('init') --[[@as Proteus.Plugin]]
  plugin.activate (app)
  return world
end

---Runs the timers that are due, and those they start.
---@param world table
local function tick (world)
  while #world.timers > 0 do
    table.remove (world.timers, 1) ()
  end
end

---@param world table
---@param class string
---@param n? integer
---@return LogsFake.El
local function find (world, class, n)
  local list = assert (world.made[class], 'no element of the class ' .. class)
  return list[n or 1]
end

---The text of each drawn row, in order.
---@param world table
---@return string[]
local function rows (world)
  local out = {} ---@type string[]
  for _, chunk in ipairs (find (world, 'logs-rows').kids) do
    for _, batch in ipairs (chunk.kids) do
      local html = batch.props.html or ''
      for text in html:gmatch ('<span class="logs%-t">(.-)</span></div>') do
        out[#out + 1] = (text:gsub ('<[^>]*>', ''))
      end
    end
  end
  return out
end

---Opens a file and sends its lines.
---@param world table
---@param command string
---@param path string
---@param lines string[]
---@return table
local function open (world, command, path, lines)
  world.picks = { path }
  world.commands[command].run ()
  local proc = world.spawned[#world.spawned]
  for _, line in ipairs (lines) do
    proc.opts.on_message (line)
  end
  tick (world)
  return proc
end

---@param world table
---@param text string
local function filter (world, text)
  find (world, 'logs-filter'):fire ('input', { value = text })
  tick (world)
end

test (
  'a file shows its lines, and a regular expression filters them',
  function ()
    local world = start ()
    local proc = open (world, 'logs.open_file', '/var/log/app.log', {
      '2024-03-01T12:00:00Z INFO started',
      '2024-03-01T12:00:05Z ERROR request timed out',
      '2024-03-01T12:01:00Z WARN slow',
    })
    eq (proc.args, { '-n', '1000', '-F', '/var/log/app.log' })
    eq (#rows (world), 3)
    filter (world, '/time(d)? ?out|slow/')
    eq (rows (world), {
      '2024-03-01T12:00:05Z ERROR request timed out',
      '2024-03-01T12:01:00Z WARN slow',
    })
    filter (world, 'after:12:00:01 before:12:00:30')
    eq (rows (world), { '2024-03-01T12:00:05Z ERROR request timed out' })
    filter (world, '/(broken/')
    ok (find (world, 'logs-problem').visible)
    eq (#rows (world), 3, 'a broken expression hides nothing')
  end
)

test ('a whole file is read from its first line', function ()
  local world = start ()
  local proc = open (world, 'logs.open_whole', '/var/log/big.log', { 'one' })
  eq (proc.args, { '-n', '+1', '-F', '/var/log/big.log' })
end)

test ('every matching line can be reached, a window at a time', function ()
  local world = start ()
  local lines = {} ---@type string[]
  for i = 1, 6000 do
    lines[i] = 'line ' .. i
  end
  open (world, 'logs.open_file', '/var/log/many.log', lines)
  local shown = rows (world)
  eq (#shown, 5000)
  eq (shown[1], 'line 1001')
  ok (find (world, 'logs-page', 1).visible, 'the bar for earlier lines shows')
  world.commands['logs.earlier'].run ()
  shown = rows (world)
  eq (shown[1], 'line 1')
  eq (shown[#shown], 'line 5000')
  ok (find (world, 'logs-page', 2).visible, 'the bar for later lines shows')
  world.commands['logs.follow_newest'].run ()
  eq (rows (world)[1], 'line 1001')
end)

test ('the merged view puts two sources in order of time', function ()
  local world = start ()
  open (world, 'logs.open_file', '/var/log/a.log', {
    '2024-03-01T12:00:00Z a first',
    '2024-03-01T12:00:02Z a second',
    '    at a trace line',
  })
  open (world, 'logs.open_file', '/var/log/b.log', {
    '2024-03-01T12:00:01Z b first',
    '2024-03-01T12:00:03Z b second',
  })
  world.commands['logs.merged'].run ()
  local shown = rows (world)
  eq (#shown, 5)
  ok (shown[1]:find ('a first', 1, true), shown[1])
  ok (shown[2]:find ('b first', 1, true), shown[2])
  ok (shown[3]:find ('a second', 1, true), shown[3])
  ok (
    shown[4]:find ('a trace line', 1, true),
    'a line with no time stays after its line'
  )
  ok (shown[5]:find ('b second', 1, true), shown[5])
  local html = find (world, 'logs-rows').kids[1].kids[1].props.html
  ok (
    html:find ('<span class="logs-tag logs-tag-1">a.log</span>', 1, true),
    'each row names its source'
  )
end)

test ('a click shows a line, with its time, and arrows move', function ()
  local world = start ()
  open (world, 'logs.open_file', '/var/log/app.log', {
    '2024-03-01T12:00:00Z INFO first',
    '    a line after it',
  })
  local html = find (world, 'logs-rows').kids[1].kids[1].props.html
  local first_id = tonumber (html:match ('data%-item="(%d+)"'))
  local list = find (world, 'logs-list')
  list:fire ('click', { item = tostring (first_id) })
  local title = find (world, 'logs-detail-title').shown_text
  ok (title:find ('Line 1', 1, true), title)
  ok (title:find ('2024-03-01 12:00:00', 1, true), title)
  list:fire ('keydown', { key = 'ArrowDown' })
  title = find (world, 'logs-detail-title').shown_text
  ok (title:find ('Line 2', 1, true), title)
  ok (title:find ('(from the line above)', 1, true), title)
end)
