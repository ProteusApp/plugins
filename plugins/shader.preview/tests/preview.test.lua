-- The preview sends the page every pass of the shader in front, with what each channel shows,
-- sends each image a channel shows once, and names what went wrong by pass.

---Loads a module of shader.core the way its own `require` does.
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

---@type Shader.Core
local core = {
  types = core_require ('shader_types'),
  nodes = core_require ('shader_nodes'),
  helpers = core_require ('shader_helpers'),
  graph = core_require ('shader_graph'),
  compile = core_require ('shader_compile'),
  layout = core_require ('shader_layout'),
  source = core_require ('shader_source'),
  passes = core_require ('shader_passes'),
  file = core_require ('shader_file'),
  format = core_require ('shader_format'),
  history = core_require ('shader_history'),
  examples = core_require ('shader_examples'),
  build = core_require ('shader_build'),
  subgraph = core_require ('shader_subgraph'),
  export = core_require ('shader_export'),
}

---@param path string
---@return Proteus.Plugin
local function plugin (path)
  return assert (load (read (path), '@' .. path, 't')) () --[[@as Proteus.Plugin]]
end

---@class PreviewTest.Run
---@field files table<string, string>
---@field docs Shader.Docs
---@field posts table[] What the page was sent.
---@field sent table[] Each `send_file`: the grant and its tag.
---@field picked? table The options of the last image dialog.
---@field answer fun(grants: Proteus.FileGrant[]?) Answers the image dialog.
---@field page fun(message: table) A message from the page.
---@field elements table[] Every element the preview made, with its tag and spec.
---@field flush fun()

