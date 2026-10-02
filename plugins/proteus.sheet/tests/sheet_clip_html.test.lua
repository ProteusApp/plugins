-- Tests for sheet_clip_html: cells copied as an HTML table, and tables pasted from other
-- programs, with their look.

local B = require ('sheet_book') --[[@as Sheet.BookModule]]
local html = require ('sheet_clip_html') --[[@as Sheet.ClipHtmlModule]]
local m = require ('sheet_model') --[[@as Sheet.ModelModule]]

local KEY = m.KEY

---@return Sheet.Sheet
local function sheet_of ()
  return B.new ():active_sheet ()
end

test ('a copy writes a table with the shown values and the look', function ()
  local s = sheet_of ()
  s:set (1, 1, 'Name')
  s:set (1, 2, '1234.5')
  s:set (2, 1, 'a<b & "c"')
  s:set (2, 2, '=B1*2')
  s:set_style (
    { r1 = 1, c1 = 1, r2 = 1, c2 = 1 },
    { bold = true, fill = '#ffeeaa', align = 'center' }
  )
  s:set_link (2, 1, 'https://example.com/?a=1&b=2')
  local text = html.from_sheet (s, { r1 = 1, c1 = 1, r2 = 2, c2 = 2 })
  ok (string.find (text, '<table', 1, true), text)
  ok (
    string.find (
      text,
      '<td style="font-weight:bold;background-color:#ffeeaa;text-align:center">Name</td>',
      1,
      true
    ),
    text
  )
  ok (string.find (text, '<td>2469</td>', 1, true), text)
  ok (
    string.find (
      text,
      '<a href="https://example.com/?a=1&amp;b=2">a&lt;b &amp; &quot;c&quot;</a>',
      1,
      true
    ),
    text
  )
end)

test ('merged cells span, and hidden rows are left out', function ()
  local s = sheet_of ()
  s:set (1, 1, 'Wide')
  s:merge ({ r1 = 1, c1 = 1, r2 = 1, c2 = 2 })
  s:set (2, 1, 'hidden')
  s:set_hidden ('row', 2, 2, true)
  s:set (3, 1, 'x')
  local text = html.from_sheet (s, { r1 = 1, c1 = 1, r2 = 3, c2 = 2 })
  ok (string.find (text, '<td colspan="2">Wide</td></tr>', 1, true), text)
  ok (not string.find (text, 'hidden', 1, true), text)
end)

test ("Excel's HTML pastes with its classes, spans and links", function ()
  local clip = assert (html.parse ([[
Version:0.9
StartHTML:0000000105
<html><head><style>
<!--
.xl65 { font-weight:700; mso-number-format:General; }
td.xl66, .xl67 { color:#FF0000; background:yellow; font-size:11.0pt; border:.5pt solid windowtext; }
-->
</style></head><body>
<table border=0>
 <col width=64>
 <tr height=20>
  <td class=xl65 height=20>Total</td>
  <td class="xl66" align=right>1,234</td>
 </tr>
 <tr>
  <td colspan=2 style='text-align:center'>A &amp; B&nbsp;&#233;</td>
 </tr>
 <tr><td><a href="https://example.com">site</a></td><td>line<br>two</td></tr>
</table>
</body></html>]]))
  eq (
    clip.texts,
    { { 'Total', '1,234' }, { 'A & B é', '' }, { 'site', 'line\ntwo' } }
  )
  eq (clip.patches[1][1], { bold = true })
  eq (clip.patches[1][2], {
    color = '#ff0000',
    fill = '#ffff00',
    align = 'right',
    border_top = 'thin',
    border_right = 'thin',
    border_bottom = 'thin',
    border_left = 'thin',
    border_color = '#000000',
  })
  eq (clip.patches[2][1], { align = 'center' })
  eq (clip.merges, { { r1 = 2, c1 = 1, r2 = 2, c2 = 2 } })
  eq (clip.links, { [3 * KEY + 1] = 'https://example.com' })
  ok (clip.typed)
end)

test ('a row span from above leaves its cells empty below', function ()
  local clip = assert (
    html.parse (
      '<table><tr><td rowspan="2">a</td><td>b</td></tr><tr><td>c</td></tr></table>'
    )
  )
  eq (clip.texts, { { 'a', 'b' }, { '', 'c' } })
  eq (clip.merges, { { r1 = 1, c1 = 1, r2 = 2, c2 = 1 } })
end)

test ('HTML without a table gives nothing to paste as cells', function ()
  eq (html.parse ('<p>Just <b>words</b></p>'), nil)
  eq (html.parse ('<table></table>'), nil)
end)

test ('a pasted table keeps its look and reads its text as typed', function ()
  local s = sheet_of ()
  local clip = assert (
    html.parse (
      '<table><tr><td style="font-weight:bold;color:rgb(0, 128, 0)">10%</td>'
        .. '<td>=1+1</td></tr></table>'
    )
  )
  s:paste (2, 2, clip)
  eq (s:style_at (2, 2).bold, true)
  eq (s:style_at (2, 2).color, '#008000')
  eq (s:display (2, 2), '10%', 'the percent typed as a number with its format')
  eq (s:display (2, 3), '2')
end)

test ('colours read from hex, short hex, rgb() and names', function ()
  eq (html.color ('#ABCDEF'), '#abcdef')
  eq (html.color ('#abc'), '#aabbcc')
  eq (html.color ('rgb(255, 0, 10)'), '#ff000a')
  eq (html.color ('Navy'), '#000080')
  eq (html.color ('transparent'), nil)
end)
