-- Tests for sheet_model_style: shared style tables, layers, and the patches that change some
-- fields of a style.

local model = require ('sheet_model') --[[@as Sheet.ModelModule]]
local style = require ('sheet_model_style') --[[@as Sheet.ModelStyleModule]]

test ('sheet_model offers the style functions as its own', function ()
  ok (model.intern == style.intern)
  ok (model.layer == style.layer)
  ok (model.cell_patch == style.cell_patch)
  ok (model.EMPTY == style.EMPTY)
  ok (model.RESET == style.RESET)
  ok (model.STYLE_FIELDS == style.STYLE_FIELDS)
end)

test (
  'equal styles are one table, and fields of the wrong kind drop out',
  function ()
    local a = style.intern ({ bold = true, size = 14 })
    local b = style.intern ({ size = 14.0, bold = true })
    ok (a ~= nil and a == b)
    eq (style.intern ({ bold = 'yes', size = -1, align = 'sideways' }), nil)
    eq (
      style.intern ({ align = 'center', border_top = 'thick', color = '#ff0000' }),
      { align = 'center', border_top = 'thick', color = '#ff0000' }
    )
    local copy = assert (style.copy_style (a))
    ok (copy ~= a, 'a copy is a table of its own')
    eq (copy, { bold = true, size = 14 })
  end
)

test ('a layer lies over its base, and clean drops defaults', function ()
  local base = style.intern ({ bold = true, color = '#000000' })
  local top = style.intern ({ color = '#ff0000', italic = true })
  eq (style.layer (base, top), { bold = true, italic = true, color = '#ff0000' })
  ok (
    style.layer (base, top) == style.layer (base, top),
    'the same table each time'
  )
  ok (style.layer (nil, top) == top)
  ok (style.clean (nil) == style.EMPTY)
  eq (style.clean (style.intern ({ bold = false, size = 13, wrap = true })), {
    wrap = true,
  })
  ok (style.is_default ('format', 'general'))
  ok (style.is_default ('size', 13))
  ok (not style.is_default ('size', 12))
end)

test ('patches change some fields and leave the rest', function ()
  local row = style.intern ({ bold = true, fill = '#eeeeee' })
  eq (style.patched (row, { bold = false, italic = true }), {
    fill = '#eeeeee',
    italic = true,
  })
  eq (
    style.patched (row, { bold = false }, { bold = true }),
    { bold = false, fill = '#eeeeee' },
    'a field a style below sets becomes its reset'
  )
  local inherited = style.intern ({ bold = true, color = '#0000ff' }) --[[@as Sheet.Style]]
  eq (
    style.cell_patch (
      nil,
      { bold = false, color = '#0000ff', size = 20 },
      inherited
    ),
    { bold = false, size = 20 },
    'the cell cancels the bold it inherits and leaves the colour to its row'
  )
  eq (style.strip (style.intern ({ bold = true, size = 20 }), { 'size' }), {
    bold = true,
  })
  local full =
    style.full_patch (style.intern ({ bold = true }) --[[@as Sheet.Style]]) --[[@as table<string, any>]]
  eq (full.bold, true)
  eq (full.size, false)
  eq (style.patch_fields ({ size = 20, bold = false }), { 'bold', 'size' })
  eq (#style.SIDES, 4)
end)
