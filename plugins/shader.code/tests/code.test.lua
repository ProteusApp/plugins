-- Shaders as code: the GLSL and WGSL languages, the editor a code shader opens in, the
-- compiler's problems on its lines, and Open This Graph as a Code Shader, against a fake UI
-- library and a fake shader.docs.

---@class CodeTest.El
---@field kind string
---@field props table
---@field calls any[][] Each method called on it, with its arguments.
---@field typed string What the editor holds, for `get_text`.

---@class CodeTest.Run
---@field languages Proteus.LanguageSpec[]
---@field opener fun(doc: table): CodeTest.El
---@field els CodeTest.El[]
---@field commands table<string, Proteus.CommandSpec>
---@field texts { [1]: string, [2]: string }[] Each docs.set_text.
---@field made { [1]: string, [2]: string, [3]: string }[] Each docs.new_code.
---@field emit fun(event: string, ...: any)
---@field flush fun()
---@field active? table
---@field open table<string, table> Open shaders by path, for docs.get.

---@param kind string
---@param props? table
---@return CodeTest.El
local function element (kind, props)
  local el = { kind = kind, props = props or {}, calls = {}, typed = '' }
  return setmetatable (el, {
    __index = function (_, method)
      return function (self, first, ...)
        self.calls[#self.calls + 1] = { method, first, ... }
        if method == 'alive' then
          return true
        elseif method == 'widget' and first == 'get_text' then
          return self.typed
        end
        return nil
      end
    end,
  })
end

---@param el CodeTest.El
---@param method string
---@param first? any
---@return any[][] Each matching call, as `{ method, arguments... }`.
local function calls_of (el, method, first)
  local out = {} ---@type any[]
  for _, c in ipairs (el.calls) do
    if c[1] == method and (first == nil or c[2] == first) then
      out[#out + 1] = c
    end
  end
  return out
end

---@return CodeTest.Run
local function start ()
  local state = {
    languages = {},
    els = {},
    commands = {},
    texts = {},
    made = {},
    open = {},
  }
  local run = state --[[@as CodeTest.Run]]
  local handlers = {} ---@type table<string, function[]>
  local timers = {} ---@type function[]
  ---@param kind string
  ---@return fun(props?: table): CodeTest.El
  local function maker (kind)
    return function (props)
      local el = element (kind, type (props) == 'table' and props or {})
      run.els[#run.els + 1] = el
      return el
    end
  end
  local ui = setmetatable ({
    css = function () end,
    language = function (spec)
      run.languages[#run.languages + 1] = spec
    end,
    widget = function (name, props)
      return maker ('widget:' .. name) (props)
    end,
  }, {
    __index = function (_, name)
      return maker (name)
    end,
  })
  local docs = {
    register_opener = function (kind, fn)
      assert (kind == 'code', kind)
      run.opener = fn
    end,
    set_text = function (path, text)
      run.texts[#run.texts + 1] = { path, text }
    end,
    program = function (path)
      if path:match ('%.wgsl$') then
        return { uniforms = {}, offset = 0 }
      end
      return { uniforms = { 'u_a', 'u_b' }, offset = 3 }
    end,
    get = function (path)
      return run.open[path]
    end,
    active = function ()
      return run.active
    end,
    compiled = function ()
      return {
        glsl = { source = 'GLSL SOURCE' },
        wgsl = { source = 'WGSL SOURCE' },
      }
    end,
    new_code = function (lang, stem, source)
      run.made[#run.made + 1] = { lang, stem, source }
    end,
  }
  local services = {
    ui = ui,
    ['shader.docs'] = docs,
    shader = {
      export = {
        godot = function ()
          return 'GODOT SOURCE'
        end,
      },
    },
    commands = {
      register = function (spec)
        run.commands[spec.id] = spec
      end,
      run = function () end,
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
    load (read ('plugins/shader.code/init.lua'), '@shader.code', 't')
  ) () --[[@as Proteus.Plugin]]
  plugin.activate (app --[[@as Proteus.App]])
  return run
end

---Opens a code shader and returns its editor and the note above it.
---@param run CodeTest.Run
---@param doc table
---@return CodeTest.El editor
---@return CodeTest.El note
local function open (run, doc)
  local before = #run.els
  run.open[doc.path] = doc
  run.opener (doc)
  local editor, note ---@type CodeTest.El?, CodeTest.El?
  for i = before + 1, #run.els do
    local el = run.els[i]
    if el.kind == 'widget:code' then
      editor = el
    elseif el.kind == 'span' and el.props.class == 'sc-note' then
      note = el
    end
  end
  return assert (editor, 'no editor'), assert (note, 'no note')
end

local FRAG = {
  path = 'shaders/a.frag',
  kind = 'code',
  language = 'glsl',
  text = 'void main(){}',
}
local WGSL = {
  path = 'shaders/b.wgsl',
  kind = 'code',
  language = 'wgsl',
  text = 'fn f(){}',
}

test ('GLSL and WGSL come to the code editor as languages', function ()
  local run = start ()
  eq (#run.languages, 2)
  eq (
    { run.languages[1].name, run.languages[1].extensions },
    { 'glsl', { 'glsl', 'frag', 'vert' } }
  )
  eq (
    { run.languages[2].name, run.languages[2].extensions },
    { 'wgsl', { 'wgsl' } }
  )
  ok (tostring (run.languages[1].keywords):find ('uniform', 1, true) ~= nil)
  ok (tostring (run.languages[2].keywords):find ('fn', 1, true) ~= nil)
end)

test ('a code shader opens in an editor in its language', function ()
  local run = start ()
  local editor = open (run, FRAG)
  eq ({ editor.props.text, editor.props.language }, { 'void main(){}', 'glsl' })
  ok (#editor.props.completions > 0)
  local wgsl = open (run, WGSL)
  eq (wgsl.props.language, 'wgsl')
  ok (
    editor.props.completions ~= wgsl.props.completions,
    'each language has its own words'
  )
end)

test ('typing reaches shader.docs once the editor is quiet', function ()
  local run = start ()
  local editor = open (run, FRAG)
  editor.typed = 'void main(){ x; }'
  editor.props.on_change ()
  editor.props.on_change ()
  eq (run.texts, {}, 'it waits')
  run.flush ()
  eq (run.texts, { { 'shaders/a.frag', 'void main(){ x; }' } })
end)

test ("the note says the shader's language and what the app adds", function ()
  local run = start ()
  local _, note = open (run, FRAG)
  eq (
    calls_of (note, 'text')[1][2],
    'GLSL ES 3.00 · WebGL 2 · the version, uniforms and output it leaves out are added · 2 controls'
  )
  local _, wgsl_note = open (run, WGSL)
  eq (calls_of (wgsl_note, 'text')[1][2], 'WGSL · WebGPU')
end)

test ('the compiler’s problems show on their lines', function ()
  local run = start ()
  local editor = open (run, FRAG)
  run.emit ('shader:problems', 'shaders/a.frag', {
    { line = 3, column = 5, message = 'undeclared x', severity = 'error' },
    { line = 1, message = 'unused', severity = 'warning', stage = 'vertex' },
    { message = 'no line' },
  })
  local set = calls_of (editor, 'widget', 'set_diagnostics')
  eq (#set, 1)
  eq (set[1][3], {
    {
      line = 2,
      character = 4,
      end_line = 2,
      end_character = 999,
      severity = 'error',
      message = 'undeclared x',
      source = 'compiler',
    },
    {
      line = 0,
      character = 0,
      end_line = 0,
      end_character = 999,
      severity = 'warning',
      message = 'unused',
      source = 'vertex shader',
    },
  })
end)

test (
  'a shader reloaded from disk replaces the editor text, and a closed one is let go',
  function ()
    local run = start ()
    local editor = open (run, FRAG)
    run.open[FRAG.path] = { path = FRAG.path, kind = 'code', text = 'new' }
    run.emit ('shader:reloaded', FRAG.path)
    eq (#calls_of (editor, 'widget', 'replace_text'), 1)
    run.emit ('shader:closed', FRAG.path)
    run.emit ('shader:problems', FRAG.path, { { line = 1, message = 'x' } })
    eq (
      #calls_of (editor, 'widget', 'set_diagnostics'),
      0,
      'no editor to show them in'
    )
  end
)

test ('a graph can be opened as a code shader, in GLSL by default', function ()
  local run = start ()
  local spec = assert (run.commands['shader.to_code'], 'no shader.to_code')
  run.active = { path = 'shaders/g.shader.json', kind = 'code', title = 'g' }
  eq (spec.when (), false, 'only a graph')
  spec.run ()
  eq (run.made, {})
  run.active =
    { path = 'shaders/g.shader.json', kind = 'graph', title = 'Waves' }
  eq (spec.when (), true)
  spec.run ()
  eq (run.made, { { 'glsl', 'Waves', 'GLSL SOURCE' } })
end)
