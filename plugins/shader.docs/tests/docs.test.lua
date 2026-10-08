-- The open shaders follow their files: a deleted file is never written back, a changed one
-- loads again, and a rename moves the open shader with its undo. A shader's buffers are
-- found by their names, and its channels show what the notes or the user give them.

---Loads a module of shader.core the way its own `require` does, since a test here reaches
---only this plugin's folder through `require`.
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

local plugin =
  assert (load (read ('plugins/shader.docs/init.lua'), '@shader.docs', 't')) () --[[@as Proteus.Plugin]]

---@class DocsTest.Run
---@field api Shader.Docs
---@field files table<string, string> The workspace, by path.
---@field listed integer How often the workspace was listed.
---@field emit fun(event: string, ...: any)
---@field flush fun() Runs the timers that are due.
---@field asked string[] The prompts the picker showed.
---@field pending table? The question the picker has open.
---@field closed string[] The ids of the tabs that closed.
---@field store table<string, any> What the plugin keeps in app.store.

---Starts shader.docs on an app that keeps its files in a table.
---@param with_picker? boolean
---@return DocsTest.Run
local function start (with_picker)
  local run = {
    files = {},
    listed = 0,
    asked = {},
    closed = {},
  } ---@type DocsTest.Run
  local handlers = {} ---@type table<string, function[]>
  local timers = {} ---@type function[]
  local store = { examples = true } ---@type table<string, any>
  run.store = store
  local services = {} ---@type table<string, any>

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

  services.shader = core
  services.tabs = {
    ---@param spec table
    open = function (spec)
      return {
        set_title = function () end,
        set_dirty = function () end,
        focus = function () end,
        close = function ()
          run.closed[#run.closed + 1] = spec.id
        end,
      }
    end,
  }
  services.commands = { register = function () end }
  if with_picker then
    services.picker = {
      ---@param opts table
      pick = function (opts)
        run.asked[#run.asked + 1] = opts.prompt
        run.pending = opts
      end,
      confirm = function () end,
      input = function () end,
    }
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
    emit = function () end,
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
      read = function ()
        return nil
      end,
    },
    fs = {
      read = function (path)
        return run.files[path]
      end,
      write = function (path, text)
        run.files[path] = text
      end,
      exists = function (path)
        return run.files[path] ~= nil
      end,
      remove = function (path)
        run.files[path] = nil
      end,
      rename = function (from, to)
        run.files[to] = run.files[from]
        run.files[from] = nil
      end,
      files = function ()
        run.listed = run.listed + 1
        local out = {} ---@type string[]
        for path in pairs (run.files) do
          out[#out + 1] = path
        end
        return out
      end,
    },
  }
  -- selene: allow(mixed_table)
  plugin.activate (app --[[@as any]])
  run.api = services['shader.docs']
  run.api.register_opener ('graph', function ()
    return {} --[[@as Proteus.El]]
  end)
  run.api.register_opener ('code', function ()
    return {} --[[@as Proteus.El]]
  end)
  run.flush ()
  return run
end

local PATH = 'shaders/glow.shader.json'

---Starts shader.docs with one graph open.
---@param with_picker? boolean
---@return DocsTest.Run, Shader.OpenDoc
local function with_graph (with_picker)
  local run = start (with_picker)
  run.files[PATH] = core.file.save (core.graph.new ('Glow'))
  return run, assert (run.api.open (PATH))
end

---Changes the open graph's name, as an edit on the canvas would.
---@param run DocsTest.Run
---@param name string
local function edit (run, name)
  local d = assert (run.api.get (PATH))
  run.api.change (PATH, core.graph.rename (d.history.doc, name), 'name')
end

test ('a graph is unsaved after an edit, and saved again after undo', function ()
  local run, d = with_graph ()
  eq (d.dirty, false)
  edit (run, 'Brighter')
  eq (d.dirty, true)
  run.api.undo (PATH)
  eq (d.dirty, false, 'undo brings back the saved graph')
  edit (run, 'Brighter')
  ok (run.api.save (PATH))
  eq (d.dirty, false)
  eq (core.file.load (run.files[PATH]).name, 'Brighter')
end)

test ('a deleted file stays deleted until a save', function ()
  local run, d = with_graph ()
  edit (run, 'Brighter')
  run.files[PATH] = nil
  run.emit ('fs:changed', PATH)
  run.flush ()
  eq (d.missing, true)
  eq (d.dirty, true)
  eq (run.files[PATH], nil, 'nothing wrote the file back')
  ok (run.api.save (PATH))
  eq (d.missing, false)
  ok (run.files[PATH] ~= nil)
end)

test ('removing an open shader closes its tab', function ()
  local run = with_graph ()
  ok (run.api.remove (PATH))
  eq (run.files[PATH], nil)
  eq (run.api.get (PATH), nil)
  eq (run.closed, { 'shader:' .. PATH })
end)

test ('a file changed outside loads, or asks when there are edits', function ()
  local run, d = with_graph (true)
  run.files[PATH] = core.file.save (core.graph.new ('Outside'))
  run.emit ('fs:changed', PATH)
  run.flush ()
  eq (d.history.doc.name, 'Outside', 'with no edits it loads')
  eq (d.dirty, false)
  eq (#run.asked, 0)

  edit (run, 'Mine')
  run.files[PATH] = core.file.save (core.graph.new ('Again'))
  run.emit ('fs:changed', PATH)
  run.flush ()
  eq (#run.asked, 1, 'with edits it asks')
  eq (d.history.doc.name, 'Mine', 'and keeps them until the answer')

  -- A change while it asks reads the file again once answered.
  run.files[PATH] = core.file.save (core.graph.new ('Third'))
  run.emit ('fs:changed', PATH)
  run.flush ()
  eq (#run.asked, 1, 'one question at a time')
  assert (run.pending, 'it asks again').on_pick ({ value = 'load' })
  eq (d.history.doc.name, 'Third')
  run.api.undo (PATH)
  eq (d.history.doc.name, 'Mine', 'undo brings back the edits')
end)

test ('its own save does not reload the shader', function ()
  local run, d = with_graph ()
  edit (run, 'Saved')
  local before = d.history
  run.api.save (PATH)
  run.emit ('fs:changed', PATH)
  run.flush ()
  ok (d.history == before)
  eq (d.dirty, false)
end)

test ('the file list is kept until a file in shaders/ changes', function ()
  local run = with_graph ()
  run.files['notes.txt'] = 'x'
  run.files['shaders/build/out.frag'] = 'x'
  eq (run.api.files (), { PATH })
  run.api.files ()
  eq (run.listed, 1)
  run.emit ('fs:changed', 'notes.txt')
  run.api.files ()
  eq (run.listed, 1, 'a change outside shaders/ keeps the list')
  run.files['shaders/wave.frag'] = 'void main () {}'
  run.emit ('fs:changed', 'shaders/wave.frag')
  run.flush ()
  eq (run.api.files (), { PATH, 'shaders/wave.frag' })
  eq (run.listed, 2)
end)

test ('a rename moves the open shader with its undo', function ()
  local run, d = with_graph ()
  edit (run, 'Moved')
  local to = 'shaders/moved.shader.json'
  ok (run.api.rename (PATH, to))
  eq (run.api.get (PATH), nil)
  local moved = assert (run.api.get (to))
  ok (moved == d, 'the same document, with its history')
  eq (moved.dirty, true, 'unsaved changes stay unsaved')
  run.api.undo (to)
  eq (moved.history.doc.name, 'Glow')
  -- The rename event a host sends after the rename finds nothing left to move.
  run.emit ('fs:renamed', PATH, to)
  ok (run.api.get (to) == d)
  local refused, why = run.api.rename (to, 'shaders/moved.frag')
  eq (refused, false)
  ok (tostring (why):find ('.shader.json', 1, true), why)
end)

---@param list Shader.CompileError[]
---@return string[]
local function messages (list)
  local out = {} ---@type string[]
  for i, e in ipairs (list) do
    out[i] = e.message
  end
  return out
end

test ('a shader finds the buffers beside it', function ()
  local run = start ()
  run.files['shaders/ink.frag'] = 'void main() { fragColor = vec4(1.0); }'
  run.files['shaders/ink.buffer-b.frag'] =
    'void main() { fragColor = vec4(0.5); }'
  run.files['shaders/ink.buffer-a.shader.json'] =
    core.file.save (core.graph.new ('A'))
  local set = run.api.passes ('shaders/ink.buffer-b.frag')
  eq (set, {
    base = 'shaders/ink',
    show = 'b',
    image = 'shaders/ink.frag',
    buffers = {
      a = 'shaders/ink.buffer-a.shader.json',
      b = 'shaders/ink.buffer-b.frag',
    },
  })
  -- A buffer without a tab still has a program, and a graph one runs in the language asked.
  local p = assert (run.api.program ('shaders/ink.buffer-b.frag'))
  eq (p.language, 'glsl')
  local g =
    assert (run.api.program ('shaders/ink.buffer-a.shader.json', 'wgsl'))
  eq (g.language, 'wgsl')
  eq (run.api.get ('shaders/ink.buffer-b.frag'), nil, 'reading it opens no tab')
end)

test ('a channel shows what its note gives, until the user picks', function ()
  local run = start ()
  local path = 'shaders/ink.frag'
  run.files[path] =
    '// @channel 0 noise\nvoid main() { fragColor = texture(iChannel0, v_uv) + texture(iChannel1, v_uv); }\n'
  local d = assert (run.api.open (path))
  eq (run.api.channels (path)[0], { kind = 'noise' })
  eq (run.api.channels (path)[1], { kind = 'none' })
  local _, errors = run.api.program (path)
  eq (messages (errors), {
    'iChannel1 shows nothing, so it reads black. Pick what it shows under Channels in the Preview panel.',
  })
  local version = d.version
  run.api.set_channel (path, 1, { kind = 'buffer', buffer = 'a' })
  ok (d.version > version, 'the preview runs it again')
  eq (d.dirty, false, 'a pick is not a change to the code')
  _, errors = run.api.program (path)
  eq (#errors, 1)
  ok (
    errors[1].message:find ('Buffer A, which this shader does not have', 1, true)
  )
  run.api.set_channel (path, 0, { kind = 'checker' })
  eq (run.api.channels (path)[0], { kind = 'checker' })
  run.api.set_channel (path, 0, nil)
  eq (
    run.api.channels (path)[0],
    { kind = 'noise' },
    'nil goes back to the note'
  )

  -- The pick is kept for the file, and follows it through a rename.
  eq (
    run.store['channels:' .. path],
    { ['1'] = { kind = 'buffer', buffer = 'a' } }
  )
  ok (run.api.rename (path, 'shaders/pen.frag'))
  eq (
    run.store['channels:shaders/pen.frag'],
    { ['1'] = { kind = 'buffer', buffer = 'a' } }
  )
end)

test ('a graph keeps its channel picks in its file, with undo', function ()
  local run, d = with_graph ()
  run.api.set_channel (PATH, 2, { kind = 'noise' })
  eq (d.history.doc.channels, { ['2'] = { kind = 'noise' } })
  eq (d.dirty, true)
  ok (run.api.save (PATH))
  ok (run.files[PATH]:find ('"channels"', 1, true))
  run.api.undo (PATH)
  eq (d.history.doc.channels, nil)
end)

test (
  'a new buffer takes the next free letter, in the language of its shader',
  function ()
    local run = start ()
    run.files['shaders/ink.frag'] = 'void main() { fragColor = vec4(1.0); }'
    run.files['shaders/ink.buffer-a.frag'] =
      'void main() { fragColor = vec4(1.0); }'
    local b = assert (run.api.new_buffer ('shaders/ink.frag'))
    eq (b.path, 'shaders/ink.buffer-b.frag')
    ok (b.text:find ('// @channel 0 buffer-b', 1, true))
    local _, errors = run.api.program (b.path)
    eq (errors, {}, 'it reads its own last frame')

    run.files['shaders/sky.wgsl'] = core.source.TEMPLATES.wgsl
    local w = assert (run.api.new_buffer ('shaders/sky.wgsl'))
    eq (w.path, 'shaders/sky.buffer-a.wgsl')
    eq (w.language, 'wgsl')
    ok (w.text:find ('@channel 0 buffer-a', 1, true))

    local run2, g2 = with_graph ()
    local made = assert (run2.api.new_buffer (g2.path))
    eq (made.path, 'shaders/glow.buffer-a.shader.json')
    eq (made.history.doc.channels, { ['0'] = { kind = 'buffer', buffer = 'a' } })

    run.api.new_buffer ('shaders/ink.frag')
    run.api.new_buffer ('shaders/ink.frag')
    local none, why = run.api.new_buffer ('shaders/ink.frag')
    eq (none, nil)
    eq (why, 'This shader has all four buffers.')
  end
)

local GODOT =
  'shader_type canvas_item;\nvoid fragment() { COLOR = vec4(UV, 0.0, 1.0); }\n'

test (
  'a followed shader runs in front without a tab, and follows its text',
  function ()
    local run = start ()
    local path = '/home/me/game/water.gdshader'
    run.api.follow (path, GODOT)
    local d = assert (run.api.active ())
    eq (
      { d.path, d.language, d.follow, d.dirty },
      { path, 'gdshader', true, false }
    )
    eq (#run.api.list (), 0)
    local program = assert (run.api.program (path))
    eq (program.language, 'glsl')
    local version = d.version
    run.api.follow (path, GODOT:gsub ('UV', 'UV.yx') --[[@as string]])
    ok (d.version > version)
    ok (not d.dirty)
    ok (d.text:find ('UV.yx', 1, true))
    run.api.unfollow (path)
    eq (run.api.active (), nil)
    eq (run.api.get (path), nil)
  end
)

test ('a builder tab of the same file wins over following it', function ()
  local run, d = with_graph ()
  run.api.follow (PATH, 'not a graph')
  eq (run.api.active (), d)
  ok (not d.follow)
end)

test (
  'a shader on disk saves through the plugin that handed it over',
  function ()
    local run = start ()
    local path = '/home/me/game/water.gdshader'
    local wrote = {} ---@type table<string, string>
    run.api.attach_disk (function (p, text, done)
      wrote[p] = text
      done (nil)
    end)
    local d = assert (run.api.open_disk (path, { [path] = GODOT }))
    run.api.set_text (path, GODOT .. '// more\n')
    ok (d.dirty)
    ok (run.api.save (path))
    eq (wrote[path], GODOT .. '// more\n')
    ok (not d.dirty)
    local renamed, why = run.api.rename (path, '/home/me/game/sea.gdshader')
    eq ({ renamed, why }, { false, 'Rename it in the file tree.' })
  end
)
