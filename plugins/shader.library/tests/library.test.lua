-- The shader builder's left side: the Shaders list with its menu, and the Nodes list with its
-- search, against the real shader.core and a fake shader.docs.

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

local core = {
  nodes = core_require ('shader_nodes'),
  source = core_require ('shader_source'),
  file = core_require ('shader_file'),
}

---@class LibraryTest.El
---@field props table
---@field handlers table<string, fun(ev: table): any>
---@field shown string What `html` set last.

---@class LibraryTest.Run
---@field shaders LibraryTest.El The Shaders list.
---@field nodes LibraryTest.El The Nodes list.
---@field search LibraryTest.El
---@field menu fun(ev: table): Proteus.MenuItem[]?
---@field opened string[]
---@field added string[] Node types added to the canvas.
---@field notes string[]
---@field ran string[] Commands run.
---@field removed string[]
---@field picker_asked table[]
---@field emit fun(event: string, ...: any)
---@field flush fun() Runs the timers that are due.
---@field files string[]
---@field active? table
---@field els LibraryTest.El[] Every element the plugin made.

---@param path string
---@return string?
local function kind_of (path)
  if path:sub (-#core.file.EXTENSION) == core.file.EXTENSION then
    return 'graph'
  end
  return core.source.kind_of (path) and 'code' or nil
end

---Starts shader.library with these shader files. `builtin` ones ship as examples, and
---`changed` ones are examples the user changed.
---@param opts { files?: string[], builtin?: table<string, true>, changed?: table<string, true>, active?: table, rename_fails?: boolean }
---@return LibraryTest.Run
local function start (opts)
  local state = {
    opened = {},
    added = {},
    notes = {},
    ran = {},
    removed = {},
    picker_asked = {},
    files = opts.files or {},
    active = opts.active,
    els = {},
  }
  local run = state --[[@as LibraryTest.Run]]
  local lists = {} ---@type LibraryTest.El[]
  local handlers = {} ---@type table<string, function[]>
  local timers = {} ---@type function[]

  ---@param props? table
  ---@return LibraryTest.El
  local function el (props)
    local e = { props = props or {}, handlers = {}, shown = '' }
    function e:html (text)
      self.shown = text
    end
    function e:on (event, fn)
      self.handlers[event] = fn
    end
    if e.props.oninput then
      e.handlers.input = e.props.oninput
    end
    if e.props.class == 'sl-list' then
      lists[#lists + 1] = e
    end
    if e.props.class == 'sl-search' then
      run.search = e
    end
    run.els[#run.els + 1] = e
    return e
  end

  local ui = setmetatable ({ css = function () end }, {
    __index = function ()
      return el
    end,
  })
  local docs = {
    folder = 'shaders',
    kind_of = kind_of,
    files = function ()
      return run.files
    end,
    active = function ()
      return run.active
    end,
    open = function (path)
      run.opened[#run.opened + 1] = path
    end,
    rename = function (path, to)
      if opts.rename_fails then
        return false, 'a file is there'
      end
      run.opened[#run.opened + 1] = path .. ' -> ' .. to
      return true
    end,
    remove = function (path)
      run.removed[#run.removed + 1] = path
      return true
    end,
  }
  local services = {
    ui = ui,
    shader = core,
    ['shader.docs'] = docs,
    views = { add = function () end },
    commands = {
      run = function (id)
        run.ran[#run.ran + 1] = id
      end,
    },
    ['shader.canvas'] = {
      add = function (type)
        run.added[#run.added + 1] = type
      end,
    },
    menus = {
      attach = function (_, fn)
        run.menu = fn
      end,
    },
    picker = {
      input = function (spec)
        run.picker_asked[#run.picker_asked + 1] = spec
      end,
      confirm = function (spec)
        run.picker_asked[#run.picker_asked + 1] = spec
      end,
    },
    notify = {
      info = function (text)
        run.notes[#run.notes + 1] = text
      end,
      warn = function (text)
        run.notes[#run.notes + 1] = text
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
    util = {
      escape = function (s)
        return (
          tostring (s)
            :gsub ('&', '&amp;')
            :gsub ('<', '&lt;')
            :gsub ('"', '&quot;')
        )
      end,
      icon = function ()
        return ''
      end,
    },
    fs = {
      stat = function (path)
        local builtin = (opts.builtin or {})[path] == true
        return {
          builtin = builtin,
          user = not builtin or (opts.changed or {})[path] == true,
          project = false,
        }
      end,
    },
    timer = {
      after = function (_, fn)
        timers[#timers + 1] = fn
      end,
    },
    system = { clipboard = function () end },
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
    load (read ('plugins/shader.library/init.lua'), '@shader.library', 't')
  ) () --[[@as Proteus.Plugin]]
  plugin.activate (app --[[@as Proteus.App]])
  run.shaders, run.nodes = lists[1], lists[2]
  return run
end

---The text of each item in a list's HTML, in order.
---@param html string
---@return string[]
local function names (html)
  local out = {} ---@type string[]
  for name in html:gmatch ('<span class="sl%-name">(.-)</span>') do
    out[#out + 1] = name
  end
  return out
end

local GRAPH = 'shaders/waves' .. core.file.EXTENSION

test ('the Shaders list groups graphs and code, and marks examples', function ()
  local run = start ({
    files = { 'shaders/plasma.frag', GRAPH, 'shaders/grid.wgsl' },
    builtin = { [GRAPH] = true },
    active = { path = 'shaders/grid.wgsl', kind = 'code' },
  })
  local html = run.shaders.shown
  eq (names (html), { 'waves', 'plasma.frag', 'grid.wgsl' })
  ok (html:find ('<div class="sl-group">Graphs</div>', 1, true))
  ok (html:find ('<div class="sl-group">Code</div>', 1, true))
  ok (html:find ('example · graph', 1, true), 'an example says so')
  ok (html:find ('<span class="sl-tag">GLSL</span>', 1, true))
  ok (html:find ('<span class="sl-tag">WGSL</span>', 1, true))
  ok (
    html:find ('class="sl-item on" data-item="3"', 1, true),
    'the shader in front'
  )
end)

test ('with no shaders the list says how to start one', function ()
  local run = start ({})
  ok (run.shaders.shown:find ('No shaders yet', 1, true))
end)

test (
  'a click opens a shader, and a click between items does nothing',
  function ()
    local run = start ({ files = { 'shaders/a.frag', 'shaders/b.frag' } })
    run.shaders.handlers.click ({ item = '2' })
    run.shaders.handlers.click ({})
    run.shaders.handlers.click ({ item = '9' })
    eq (run.opened, { 'shaders/b.frag' })
  end
)

test ('a changed file in shaders/ redraws the list once', function ()
  local run = start ({ files = { 'shaders/a.frag' } })
  run.files = { 'shaders/a.frag', 'shaders/b.frag' }
  run.emit ('fs:changed', 'graphs/other.ndg')
  run.flush ()
  eq (
    names (run.shaders.shown),
    { 'a.frag' },
    'a file elsewhere changes nothing'
  )
  run.emit ('fs:changed', 'shaders/b.frag')
  run.emit ('shader:saved')
  run.flush ()
  eq (names (run.shaders.shown), { 'a.frag', 'b.frag' })
end)

test ('your own shader can be renamed and deleted from its menu', function ()
  local run = start ({ files = { 'shaders/a.frag' }, rename_fails = true })
  local items = assert (run.menu ({ item = '1' }))
  local labels = {} ---@type string[]
  for _, item in ipairs (items) do
    labels[#labels + 1] = item.label or '-'
  end
  eq (labels, { 'Open', 'Copy Path', 'Rename…', '-', 'Delete' })
  items[3].run ()
  run.picker_asked[1].on_submit ('shaders/b.frag')
  eq (run.notes, { 'Could not rename shaders/a.frag: a file is there' })
  items[5].run ()
  eq (run.picker_asked[2].yes, 'Delete')
  run.picker_asked[2].on_yes ()
  eq (run.removed, { 'shaders/a.frag' })
  eq (run.menu ({}), nil, 'no menu between items')
end)

test ('an example can only go back to the original, once changed', function ()
  local run = start ({
    files = { 'shaders/a.frag', 'shaders/b.frag' },
    builtin = { ['shaders/a.frag'] = true, ['shaders/b.frag'] = true },
    changed = { ['shaders/b.frag'] = true },
  })
  local untouched = assert (run.menu ({ item = '1' }))
  eq (#untouched, 4, 'no Rename')
  eq (
    { untouched[4].label, untouched[4].disabled },
    { 'Revert to the Example', true }
  )
  local changed = assert (run.menu ({ item = '2' }))
  eq (
    { changed[4].label, changed[4].disabled },
    { 'Revert to the Example', false }
  )
end)

test ('the buttons make new shaders through the commands', function ()
  local run = start ({})
  for _, e in ipairs (run.els) do
    if e.props.onclick then
      e.props.onclick ()
    end
  end
  eq (run.ran, { 'shader.new_graph', 'shader.new_glsl', 'shader.new_wgsl' })
end)

---The first node whose title, type or description holds `word`.
---@param word string
---@return Shader.NodeDef
local function node_with (word)
  for _, def in ipairs (core.nodes.list) do
    local hay = def.title .. ' ' .. def.type .. ' ' .. def.description
    if hay:lower ():find (word, 1, true) then
      return def
    end
  end
  error ('no node holds ' .. word)
end

test ('the Nodes list shows every node, and search narrows it', function ()
  local run = start ({})
  eq (#names (run.nodes.shown), #core.nodes.list)
  local def = node_with ('noise')
  run.search.handlers.input ({ value = 'NOISE' })
  local shown = names (run.nodes.shown)
  ok (#shown > 0 and #shown < #core.nodes.list, tostring (#shown))
  ok (run.nodes.shown:find ('>' .. def.title .. '<', 1, true), def.title)
  run.search.handlers.input ({ value = 'no node is called this' })
  ok (run.nodes.shown:find ('No node matches.', 1, true))
end)

test (
  'a click on a node adds it to the graph in front, and only to a graph',
  function ()
    local run = start ({ active = { path = 'shaders/a.frag', kind = 'code' } })
    run.nodes.handlers.click ({ item = '1' })
    eq (run.added, {})
    eq (run.notes, { 'Open a graph first. Nodes go into a graph.' })
    run.active = { path = GRAPH, kind = 'graph' }
    local def = node_with ('noise')
    run.search.handlers.input ({ value = def.title })
    -- The first node shown is the first, by group, that the search finds.
    local first ---@type string?
    for _, cat in ipairs (core.nodes.categories) do
      for _, d in ipairs (core.nodes.list) do
        local hay = (d.title .. ' ' .. d.type .. ' ' .. d.description):lower ()
        if
          not first
          and d.category == cat.id
          and hay:find (def.title:lower (), 1, true)
        then
          first = d.type
        end
      end
    end
    run.nodes.handlers.click ({ item = '1' })
    eq (run.added, { first })
    run.nodes.handlers.click ({ item = '999' })
    eq (run.added, { first })
  end
)
