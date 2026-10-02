local links = require ('lib.links')

local H = links.HOST

test (
  'classify tells headings, web pages, files and other schemes apart',
  function ()
    eq (links.classify ('#setup'), { kind = 'anchor', anchor = 'setup' })
    eq (
      links.classify ('https://example.com/a'),
      { kind = 'web', url = 'https://example.com/a' }
    )
    eq (
      links.classify ('mailto:me@example.com'),
      { kind = 'web', url = 'mailto:me@example.com' }
    )
    eq (
      links.classify ('//example.com'),
      { kind = 'web', url = 'https://example.com' }
    )
    eq (links.classify ('ftp://x'), { kind = 'other', url = 'ftp://x' })
    eq (
      links.classify ('docs/My%20Notes.md#part-two'),
      { kind = 'file', path = 'docs/My Notes.md', anchor = 'part-two' }
    )
    eq (
      links.classify ('C:/notes/a.md'),
      { kind = 'file', path = 'C:/notes/a.md' }
    )
    eq (links.classify ('?x=1#top'), { kind = 'anchor', anchor = 'top' })
    eq (links.classify (''), nil)
  end
)

test ('resolve follows a relative path from the file the link is in', function ()
  eq (links.resolve ('docs/guide/a.md', '../b.md'), 'docs/b.md')
  eq (links.resolve ('docs/a.md', './img/../c.md'), 'docs/c.md')
  eq (links.resolve ('README.md', 'docs/x.md'), 'docs/x.md')
  eq (
    links.resolve ('C:\\code\\app\\README.md', 'src\\main.md'),
    'C:/code/app/src/main.md'
  )
  eq (links.resolve ('/home/me/app/a.md', '../../b.md'), '/home/b.md')
  eq (links.resolve ('/a.md', '../../b.md'), '/b.md')
end)

test ('resolve gives nil above the top of the workspace', function ()
  eq (links.resolve ('README.md', '../outside.md'), nil)
end)

test ('a path from / starts at the root', function ()
  eq (links.resolve ('docs/a.md', '/b.md', ''), 'b.md')
  eq (links.resolve ('C:/app/docs/a.md', '/b.md', 'C:/app'), 'C:/app/b.md')
  eq (links.resolve ('/srv/a.md', '/b.md', nil), '/b.md')
end)

test ('task_line marks the boxes of task list items', function ()
  eq (links.task_line ('- [ ] milk'), '- ' .. links.TASK_OPEN .. ' milk')
  eq (links.task_line ('  * [x] eggs'), '  * ' .. links.TASK_DONE .. ' eggs')
  eq (links.task_line ('1. [X] bread'), '1. ' .. links.TASK_DONE .. ' bread')
  eq (links.task_line ('> - [ ] quoted'), '> - ' .. links.TASK_OPEN .. ' quoted')
  eq (links.task_line ('[ ] not a list'), '[ ] not a list')
  eq (links.task_line ('- [link](x)'), '- [link](x)')
end)

test ('rewrite points links and images at numbered addresses', function ()
  local text, targets = links.rewrite (
    'See [a](docs/a.md "A") and ![pic](img/p.png) and [w](https://x.io/(y)).'
  )
  eq (
    text,
    'See [a](' .. H .. '1 "A") and ![pic](' .. H .. '2) and [w](' .. H .. '3).'
  )
  eq (targets, { 'docs/a.md', 'img/p.png', 'https://x.io/(y)' })
end)

test ('rewrite reads angle brackets and leaves code spans alone', function ()
  local text, targets = links.rewrite ('[x](<my file.md>) `[y](z.md)` \\[n](m)')
  eq (text, '[x](' .. H .. '1) `[y](z.md)` \\[n](' .. H .. '2)')
  eq (targets, { 'my file.md', 'm' })
end)

test ('rewrite changes reference definitions', function ()
  local text, targets =
    links.rewrite ('[home]\n\n[home]: ./README.md "Home"\n[b]: <a b.md>')
  eq (text, '[home]\n\n[home]: ' .. H .. '1 "Home"\n[b]: ' .. H .. '2')
  eq (targets, { './README.md', 'a b.md' })
end)

test ('finish gives each link its real address for the click', function ()
  local html = links.finish (
    '<p><a data-item="link:'
      .. H
      .. '1" title="'
      .. H
      .. '1" class="ui-link">a</a></p>',
    { 'docs/a&b.md#x' }
  )
  eq (
    html,
    '<p><a data-item="go:docs/a&amp;b.md#x" title="docs/a&amp;b.md#x" class="ui-link">a</a></p>'
  )
end)

test ('finish turns images into placeholders with their text', function ()
  local html = links.finish (
    '<p><img src="' .. H .. '1" alt="A cat"><img alt=""></p>',
    { 'img/cat.png' }
  )
  eq (
    html,
    '<p><span class="md-image" title="img/cat.png">A cat</span>'
      .. '<span class="md-image" title="">image</span></p>'
  )
end)

test ('finish shows a picture held in the file itself', function ()
  local data = 'data:image/png;base64,iVBORw0KGgo='
  local html = links.finish ('<img src="' .. H .. '1" alt="dot">', { data })
  eq (html, '<img class="md-img" src="' .. data .. '" alt="dot">')
end)

test ('finish draws task boxes, and code keeps its text', function ()
  local html = links.finish (
    '<li>'
      .. links.TASK_DONE
      .. ' done</li><pre><code>[a]('
      .. H
      .. '1) '
      .. links.TASK_OPEN
      .. '</code></pre>',
    { 'x<y.md' }
  )
  eq (
    html,
    '<li class="md-task"><span class="md-check done"></span> done</li>'
      .. '<pre><code>[a](x&lt;y.md) [ ]</code></pre>'
  )
end)