---A stand-in element: every method does nothing and returns the element.
---@param tag string
---@param spec any
---@param run PreviewTest.Run
---@param on_widget? fun(method: string, ...: any)
---@return table
local function element (tag, spec, run, on_widget)
  local e = { tag = tag, spec = type (spec) == 'table' and spec or {} }
  run.elements[#run.elements + 1] = e
  return setmetatable (e, {
    __index = function (_, method)
      return function (self, ...)
        if method == 'widget' and on_widget then
          on_widget (...)
        end
        return self
      end
    end,
  })
end

---Starts shader.docs and shader.preview on an app that keeps its files in a table.
---@return PreviewTest.Run
local function start ()
  local run = { files = {}, posts = {}, sent = {}, elements = {} } ---@type PreviewTest.Run
  local handlers = {} ---@type table<string, function[]>
  local timers = {} ---@type function[]
  local store = { examples = true, open = {} } ---@type table<string, any>
  local services = {} ---@type table<string, any>
  local answer ---@type fun(grants: Proteus.FileGrant[]?)?
  run.flush = function ()
    while #timers > 0 do
      table.remove (timers, 1) ()
    end
  end
  run.answer = function (grants)
    assert (answer, 'no dialog is open') (grants)
  end

  local ui = setmetatable ({
    css = function () end,
    h = function (tag, spec)
      return element (tag, spec, run)
    end,
    webview = function (opts)
      run.page = function (message)
        opts.on_message (message)
      end
      return element ('webview', opts, run, function (method, a, b)
        if method == 'post' then
          run.posts[#run.posts + 1] = a
        elseif method == 'send_file' then
          run.sent[#run.sent + 1] = { a, b }
        end
      end)
    end,
  }, {
    __index = function (_, tag)
      return function (spec)
        return element (tag, spec, run)
      end
    end,
  })
  services.ui = ui
  services.shader = core
  services.tabs = {
    open = function ()
      return {
        set_title = function () end,
        set_dirty = function () end,
        focus = function () end,
        close = function () end,
      }
    end,
    get = function () end,
  }
  services.commands = {
    register = function () end,
    run = function () end,
  }
  services.views = { add = function () end, show = function () end }

  local function emit (event, ...)
    for _, fn in ipairs (handlers[event] or {}) do
      fn (...)
    end
  end
  local app = {
    use = function (name)
      return assert (services[name], name)
    end,
    try_use = function (name)
      return services[name]
    end,
    provide = function (name, value)
      services[name] = value
    end,
    on = function (event, fn)
      handlers[event] = handlers[event] or {}
      table.insert (handlers[event], fn)
    end,
    emit = emit,
    log = function () end,
    warn = function () end,
    store = {
      get = function (key, default)
        if store[key] == nil then
          return default
        end
        return store[key]
      end,
      set = function (key, value)
        store[key] = value
      end,
    },
    timer = {
      after = function (_, fn)
        timers[#timers + 1] = fn
      end,
    },
    util = {
      now = function ()
        return 0
      end,
    },
    dom = {
      focus_info = function ()
        return { editable = false }
      end,
    },
    plugin = {
      list = function ()
        return {}
      end,
    },
    grants = {
      open = function (opts, cb)
        run.picked = opts
        answer = cb
      end,
    },
    fs = {
      read = function (path)
        return run.files[path]
      end,
      write = function (path, text)
        run.files[path] = text
        emit ('fs:changed', path)
      end,
      exists = function (path)
        return run.files[path] ~= nil
      end,
      files = function ()
        local out = {} ---@type string[]
        for path in pairs (run.files) do
          out[#out + 1] = path
        end
        return out
      end,
    },
  }
  -- selene: allow(mixed_table)
  plugin ('plugins/shader.docs/init.lua').activate (app --[[@as any]])
  run.docs = services['shader.docs']
  run.docs.register_opener ('graph', function ()
    return {} --[[@as Proteus.El]]
  end)
  run.docs.register_opener ('code', function ()
    return {} --[[@as Proteus.El]]
  end)
  -- selene: allow(mixed_table)
  plugin ('plugins/shader.preview/init.lua').activate (app --[[@as any]])
  run.flush ()
  return run
end

---The last run message the page got.
---@param run PreviewTest.Run
---@return table?
local function last_run (run)
  for i = #run.posts, 1, -1 do
    if run.posts[i].type == 'run' then
      return run.posts[i]
    end
  end
  return nil
end

---The ids of a run's passes, in order.
---@param message table
---@return string[]
local function ids (message)
  local out = {} ---@type string[]
  for i, p in ipairs (message.passes) do
    out[i] = p.id
  end
  return out
end

---The menu of what a channel shows.
---@param run PreviewTest.Run
---@param index integer
---@return table?
local function channel_menu (run, index)
  for i = #run.elements, 1, -1 do
    local e = run.elements[i]
    if
      e.tag == 'select'
      and e.spec.title == 'What iChannel' .. index .. ' shows'
    then
      return e
    end
  end
  return nil
end

local IMAGE = 'shaders/ink.frag'
local BUFFER = 'shaders/ink.buffer-a.frag'

---@param run PreviewTest.Run
local function ink (run)
  run.files[IMAGE] =
    '// @channel 0 buffer-a\nvoid mainImage(out vec4 c, in vec2 f) {\n  c = texture(iChannel0, f / iResolution.xy) + texture(iChannel1, vec2(0.0));\n}\n'
  run.files[BUFFER] =
    core.source.TEMPLATES.buffer:gsub ('{{BUFFER}}', 'buffer-a') --[[@as string]]
end

test (
  'the page runs each buffer before the image, with what each channel shows',
  function ()
    local run = start ()
    ink (run)
    assert (run.docs.open (IMAGE))
    run.flush ()
    local message = assert (last_run (run))
    eq (message.language, 'glsl')
    eq (message.show, 'image')
    eq (ids (message), { 'a', 'image' })
    local image = message.passes[2].program
    eq (image.channels[1].source, { kind = 'buffer', buffer = 'a' })
    eq (image.channels[2].source, { kind = 'none' })
    eq (message.passes[1].program.channels[1].source, {
      kind = 'buffer',
      buffer = 'a',
    })

    -- A buffer in front shows its own picture, and the image does not run.
    assert (run.docs.open (BUFFER))
    run.flush ()
    message = assert (last_run (run))
    eq (message.show, 'a')
    eq (ids (message), { 'a' })
  end
)

test ('a pick in the Channels menu runs the shader again', function ()
  local run = start ()
  ink (run)
  assert (run.docs.open (IMAGE))
  run.flush ()
  local before = #run.posts
  local menu = assert (channel_menu (run, 1), 'iChannel1 has a menu')
  menu.spec.onchange ({ value = 'noise' })
  run.flush ()
  ok (#run.posts > before)
  local message = assert (last_run (run))
  eq (message.passes[2].program.channels[2].source, { kind = 'noise' })
  eq (run.docs.channels (IMAGE)[1], { kind = 'noise' })
end)

test (
  'an image is picked through a dialog and sent to the page once',
  function ()
    local run = start ()
    ink (run)
    assert (run.docs.open (IMAGE))
    run.flush ()
    assert (channel_menu (run, 1)).spec.onchange ({ value = 'image' })
    run.flush ()
    local picked = assert (run.picked, 'a dialog opened')
    eq (picked.filters[1].name, 'Images')
    run.answer ({ { id = 'f7', name = 'wood.png', mode = 'read' } })
    run.flush ()
    eq (
      run.docs.channels (IMAGE)[1],
      { kind = 'image', grant = 'f7', name = 'wood.png' }
    )
    eq (run.sent, { { 'f7', 'f7' } })
    -- Another change does not send it again.
    run.docs.set_uniform (IMAGE, 'x', { 1 })
    run.docs.set_text (IMAGE, run.files[IMAGE] .. '\n')
    run.flush ()
    eq (#run.sent, 1)
    -- A file the page could not use shows as a problem until it is picked again.
    run.page ({
      type = 'file',
      grant = 'f7',
      name = 'wood.png',
      error = 'not allowed',
    })
    run.flush ()
    local found = false
    for _, e in ipairs (run.elements) do
      if
        e.tag == 'span'
        and type (e.spec[1]) == 'string'
        and e.spec[1]:find (
          'wood.png, which did not arrive: not allowed',
          1,
          true
        )
      then
        found = true
      end
    end
    ok (found, 'the problem names the file')
    assert (channel_menu (run, 1)).spec.onchange ({ value = 'image' })
    run.answer ({ { id = 'f7', name = 'wood.png', mode = 'read' } })
    run.flush ()
    eq (#run.sent, 2, 'picking it again sends it again')
  end
)

test (
  'a buffer in another language is a problem, and the rest still runs',
  function ()
    local run = start ()
    ink (run)
    run.files['shaders/ink.buffer-b.wgsl'] = core.source.TEMPLATES.wgsl
    assert (run.docs.open (IMAGE))
    run.flush ()
    eq (ids (assert (last_run (run))), { 'a', 'image' })
    -- The problems show once the page has compiled.
    run.page ({ type = 'status', ok = true, errors = {} })
    local found = false
    for _, e in ipairs (run.elements) do
      if
        e.tag == 'span'
        and e.spec[1]
          == 'Buffer B is WGSL, and this shader runs GLSL. Every pass runs in one language.'
      then
        found = true
      end
    end
    ok (found)
  end
)

test ('the page names the pass a problem is in', function ()
  local run = start ()
  ink (run)
  assert (run.docs.open (IMAGE))
  run.flush ()
  run.page ({
    type = 'status',
    ok = false,
    errors = {
      {
        pass = 'a',
        line = 12,
        message = 'x: undeclared',
        stage = 'fragment',
        severity = 'error',
      },
    },
  })
  local where = nil ---@type string?
  for i = #run.elements, 1, -1 do
    local e = run.elements[i]
    if e.tag == 'span' and e.spec.class == 'where' and not where then
      where = e.spec[1]
    end
  end
  -- The short buffer gets seven lines above it, so line 12 is its line 5.
  eq (where, 'Buffer A line 5')
end)

---The menu of what the picture shows on.
---@param run PreviewTest.Run
---@return table?
local function view_menu (run)
  for i = #run.elements, 1, -1 do
    local e = run.elements[i]
    if e.tag == 'select' and e.spec.class == 'sp-view' then
      return e
    end
  end
  return nil
end

---The last view message the page got.
---@param run PreviewTest.Run
---@return string?
local function last_view (run)
  for i = #run.posts, 1, -1 do
    if run.posts[i].type == 'view' then
      return run.posts[i].shape
    end
  end
  return nil
end

test ('the View menu puts the shader on a mesh', function ()
  local run = start ()
  eq (last_view (run), 'flat')
  local menu = assert (view_menu (run), 'the bar has a View menu')
  menu.spec.onchange ({ value = 'torus' })
  eq (last_view (run), 'torus')
end)

test (
  'a graph runs on a mesh as its surface, and a Shadertoy shader as a picture',
  function ()
    local run = start ()
    local d = assert (run.docs.new_graph ('Mesh'))
    run.flush ()
    local message = assert (last_run (run))
    eq (message.passes[1].program.surface, true)
    ink (run)
    assert (run.docs.open (IMAGE))
    run.flush ()
    message = assert (last_run (run))
    eq (message.passes[2].program.surface, false)
    ok (d.path)
  end
)

---A string constant of the page's script, with `${...}` filled in from `values`.
---@param name string
---@param values? table<string, string>
---@return string
local function page_constant (name, values)
  local js = read ('plugins/shader.preview/page/preview.js')
  local text = assert (
    js:match ('const ' .. name .. ' = `(.-)`;'),
    name .. ' is in the page'
  )
  return (
    text:gsub ('%${([%w_]+)}', function (key)
      return assert ((values or {})[key], key)
    end)
  )
end

test ('the page draws meshes with code that compiles', function ()
  local graph = core.graph
  local result = core.compile.compile (graph.new ('Mesh'))
  local vertex = page_constant ('GL_MESH_VERTEX')
  local good, messages = shader_check ('glsl', 'vertex', vertex)
  ok (good ~= false, messages)
  local module = result.wgsl.source
    .. '\n'
    .. page_constant ('GPU_MESH_VERTEX', { GPU_MESH_GROUP = '2' })
  good, messages = shader_check ('wgsl', 'fragment', module)
  ok (good ~= false, messages)
  good, messages =
    shader_check ('wgsl', 'fragment', page_constant ('GPU_MESH_COPY'))
  ok (good ~= false, messages)
  -- The graph's fragment shader reads the UV the mesh's vertex stage writes.
  ok (result.glsl.source:find ('in vec2 v_uv;', 1, true) ~= nil)
  ok (vertex:find ('out vec2 v_uv;', 1, true) ~= nil)
end)
