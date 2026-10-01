local render = require ('minimap_render') --[[@as Minimap.RenderModule]]

local LUA = render.spec_for ('lua')
local JS = render.spec_for ('javascript')

test ('line colors keywords, constants, numbers and strings', function ()
  local html, state = render.line (LUA, 'local x = "hi" .. 42 or nil', '')
  eq (
    html,
    '<span class="k">local</span> x = <span class="s">"hi"</span> .. <span class="n">42</span> '
      .. '<span class="k">or</span> <span class="t">nil</span>'
  )
  eq (state, '')
end)

test ('line colors a comment to the end of the line', function ()
  local html = render.line (LUA, 'x = 1 -- one', '')
  eq (html, 'x = <span class="n">1</span> <span class="c">-- one</span>')
end)

test ('line escapes the characters HTML reads as markup', function ()
  local html = render.line (JS, 'if (a < b && c > d) {}', '')
  eq (html, '<span class="k">if</span> (a &lt; b &amp;&amp; c &gt; d) {}')
end)

test ('line skips a quote a backslash escapes', function ()
  local html = render.line (JS, [[s = 'it\'s' + t]], '')
  eq (html, [[s = <span class="s">'it\'s'</span> + t]])
end)

test (
  'a block comment carries over to the next lines until it closes',
  function ()
    local html, state = render.line (JS, 'a /* start', '')
    eq (html, 'a <span class="c">/* start</span>')
    eq (state, 'c1')
    html, state = render.line (JS, 'middle', state)
    eq (html, '<span class="c">middle</span>')
    eq (state, 'c1')
    html, state = render.line (JS, 'end */ return', state)
    eq (html, '<span class="c">end */</span> <span class="k">return</span>')
    eq (state, '')
  end
)

test ('a Lua block comment wins over a line comment', function ()
  local _, state = render.line (LUA, '--[[ notes', '')
  eq (state, 'c1')
  local _, level = render.line (LUA, '--[==[ notes', '')
  eq (level, 'c3')
end)

test ('a long string spans lines, and Lua reads no escapes in it', function ()
  local _, state = render.line (LUA, 'local s = [[ C:\\', '')
  eq (state, 's1')
  local html, after = render.line (LUA, ']] .. x', state)
  eq (html, '<span class="s">]]</span> .. x')
  eq (after, '')
end)

test ('a template string spans lines in JavaScript', function ()
  local _, state = render.line (JS, 'const t = `one', '')
  eq (state, 's1')
  local _, after = render.line (JS, 'two`;', state)
  eq (after, '')
end)

test ('a string left open stops at the end of its line', function ()
  local html, state = render.line (JS, 'x = "open', '')
  eq (html, 'x = <span class="s">"open</span>')
  eq (state, '')
end)

test ('SQL keywords match in any case', function ()
  local html = render.line (render.spec_for ('sql'), 'SELECT a FROM t', '')
  eq (html, '<span class="k">SELECT</span> a <span class="k">FROM</span> t')
end)

test (
  'a Markdown heading is one colored line, and apostrophes start no string',
  function ()
    local md = render.spec_for ('markdown')
    eq (
      render.line (md, '## Getting started', ''),
      '<span class="k">## Getting started</span>'
    )
    eq (render.line (md, "It's fine", ''), "It's fine")
  end
)

test ('an unknown language is drawn plain', function ()
  eq (
    render.line (render.spec_for ('nothing'), 'if "x" then', ''),
    'if "x" then'
  )
end)

test ('a line stops at the last column worth drawing', function ()
  local html =
    render.line (render.spec_for ('text'), ('a'):rep (render.MAX_COLS + 50), '')
  eq (#html, render.MAX_COLS)
end)

test ('a painter draws every line and counts them', function ()
  local painter = render.painter ()
  local picture = painter.paint ('local a = 1\r\n\n-- end\n', 'lua')
  eq (picture.lines, 4)
  eq (picture.drawn, 4)
  eq (
    picture.html,
    '<span class="k">local</span> a = <span class="n">1</span>\n\n<span class="c">-- end</span>\n'
  )
end)

test ('a painter carries a comment across lines it kept from before', function ()
  local painter = render.painter ()
  painter.paint ('x\ny', 'javascript')
  local picture = painter.paint ('/*\ny', 'javascript')
  eq (picture.html, '<span class="c">/*</span>\n<span class="c">y</span>')
end)

test ('a painter stops drawing after the last line it draws', function ()
  local painter = render.painter ()
  local text = ('x\n'):rep (render.MAX_LINES + 4)
  local picture = painter.paint (text, 'text')
  eq (picture.lines, render.MAX_LINES + 5)
  eq (picture.drawn, render.MAX_LINES)
end)

test (
  'line_at finds the line under a point and keeps inside the file',
  function ()
    eq (render.line_at (0, 3, 10), 1)
    eq (render.line_at (5.9, 3, 10), 2)
    eq (render.line_at (300, 3, 10), 10)
    eq (render.line_at (-4, 3, 10), 1)
    eq (render.line_at (10, 3, 0), 1)
  end
)
