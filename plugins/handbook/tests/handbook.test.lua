-- The Handbook's parts that touch nothing on screen: reading pages, links, coloring code,
-- the reference built from type files, search, and the library that sorts pages.

local highlight = require ('lib.highlight')
local library = require ('lib.library')
local page = require ('lib.page')
local reference = require ('lib.reference')
local render = require ('lib.render')
local search = require ('lib.search')

-- page -------------------------------------------------------------------------------------

test ('an anchor is the heading in lower case with dashes', function ()
  eq (page.slug ('Setting one'), 'setting-one')
  eq (page.slug ('`commands.register`'), 'commands.register')
  eq (page.slug ('app.use (name)'), 'app.use-name')
  eq (page.slug ('  What it_does!  '), 'what-it_does')
end)

test ('front matter is split from the page', function ()
  local front, body =
    page.split_front ('---\ntitle: Alarms\norder: 20\n---\n# Alarms\n\nText.')
  eq (front, { title = 'Alarms', order = '20' })
  eq (body, '# Alarms\n\nText.')
  local none, same = page.split_front ('# Plain\n')
  eq (none, {})
  eq (same, '# Plain\n')
end)

test ('a page splits into text, headings and code', function ()
  local doc = page.parse (table.concat ({
    '# Clock',
    '',
    'Shows the time.',
    '',
    '```lua',
    '-- # not a heading',
    "local x = 'y'",
    '```',
    '',
    '## Setting one',
    'More.',
    '## Setting one',
  }, '\n'))
  eq (doc.title, 'Clock')
  eq (#doc.blocks, 6)
  eq (
    doc.blocks[1],
    { kind = 'heading', text = 'Clock', level = 1, anchor = 'clock' }
  )
  eq (doc.blocks[2].kind, 'text')
  eq (
    doc.blocks[3],
    { kind = 'code', text = "-- # not a heading\nlocal x = 'y'", lang = 'lua' }
  )
  eq (doc.blocks[4].anchor, 'setting-one')
  eq (doc.blocks[6].anchor, 'setting-one-2')
  eq (#doc.headings, 3)
end)

test ('the front matter title wins over the first heading', function ()
  local doc = page.parse ('---\ntitle: Short\n---\n# A Longer Title\n')
  eq (doc.title, 'Short')
end)

test ('fences of four backticks hold three', function ()
  local doc = page.parse ('````markdown\n```lua\nx()\n```\n````\n')
  eq (#doc.blocks, 1)
  eq (doc.blocks[1].text, '```lua\nx()\n```')
  eq (doc.blocks[1].lang, 'markdown')
end)

test ('an indented fence in a list keeps its code flush', function ()
  local doc = page.parse ('1. Step\n\n   ```lua\n   local a = 1\n   ```\n')
  eq (doc.blocks[2], { kind = 'code', text = 'local a = 1', lang = 'lua' })
end)

test ('links resolve to pages, headings and web addresses', function ()
  eq (
    page.resolve ('alarms.md', 'my.clock', 'clock'),
    { source = 'my.clock', name = 'alarms' }
  )
  eq (
    page.resolve ('alarms.md#setting-one', 'my.clock', 'clock'),
    { source = 'my.clock', name = 'alarms', anchor = 'setting-one' }
  )
  eq (
    page.resolve ('#below', 'my.clock', 'clock'),
    { source = 'my.clock', name = 'clock', anchor = 'below' }
  )
  eq (
    page.resolve ('core.commands/commands.md', 'my.clock', 'clock'),
    { source = 'core.commands', name = 'commands' }
  )
  eq (
    page.resolve ('types/services.md#proteus.commands', 'proteus', 'welcome'),
    { source = 'types', name = 'services', anchor = 'proteus.commands' }
  )
  eq (
    page.resolve ('daw.core/types/daw.md', 'x', 'y'),
    { source = 'daw.core', name = 'types/daw' }
  )
  eq (
    page.resolve ('https://lucide.dev/icons', 'x', 'y'),
    { url = 'https://lucide.dev/icons' }
  )
end)

test ('link targets change outside code spans only', function ()
  local seen = {} ---@type string[]
  local out = page.map_links (
    '[a](one.md) `[b](two.md)` [c](<three.md>) ``x`` [d](four.md "Four")',
    function (t)
      seen[#seen + 1] = t
      return 'X'
    end
  )
  eq (seen, { 'one.md', 'three.md', 'four.md' })
  eq (out, '[a](X) `[b](two.md)` [c](X) ``x`` [d](X "Four")')
end)

test ('a bracket that starts no link is kept as it is', function ()
  eq (
    page.map_links ('a [b] c] d `x` e', function ()
      return 'X'
    end),
    'a [b] c] d `x` e'
  )
end)

-- highlight ---------------------------------------------------------------------------------

test ('Lua is colored and escaped', function ()
  local html =
    highlight.lua ("local ui = app.use ('ui') -- <b>\nreturn x.y (1, true)")
  ok (html:find ('<span class="hb%-k">local</span>'), html)
  ok (html:find ('<span class="hb%-f">use</span>'), html)
  ok (html:find ('<span class="hb%-s">&#39;ui&#39;</span>'), html)
  ok (html:find ('<span class="hb%-c">%-%- &lt;b&gt;</span>'), html)
  ok (html:find ('<span class="hb%-f">y</span>'), html)
  ok (html:find ('<span class="hb%-n">1</span>'), html)
  ok (html:find ('<span class="hb%-o">true</span>'), html)
  ok (not html:find ('<b>', 1, true), 'the comment was not escaped')
end)

test ('long strings and comments are one piece each', function ()
  local html = highlight.lua ('--[[ a\nb ]] local s = [==[\n]] ]==]')
  ok (html:find ('<span class="hb%-c">%-%-%[%[ a\nb %]%]</span>'), html)
  ok (html:find ('<span class="hb%-s">%[==%[\n%]%] %]==%]</span>'), html)
end)

test ('a field after a dot is a property, and a call is a function', function ()
  local html = highlight.lua ('app.store.get (key)')
  ok (html:find ('<span class="hb%-p">store</span>'), html)
  ok (html:find ('<span class="hb%-f">get</span>'), html)
end)

test ('other languages get strings, numbers and comments', function ()
  eq (
    highlight.html ('{ "a": 1 }', 'json'),
    '{ <span class="hb-s">&quot;a&quot;</span>: <span class="hb-n">1</span> }'
  )
  eq (
    highlight.html ('a = 1 # note', 'toml'),
    'a = <span class="hb-n">1</span> <span class="hb-c"># note</span>'
  )
  eq (highlight.html ('<b>', 'text'), '&lt;b&gt;')
end)

-- reference ---------------------------------------------------------------------------------

local TYPES = table.concat ({
  '---@meta',
  '',
  '-- Types for the clock.',
  '',
  '---------------------------------------------------------------------------------------------',
  '-- clock (my.clock)',
  '---------------------------------------------------------------------------------------------',
  '',
  '---A time of day.',
  '---@class Clock.Time',
  '---@field hour integer From 0 to 23.',
  '---@field label? string Such as `9:30`.',
  '---@field on_ring fun(t: Clock.Time): boolean Runs when it rings.',
  '',
  '---How a time shows.',
  '---@alias Clock.Style',
  "---| 'short' # Such as 9:30.",
  "---| 'long'",
  '',
  '---@class Clock.Service',
  'local Clock = {}',
  '',
  '---Sets an alarm.',
  '---@param at Clock.Time When it rings.',
  '---@param style? Clock.Style',
  '---@return boolean ok',
  '---@return string? err Why it could not.',
  '---@overload fun(at: string): boolean',
  'function Clock.alarm (at, style) end',
  '',
  '---@return Clock.Time',
  'function Clock:now () end',
}, '\n')

test ('a type reads up to the space after it', function ()
  eq ({ reference.read_type ('string text', 1) }, { 'string', 7 })
  eq ({ reference.read_type ("'a'|'b' text", 1) }, { "'a'|'b'", 8 })
  eq (
    { reference.read_type ('fun(x: integer): boolean text', 1) },
    { 'fun(x: integer): boolean', 25 }
  )
  eq (
    { reference.read_type ('table<string, any> text', 1) },
    { 'table<string, any>', 19 }
  )
  eq (
    { reference.read_type ('{ x: number, y: number }', 1) },
    { '{ x: number, y: number }', 25 }
  )
end)

test ('a type file reads into classes, aliases and functions', function ()
  local items, intro = reference.read (TYPES)
  eq (intro, 'Types for the clock.')
  local kinds, names = {}, {} ---@type string[], string[]
  for _, item in ipairs (items) do
    kinds[#kinds + 1] = item.kind
    names[#names + 1] = item.name
  end
  eq (kinds, { 'group', 'class', 'alias', 'class', 'function', 'function' })
  eq (names, {
    'clock (my.clock)',
    'Clock.Time',
    'Clock.Style',
    'Clock.Service',
    'Clock.Service.alarm',
    'Clock.Service.now',
  })
  local time, style, alarm, now = items[2], items[3], items[5], items[6]
  eq (time.text, { 'A time of day.' })
  eq (
    time.fields[1],
    { name = 'hour', type = 'integer', text = 'From 0 to 23.' }
  )
  eq (time.fields[3], {
    name = 'on_ring',
    type = 'fun(t: Clock.Time): boolean',
    text = 'Runs when it rings.',
  })
  eq (style.fields, {
    { name = '', type = "'short'", text = 'Such as 9:30.' },
    { name = '', type = "'long'", text = '' },
  })
  eq (alarm.call, 'Clock.alarm (at, style)')
  eq (alarm.text, { 'Sets an alarm.' })
  eq (
    alarm.fields[1],
    { name = 'at', type = 'Clock.Time', text = 'When it rings.' }
  )
  eq (alarm.returns, {
    { name = 'ok', type = 'boolean', text = '' },
    { name = 'err', type = 'string?', text = 'Why it could not.' },
  })
  eq (alarm.overloads, { 'fun(at: string): boolean' })
  eq (now.call, 'clock:now ()')
end)

test ('the reference page has an anchor for every name', function ()
  local md, names = reference.build (TYPES, {
    title = 'Clock types',
    source = 'types/clock.lua',
    link = function (name)
      return name == 'Clock.Time' and 'types/clock.md#clock.time' or nil
    end,
  })
  eq (names, { 'Clock.Time', 'Clock.Style', 'Clock.Service' })
  local anchors = {} ---@type table<string, true>
  for _, h in ipairs (page.parse (md).headings) do
    anchors[h.anchor] = true
  end
  for _, a in ipairs ({
    'clock.time',
    'clock.style',
    'clock.service',
    'clock.service.alarm',
    'clock.service.now',
  }) do
    ok (anchors[a], 'no anchor ' .. a)
  end
  ok (
    md:find (
      '- **`at`** [`Clock.Time`](types/clock.md#clock.time) — When it rings.',
      1,
      true
    ),
    md
  )
  ok (md:find ('`Clock.alarm (at, style)`', 1, true), md)
  eq (reference.names (TYPES), { 'Clock.Time', 'Clock.Style', 'Clock.Service' })
end)

-- search ------------------------------------------------------------------------------------

---@param id string
---@param title string
---@param text string
---@return Handbook.IndexPage
local function indexed (id, title, text)
  return { id = id, title = title, section = 'Test', doc = page.parse (text) }
end

local INDEX = search.index ({
  indexed (
    'a/commands',
    'Commands',
    '# Commands\n\nActions for menus.\n\n## register\n\nAdds a command with a key.'
  ),
  indexed (
    'a/keys',
    'Keys',
    '# Keys\n\nBinds a key to a command such as Commands.'
  ),
  indexed (
    'a/settings',
    'Settings',
    '# Settings\n\n## Defining one\n\nA setting has a default.'
  ),
})

test ('a title match comes before a mention in the text', function ()
  local hits = search.find (INDEX, 'commands')
  eq (hits[1].id, 'a/commands')
  eq (hits[1].anchor, nil)
  eq (hits[2].id, 'a/keys')
  ok (hits[2].snippet and hits[2].snippet:find ('Commands'), 'no snippet')
end)

test ('headings are found, with the page as context', function ()
  local hits = search.find (INDEX, 'regist')
  eq (hits[1].id, 'a/commands')
  eq (hits[1].anchor, 'register')
  eq (hits[1].context, 'Commands')
end)

test ('every word must appear', function ()
  eq (#search.find (INDEX, 'setting default'), 1)
  eq (#search.find (INDEX, 'setting nowhere'), 0)
  eq (search.find (INDEX, '   '), {})
end)

-- library -----------------------------------------------------------------------------------

test ('pages sort into sections by their lowest order', function ()
  local lib = library.new ()
  lib.set ('p/b', {
    source = 'p',
    name = 'b',
    markdown = '---\nsection: Later\norder: 50\n---\n# B',
    origin = 'file',
  })
  lib.set ('p/a', {
    source = 'p',
    name = 'a',
    markdown = '---\nsection: First\norder: 2\n---\n# A',
    origin = 'file',
  })
  lib.set ('p/c', {
    source = 'p',
    name = 'c',
    markdown = '---\nsection: Later\norder: 1\n---\n# C',
    origin = 'file',
  })
  lib.set ('q/d', {
    source = 'q',
    name = 'd',
    markdown = '# D',
    origin = 'code',
    plugin_name = 'Q plugin',
  })
  local out = {} ---@type string[]
  for _, s in ipairs (lib.sections ()) do
    local ids = {} ---@type string[]
    for _, p in ipairs (s.pages) do
      ids[#ids + 1] = p.id
    end
    out[#out + 1] = s.name .. ': ' .. table.concat (ids, ' ')
  end
  eq (out, { 'Later: p/c p/b', 'First: p/a', 'Q plugin: q/d' })
  local before, after = lib.neighbors ('p/b')
  eq (before and before.id, 'p/c')
  eq (after and after.id, 'p/a')
end)

test ('a page made by a function is built when asked for, once', function ()
  local lib = library.new ()
  local built = 0
  lib.set ('types/x', {
    source = 'types',
    name = 'x',
    origin = 'types',
    markdown = function ()
      built = built + 1
      return '# X types\n\n## X.thing'
    end,
  })
  eq (built, 0)
  eq (lib.get ('types/x').title, 'X types')
  lib.get ('types/x')
  eq (built, 1)
  eq (lib.find ('x.thing')[1].anchor, 'x.thing')
end)

test (
  'a change to a page changes the version, and the same text does not',
  function ()
    local lib = library.new ()
    local src = { source = 'p', name = 'a', markdown = '# A', origin = 'file' } ---@type Handbook.Source
    lib.set ('p/a', src)
    local v = lib.version ()
    lib.set (
      'p/a',
      { source = 'p', name = 'a', markdown = '# A', origin = 'file' }
    )
    eq (lib.version (), v)
    lib.set (
      'p/a',
      { source = 'p', name = 'a', markdown = '# A2', origin = 'file' }
    )
    ok (lib.version () > v)
    eq (lib.get ('p/a').title, 'A2')
    lib.remove ('p/a')
    eq (lib.get ('p/a'), nil)
  end
)

-- render ------------------------------------------------------------------------------------

test ('links between pages point inside the Handbook', function ()
  eq (
    render.links (
      '[a](alarms.md#x) [b](https://lucide.dev) [c](#top)',
      'my.clock',
      'clock'
    ),
    '[a]('
      .. render.INTERNAL
      .. 'my.clock/alarms#x) [b](https://lucide.dev) [c]('
      .. render.INTERNAL
      .. 'my.clock/clock#top)'
  )
end)

test ('a click says what it asks for', function ()
  eq (render.target ('copy:3'), { kind = 'copy', n = 3 })
  eq (render.target ('page:core.commands/commands#register'), {
    kind = 'page',
    id = 'core.commands/commands',
    anchor = 'register',
  })
  eq (render.target ('page:'), { kind = 'page', id = '' })
  eq (
    render.target ('link:' .. render.INTERNAL .. 'proteus/welcome'),
    { kind = 'page', id = 'proteus/welcome' }
  )
  eq (
    render.target ('link:https://lucide.dev'),
    { kind = 'url', url = 'https://lucide.dev' }
  )
  eq (render.target (nil), nil)
end)

test (
  'the safe renderer’s links between pages lose their address on hover',
  function ()
    local html = '<a data-item="link:'
      .. render.INTERNAL
      .. 'a/b" title="'
      .. render.INTERNAL
      .. 'a/b" class="ui-link">x</a>'
    eq (
      render.tidy (html),
      '<a data-page="1" data-item="link:'
        .. render.INTERNAL
        .. 'a/b" class="ui-link">x</a>'
    )
  end
)

test ('parts start at each heading, and code blocks are numbered', function ()
  local doc = page.parse (
    'Intro.\n\n## One\n\n```lua\nx ()\n```\n\n## Two\n\n```\nplain\n```\n'
  )
  local parts, codes = render.parts (doc, 'p', 'a', function (text)
    return '<p>' .. text .. '</p>'
  end)
  eq (#parts, 3)
  eq (parts[1].heading, nil)
  eq (parts[2].heading.anchor, 'one')
  ok (parts[2].html:find ('data%-item="copy:1"'), parts[2].html)
  ok (parts[3].html:find ('data%-item="copy:2"'), parts[3].html)
  eq (codes, { 'x ()', 'plain' })
end)

-- the plugin's own pages --------------------------------------------------------------------

test ('the Handbook’s own pages have titles and Lua that parses', function ()
  for _, name in ipairs ({ 'using', 'writing-pages' }) do
    local doc =
      page.parse (read ('plugins/handbook/handbook/' .. name .. '.md'))
    ok (doc.title, name .. ' has no title')
    ok (doc.front.section, name .. ' has no section')
    for _, block in ipairs (doc.blocks) do
      if block.kind == 'code' and block.lang == 'lua' then
        local _, err = load (block.text, '=' .. name, 't', {})
        ok (not err, err)
      end
    end
  end
end)
