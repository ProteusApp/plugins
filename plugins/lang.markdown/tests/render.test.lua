local links = require ('lib.links')
local render = require ('lib.render')

-- A stand-in for the app's safe renderer: it wraps the text and counts its calls.
local calls = 0
---@param text string
---@return string
local function markdown (text)
  calls = calls + 1
  return '<div>' .. text .. '</div>'
end

test ('page renders each part, with its line and anchor', function ()
  calls = 0
  local page = render.page ('Intro\n# One\nText\n## Two\n', markdown)
  eq (page.lines, 5)
  eq (#page.parts, 3)
  eq (page.parts[2].line, 2)
  eq (page.parts[2].anchor, 'one')
  eq (page.parts[3].html, '<div>## Two\n</div>')
  eq (calls, 3)
end)

test ('page renders again only the parts that changed', function ()
  calls = 0
  local _, cache = render.page ('# One\na\n# Two\nb', markdown)
  eq (calls, 2)
  local page = render.page ('# One\na\n# Two\nb changed', markdown, cache)
  eq (calls, 3)
  eq (page.parts[2].html, '<div># Two\nb changed</div>')
end)

test ('every part gets the reference definitions', function ()
  local page = render.page ('# A\n[x][r]\n# B\n\n[r]: b.md', markdown)
  eq (page.parts[1].html, '<div># A\n[x][r]\n\n[r]: b.md</div>')
  eq (page.parts[2].html, '<div># B\n\n[r]: b.md\n\n[r]: b.md</div>')
end)

test ('the renderer gets the stand-in addresses', function ()
  local seen = nil ---@type string?
  render.page ('[a](b.md)', function (text)
    seen = text
    return ''
  end)
  eq (seen, '[a](' .. links.HOST .. '1)')
end)

test ('page marks task boxes outside code only', function ()
  local page = render.page ('- [ ] todo\n```\n- [ ] code\n```', markdown)
  eq (
    page.parts[1].html,
    '<div>- <span class="md-check"></span> todo\n```\n- [ ] code\n```</div>'
  )
end)
