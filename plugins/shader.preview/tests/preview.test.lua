-- The live preview: what it sends its page, and how the page's compiler errors come back as
-- lines of the user's text or nodes of a graph, against a fake UI library and shader.docs.

---@type table<string, any>
local loaded = {}
---@param name string
---@return any
local function core_require (name)
  if loaded[name] == nil then
    -- selene: allow(global_usage)
    local env = setmetatable ({ require = core_require }, { __index = _G })
    local chunk = assert (
      load (
        read ('plugins/shader.core/' .. name .. '.lua'),
        '@' .. name,
        't',
        env
      )
    )
    loaded[name] = chunk ()
  end
  return loaded[name]
end

---@class PreviewTest.El
---@field kind string
---@field props table
---@field calls any[][]
---@field widget? fun(self: PreviewTest.El, method: string, message: table)

---@class PreviewTest.Run
---@field els PreviewTest.El[]
---@field posted table[] What the dock's page was sent.
---@field emitted any[][] Each app.emit, as `{ event, ... }`.
---@field status string[] What the status bar item showed.
---@field commands table<string, Proteus.CommandSpec>
---@field page PreviewTest.El The dock's web view.
---@field emit fun(event: string, ...: any)
---@field flush fun()
---@field active? table
---@field programs table<string, table> What docs.program gives by path.

