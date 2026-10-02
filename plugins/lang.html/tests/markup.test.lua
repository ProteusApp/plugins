local markup = require ('lib.markup') --[[@as LangHtml.Markup]]

local function pos (line, character)
  return { line = line, character = character }
end

-- Script stripping ----------------------------------------------------------------------

test ('strip_scripts takes out every script element', function ()
  local html = '<p>a</p><script>alert(1)</script><p>b</p>'
    .. '<SCRIPT type="module">x()</SCRIPT ><p>c</p>'
  eq (markup.strip_scripts (html), '<p>a</p><p>b</p><p>c</p>')
end)

test ('strip_scripts drops a script that never closes', function ()
  eq (markup.strip_scripts ('<p>a</p><script>let x = 1'), '<p>a</p>')
end)

test ('strip_scripts leaves look-alike tags alone', function ()
  local html = '<scripted>x</scripted><noscript>y</noscript>'
  eq (markup.strip_scripts (html), html)
end)

test ('page keeps scripts when they may run', function ()
  local out = markup.page ('<p>a</p><script>go()</script>', true)
  ok (out:find ('<script>go()</script>', 1, true), 'the script stays')
  ok (not out:find ("script-src 'none'", 1, true), 'no policy that stops it')
end)

test ('page stops scripts when they may not run', function ()
  local out =
    markup.page ('<p onclick="go()">a</p><script>go()</script>', false)
  ok (not out:find ('<script>go()</script>', 1, true), 'the script is gone')
  ok (out:find ("script-src 'none'", 1, true), 'a policy stops the rest')
  ok (out:find ('<p onclick="go()">a</p>', 1, true), 'the text stays')
end)

test ('page goes after the doctype, so the page keeps its mode', function ()
  local out = markup.page ('<!DOCTYPE html>\n<p>a</p>', false)
  eq (out:sub (1, 15), '<!DOCTYPE html>')
  ok (out:find ('proteus.on', 1, true), 'the scroll keeper is there')
  ok (out:sub (-9) == '\n<p>a</p>')
end)

test ('is_page is true only for .html and .htm', function ()
  ok (markup.is_page ('C:/site/index.html'))
  ok (markup.is_page ('site/OLD.HTM'))
  ok (not markup.is_page ('src/App.vue'))
  ok (not markup.is_page ('notes.html.md'))
end)

-- Positions ------------------------------------------------------------------------------

test ('before splits the text at a position', function ()
  local before, line = markup.before ('one\ntwo three\nfour', pos (1, 3))
  eq (before, 'one\ntwo')
  eq (line, 'two')
end)

test ('before counts columns in UTF-16 units, as the editor does', function ()
  -- "é" is two bytes and one unit. The emoji is four bytes and two units.
  local _, line = markup.before ('é😀<b', pos (0, 4))
  eq (line, 'é😀<')
  eq (markup.units (line), 4)
end)

-- The skeleton ---------------------------------------------------------------------------

test ('skeleton completes ! and html:5 on a line of their own', function ()
  local item, from = markup.skeleton ('!')
  eq (item and item.label, '!')
  eq (from, 0)
  item = markup.skeleton ('html')
  eq (item and item.label, 'html:5')
  item = markup.skeleton ('html:5')
  eq (item and item.label, 'html:5')
  ok (item and item.insert:find ('<!doctype html>', 1, true) == 1)
end)

test ('skeleton indents every line like the first', function ()
  local item, from = markup.skeleton ('  !')
  eq (from, 2)
  ok (item and item.insert:find ('\n  <html lang="en">', 1, true))
  ok (item and item.insert:find ('\n  </html>$'))
end)

test ('skeleton offers nothing elsewhere', function ()
  eq (markup.skeleton (''), nil)
  eq (markup.skeleton ('<p>!'), nil)
  eq (markup.skeleton ('htm'), nil)
  eq (markup.skeleton ('html:6'), nil)
  eq (markup.skeleton ('a !'), nil)
end)

-- Closing tags ---------------------------------------------------------------------------

test ('open_element finds the innermost open element', function ()
  eq (markup.open_element ('<div><p>text'), 'p')
  eq (markup.open_element ('<div><p>text</p>'), 'div')
  eq (markup.open_element ('<div><p>a</p></div>'), nil)
end)

test (
  'open_element skips void elements and tags that close themselves',
  function ()
    eq (
      markup.open_element ('<ul><li>a<br><img src="x.png"><x-icon /></li>'),
      'ul'
    )
  end
)

test ('open_element reads past > inside quotes and comments', function ()
  eq (markup.open_element ('<a title="1 > 0"><!-- <b> -->'), 'a')
end)

test ('open_element treats script content as text', function ()
  eq (markup.open_element ('<body><script>if (a < b) {}</script>'), 'body')
  eq (markup.open_element ('<body><script>if (a < b) {'), 'script')
end)

test ('open_element keeps the spelling of the tag', function ()
  eq (markup.open_element ('<Section><DIV></div>'), 'Section')
end)

test ('closing offers the tag that closes the open element', function ()
  local text = '<ul>\n  <li>one\n  </'
  local before, line = markup.before (text, pos (2, 4))
  local item, from = markup.closing (before, line)
  eq (item and item.label, '</li>')
  eq (item and item.insert, '</li>')
  eq (from, 2)
end)

test ('closing follows part of a name', function ()
  local item = markup.closing ('<section></se', '<section></se')
  eq (item and item.label, '</section>')
  eq (markup.closing ('<section></di', '<section></di'), nil)
end)

test ('closing offers nothing without </ before the cursor', function ()
  eq (markup.closing ('<div>text', '<div>text'), nil)
  eq (markup.closing ('</', '</'), nil)
end)

-- Snippets -------------------------------------------------------------------------------

test ('plain_snippet takes out the snippet marks', function ()
  eq (markup.plain_snippet ('class="$1"'), 'class=""')
  eq (markup.plain_snippet ('$0</div>'), '</div>')
  eq (markup.plain_snippet ('color: ${1:red};'), 'color: red;')
  eq (markup.plain_snippet ('dir="${1|ltr,rtl|}"'), 'dir="ltr"')
  eq (markup.plain_snippet ('cost: \\$5${2}'), 'cost: $5')
end)