---@param kind string
---@param props? table
---@return PreviewTest.El
local function element (kind, props)
  local el = { kind = kind, props = props or {}, calls = {} }
  return setmetatable (el, {
    __index = function (_, method)
      return function (self, ...)
        self.calls[#self.calls + 1] = { method, ... }
      end
    end,
  })
end

---@return PreviewTest.Run
local function start ()
  local state = {
    els = {},
    posted = {},
    emitted = {},
    status = {},
    commands = {},
    programs = {},
  }
  local run = state --[[@as PreviewTest.Run]]
  local handlers = {} ---@type table<string, function[]>
  local timers = {} ---@type function[]
  ---@param kind string
  ---@return fun(props?: table): PreviewTest.El
  local function maker (kind)
    return function (props)
      local el = element (kind, type (props) == 'table' and props or {})
      run.els[#run.els + 1] = el
      if kind == 'webview' and not run.page then
        run.page = el
        el.widget = function (_, method, message)
          if method == 'post' then
            run.posted[#run.posted + 1] = message
          end
        end
      end
      return el
    end
  end
  local ui = setmetatable ({ css = function () end }, {
    __index = function (_, name)
      return maker (name)
    end,
  })
  local docs = {
    active = function ()
      return run.active
    end,
    get = function (path)
      return run.active and run.active.path == path and run.active or nil
    end,
    program = function (path)
      return run.programs[path], {}
    end,
    set_uniform = function () end,
  }
  local services = {
    ui = ui,
    shader = { format = core_require ('shader_format') },
    ['shader.docs'] = docs,
    views = { add = function () end, show = function () end },
    commands = {
      register = function (spec)
        run.commands[spec.id] = spec
      end,
    },
    status = {
      add = function ()
        return {
          set = function (text)
            run.status[#run.status + 1] = text
          end,
        }
      end,
    },
  }
  local app = {
    use = function (name)
      return assert (services[name], name)
    end,
    try_use = function (name)
      return services[name]
    end,
    on = function (event, fn)
      handlers[event] = handlers[event] or {}
      table.insert (handlers[event], fn)
    end,
    emit = function (event, ...)
      run.emitted[#run.emitted + 1] = { event, ... }
    end,
    timer = {
      after = function (_, fn)
        timers[#timers + 1] = fn
      end,
    },
    store = {
      get = function (_, default)
        return default
      end,
      set = function () end,
    },
    util = {
      escape = function (s)
        return tostring (s)
      end,
    },
  }
  run.emit = function (event, ...)
    for _, fn in ipairs (handlers[event] or {}) do
      fn (...)
    end
  end
  run.flush = function ()
    while #timers > 0 do
      table.remove (timers, 1) ()
    end
  end
  local plugin = assert (
    load (read ('plugins/shader.preview/init.lua'), '@shader.preview', 't')
  ) () --[[@as Proteus.Plugin]]
  plugin.activate (app --[[@as Proteus.App]])
  return run
end

---The posts of one type.
---@param run PreviewTest.Run
---@param kind string
---@return table[]
local function posts (run, kind)
  local out = {} ---@type table[]
  for _, m in ipairs (run.posted) do
    if m.type == kind then
      out[#out + 1] = m
    end
  end
  return out
end

---The problems the dock last sent the code editor.
---@param run PreviewTest.Run
---@return table[]?
local function last_problems (run)
  local found ---@type table[]?
  for _, e in ipairs (run.emitted) do
    if e[1] == 'shader:problems' then
      found = e[3]
    end
  end
  return found
end

local CODE = { path = 'shaders/a.frag', kind = 'code', language = 'glsl' }

---A code shader of 10 lines, after 3 lines the app adds.
---@return table
local function code_program ()
  return {
    language = 'glsl',
    source = 'SOURCE',
    offset = 3,
    user_lines = 10,
    uniforms = {
      {
        key = 'speed',
        glsl = 'u_speed',
        type = 'float',
        value = { 1 },
        min = 0,
        max = 4,
        color = false,
      },
    },
  }
end

test (
  'the page is sent the shader in front, and only again when its code changes',
  function ()
    local run = start ()
    run.active = CODE
    run.programs[CODE.path] = code_program ()
    run.flush ()
    eq (posts (run, 'scale'), { { type = 'scale', scale = 1 } })
    local runs = posts (run, 'run')
    eq (#runs, 1)
    eq (runs[1].program.source, 'SOURCE')
    eq (
      runs[1].program.uniforms,
      { { key = 'speed', glsl = 'u_speed', type = 'float', value = { 1 } } }
    )
    run.emit ('shader:changed', CODE.path)
    run.flush ()
    eq (#posts (run, 'run'), 1, 'the same code runs on')
    eq (
      posts (run, 'uniform'),
      { { type = 'uniform', key = 'speed', value = { 1 } } }
    )
  end
)

test ("the page's errors come back as lines of the user's text", function ()
  local run = start ()
  run.active = CODE
  run.programs[CODE.path] = code_program ()
  run.flush ()
  run.page.props.on_message ({
    type = 'status',
    errors = {
      { message = 'past the end', line = 20 },
      { message = 'undeclared x', line = 5, column = 2 },
      { message = 'in the added lines', line = 2 },
      'not an error',
    },
  })
  eq (last_problems (run), {
    { message = 'undeclared x', line = 2, column = 2, stage = 'fragment' },
  })
end)

test ("a graph's errors point at the node that wrote the line", function ()
  local run = start ()
  local graph =
    { path = 'shaders/g.shader.json', kind = 'graph', language = 'glsl' }
  run.active = graph
  local p = code_program ()
  p.lines = { [6] = 'noise1' }
  run.programs[graph.path] = p
  run.flush ()
  run.page.props.on_message ({
    type = 'status',
    errors = { { message = 'bad', line = 6 } },
  })
  eq (last_problems (run), {}, 'a graph has no lines to mark')
  local shown = false
  for _, el in ipairs (run.els) do
    if
      el.kind == 'span'
      and el.props.class == 'where'
      and el.props[1] == 'node noise1'
    then
      shown = true
    end
  end
  ok (shown, 'the problem names the node')
end)

test ('a page that stops answering is a problem', function ()
  local run = start ()
  run.active = CODE
  run.programs[CODE.path] = code_program ()
  run.flush ()
  run.page.props.on_status ({ responsive = false })
  local said = false
  for _, el in ipairs (run.els) do
    if
      el.kind == 'span' and el.props[1] == 'The preview stopped answering.'
    then
      said = true
    end
  end
  ok (said)
end)

test ('the frame rate shows in the status bar', function ()
  local run = start ()
  run.page.props.on_message ({ type = 'stats', fps = 59.6, time = 1.25 })
  eq (run.status, { '60 fps' })
end)

test (
  'pause and play reach the page, and a control moves only the shader in front',
  function ()
    local run = start ()
    run.active = CODE
    run.programs[CODE.path] = code_program ()
    run.flush ()
    run.commands['shader.toggle_play'].run ()
    run.commands['shader.toggle_play'].run ()
    eq (#posts (run, 'pause'), 1)
    eq (#posts (run, 'play'), 1)
    run.emit ('shader:uniform', 'shaders/other.frag', 'speed', { 2 })
    run.emit ('shader:uniform', CODE.path, 'speed', { 3 })
    eq (
      posts (run, 'uniform'),
      { { type = 'uniform', key = 'speed', value = { 3 } } }
    )
  end
)

test ('with no shader in front there is nothing to run', function ()
  local run = start ()
  run.flush ()
  eq (posts (run, 'run'), {})
  local said = false
  for _, el in ipairs (run.els) do
    if el.kind == 'div' and el.props[1] == 'Open a shader to see it run.' then
      said = true
    end
  end
  ok (said)
end)
