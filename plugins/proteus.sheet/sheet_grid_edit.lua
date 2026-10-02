-- sheet_grid_edit: editing cells in the Sheet app's grid, and the formula bar with the name box.
-- sheet_grid.lua installs it into the grid.
--
-- A cell is edited in one of two boxes: the cell editor over the cell, or the formula bar. Both
-- show the same text. While a formula is typed, each reference gets its own colour. A text box
-- cannot colour its own text, so a copy of the text with coloured references lies under each
-- box, whose own text does not show while the caret does. The same references get an outline
-- in their colour on the grid.
--
-- A list of matching functions opens under the box while a name is typed, and a hint with the
-- current argument in bold shows while the caret sits inside a function's brackets. Clicking a
-- cell or pressing an arrow key where a reference can go puts the cell's address in, and a
-- click on another sheet's tab first lets the reference name that sheet.

local calc = require ('sheet_grid_calc') --[[@as Sheet.GridCalcModule]]
local formula = require ('sheet_formula') --[[@as Sheet.FormulaModule]]
local model = require ('sheet_model') --[[@as Sheet.ModelModule]]
local ops = require ('sheet_ops') --[[@as Sheet.OpsModule]]

---@class Sheet.GridEditModule
local M = {}

-- How many functions the list under the editor offers.
local CHOICES = 8
-- The most cells Ctrl+Enter fills at once.
local FILL_MAX = 50000

-- lang=css
local CSS = [[
.sheet-grid-bar { flex: none; display: flex; align-items: center; gap: 6px; height: 34px; padding: 0 8px;
  border-bottom: 1px solid var(--border); background: var(--bg); position: relative; z-index: 20; }
.sheet-grid-bar .sheet-grid-name { flex: none; width: 92px; height: 26px; box-sizing: border-box; padding: 0 6px;
  text-align: center; font-family: var(--font-mono); font-size: 12px; }
.sheet-grid-fx { flex: none; color: var(--fg-faint); font-family: var(--font-mono); font-style: italic;
  user-select: none; padding: 0 2px; border-left: 1px solid var(--border); padding-left: 8px; }
.sheet-grid-fwrap { flex: 1; min-width: 0; height: 26px; position: relative; }
.sheet-grid-fbar, .sheet-grid-fmirror { position: absolute; left: 0; top: 0; width: 100%; box-sizing: border-box;
  margin: 0; padding: 4px 6px; border: 1px solid transparent; border-radius: var(--radius);
  font-family: var(--font-mono); font-size: 12.5px; line-height: 16px; white-space: pre-wrap;
  overflow-wrap: anywhere; letter-spacing: normal; }
.sheet-grid-fbar { z-index: 1; height: 26px; resize: none; overflow: hidden; outline: none; background: transparent;
  color: var(--fg); caret-color: var(--fg); }
.sheet-grid-fbar:focus { height: auto; field-sizing: content; min-height: 26px; max-height: 160px; overflow-y: auto;
  border-color: var(--accent); background: var(--bg); box-shadow: var(--shadow); }
.sheet-grid-fmirror { display: none; height: 26px; overflow: hidden; pointer-events: none; color: var(--fg); }
.sheet-grid-fwrap.sheet-grid-fx .sheet-grid-fmirror { display: block; }
.sheet-grid-fwrap.sheet-grid-fx .sheet-grid-fbar { color: transparent; }
.sheet-grid-fwrap.sheet-grid-fx .sheet-grid-fbar:focus { background: transparent; box-shadow: none; }
.sheet-grid-fwrap.sheet-grid-open .sheet-grid-fmirror { height: auto; min-height: 26px; max-height: 160px;
  border-color: var(--accent); background: var(--bg); box-shadow: var(--shadow); }

.sheet-grid-edbox { position: absolute; left: 0; top: 0; width: max-content; pointer-events: none; }
.sheet-grid-edwrap { position: relative; }
.sheet-grid-editor, .sheet-grid-mirror { display: block; box-sizing: border-box; margin: 0; padding: 2px 6px 2px 3px;
  border: 2px solid transparent; font-family: var(--font-ui); font-size: var(--fs, 13px); font-weight: inherit;
  font-style: inherit; line-height: 1.25; white-space: pre-wrap; overflow-wrap: anywhere; letter-spacing: normal;
  text-align: left; }
.sheet-grid-editor { position: relative; z-index: 1; width: var(--w); height: var(--h); min-width: var(--w);
  min-height: var(--h); resize: none; overflow: hidden; outline: none; background: transparent;
  color: transparent; caret-color: transparent; opacity: 0; pointer-events: none; }
.sheet-grid-edbox.sheet-grid-on .sheet-grid-editor { opacity: 1; pointer-events: auto; field-sizing: content;
  width: auto; height: auto; max-width: 560px; color: var(--fg); caret-color: var(--fg); background: var(--bg);
  border-color: var(--accent); box-shadow: var(--shadow); }
.sheet-grid-mirror { position: absolute; top: 0; bottom: 0; left: 0; right: -12px; display: none;
  pointer-events: none; overflow: hidden; color: var(--fg); }
.sheet-grid-edbox.sheet-grid-on.sheet-grid-fx .sheet-grid-edwrap { background: var(--bg); }
.sheet-grid-edbox.sheet-grid-on.sheet-grid-fx .sheet-grid-mirror { display: block; }
.sheet-grid-edbox.sheet-grid-on.sheet-grid-fx .sheet-grid-editor { color: transparent; background: transparent; }

.sheet-grid-pop { display: none; position: absolute; left: 0; top: 100%; margin-top: 3px; z-index: 5; pointer-events: auto;
  min-width: 280px; max-width: 440px; padding: 4px 0; background: var(--bg-elev); color: var(--fg);
  border: 1px solid var(--border); border-radius: var(--radius); box-shadow: var(--shadow);
  font-family: var(--font-ui); font-size: 12px; line-height: 1.4; white-space: normal; text-align: left; }
.sheet-grid-pop.sheet-grid-up { top: auto; bottom: 100%; margin: 0 0 3px; }
.sheet-grid-pop.sheet-grid-show { display: block; }
.sheet-grid-pi { padding: 4px 10px; cursor: pointer; }
.sheet-grid-pi b { font-family: var(--font-mono); font-weight: 600; }
.sheet-grid-pi span { color: var(--fg-muted); margin-left: 8px; font-family: var(--font-mono); font-size: 11px; }
.sheet-grid-pi div { display: none; color: var(--fg-muted); margin-top: 2px; }
.sheet-grid-pi.sheet-grid-on { background: var(--bg-active); }
.sheet-grid-pi.sheet-grid-on div { display: block; }
.sheet-grid-hs { padding: 2px 10px; font-family: var(--font-mono); font-size: 12px; }
.sheet-grid-hs b { color: var(--accent); }
.sheet-grid-hd { padding: 2px 10px 4px; color: var(--fg-muted); }
]]

---The byte a caret sits before, from its place in JavaScript's UTF-16 units.
---@param text string
---@param units number
---@return integer
local function to_byte (text, units)
  local byte, count = 1, 0
  for ch in string.gmatch (text, utf8.charpattern) do
    if count >= units then
      break
    end
    count = count + (#ch == 4 and 2 or 1)
    byte = byte + #ch
  end
  return byte
end

---The place of a byte in JavaScript's UTF-16 units.
---@param text string
---@param byte integer
---@return integer
local function to_units (text, byte)
  local units = 0
  for ch in string.gmatch (string.sub (text, 1, byte - 1), utf8.charpattern) do
    units = units + (#ch == 4 and 2 or 1)
  end
  return units
end

---@param grid Sheet.GridView
function M.install (grid)
  local G = grid
  local app, ui, env = G.app, G.ui, G.env
  ui.css (CSS)

  G.namebox = ui.input ({
    class = 'sheet-grid-name',
    spellcheck = false,
    title = 'The selected cells. Type an address such as C12 or Income!A1 and press Enter to go there.',
  })
  G.fbar = ui.h ('textarea', {
    class = 'sheet-grid-fbar',
    spellcheck = false,
    rows = 1,
    attrs = { autocomplete = 'off', ['aria-label'] = 'Formula' },
  })
  G.fmirror = ui.div ({ class = 'sheet-grid-fmirror' })
  G.fpop = ui.div ({ class = 'sheet-grid-pop' })
  local fwrap =
    ui.div ({ class = 'sheet-grid-fwrap', G.fmirror, G.fbar, G.fpop })
  G.bar = ui.div ({
    class = 'sheet-grid-bar',
    G.namebox,
    ui.span ({ class = 'sheet-grid-fx', 'fx' }),
    fwrap,
  })
  local editor, mirror, pop = G.editor, G.mirror, G.pop
  local fbar, fmirror, fpop = G.fbar, G.fmirror, G.fpop
  local shown_pop = { cell = '', bar = '' }

  ---@param e Sheet.GridEdit
  ---@return Proteus.El
  local function box_of (e)
    return e.source == 'bar' and fbar or editor
  end

  ---@param e Sheet.GridEdit
  ---@return Proteus.El
  local function other_of (e)
    return e.source == 'bar' and editor or fbar
  end

  ---Shows the list or the hint under the box being typed in, or hides both with ''.
  ---@param html string
  local function show_pop (html)
    local e = G.edit
    local which = e and e.source or 'cell'
    local el = which == 'bar' and fpop or pop
    local other = which == 'bar' and pop or fpop
    local other_key = which == 'bar' and 'cell' or 'bar'
    if shown_pop[other_key] ~= '' then
      shown_pop[other_key] = ''
      other:class ('sheet-grid-show', false)
    end
    if shown_pop[which] == html then
      return
    end
    shown_pop[which] = html
    if html == '' then
      el:class ('sheet-grid-show', false)
      return
    end
    el:html (html)
    el:class ('sheet-grid-show', true)
  end

  ---Colours the references of formula text under both boxes, or clears the colours.
  ---@param text string
  ---@param own? Sheet.Sheet The sheet the formula lives on, for the outlines on the grid.
  local function colour (text, own)
    local fx = string.sub (text, 1, 1) == '='
    if fx then
      local spans = formula.ref_spans (text)
      local colors = calc.span_colors (spans)
      local html = calc.mirror_html (text, spans, colors)
      mirror:html (html)
      fmirror:html (html)
      G.ref_css = own and G.refs_css (spans, colors, own) or ''
    else
      G.ref_css = ''
    end
    G.edbox:class ('sheet-grid-fx', fx)
    fwrap:class ('sheet-grid-fx', fx)
  end

  ---Shows the active cell's text in the formula bar while nothing is being edited.
  function G.show_edit_text ()
    local s = G.sheet ()
    if not s or G.edit then
      return
    end
    local text = s:edit_text (G.sel.r, G.sel.c)
    fbar:value (text)
    colour (text, nil)
  end

  ---The function list's HTML.
  ---@param e Sheet.GridEdit
  ---@return string
  local function choices_html (e)
    local parts = {} ---@type string[]
    for i, fn in ipairs (e.choices) do
      parts[#parts + 1] = '<div class="sheet-grid-pi'
        .. (i == e.choice and ' sheet-grid-on' or '')
        .. '" data-item="fn:'
        .. calc.escape (fn.name)
        .. '"><b>'
        .. calc.escape (fn.name)
        .. '</b><span>'
        .. calc.escape (fn.syntax)
        .. '</span><div>'
        .. calc.escape (fn.summary)
        .. '</div></div>'
    end
    return table.concat (parts)
  end

  ---Works out the colours, the outlines, and the list or hint, from the text and the caret.
  local function helpers ()
    local e = G.edit
    if not e then
      return
    end
    local box = box_of (e)
    local text = box:value () or ''
    colour (text, e.sheet)
    G.place_boxes ()
    if string.sub (text, 1, 1) ~= '=' then
      e.choices = {}
      show_pop ('')
      return
    end
    local pos = to_byte (text, tonumber (box:get ('selectionStart')) or #text)
    local comp = formula.complete (text, pos)
    e.choices = comp and calc.matching (formula.catalog, comp.prefix, CHOICES)
      or {}
    e.choice = 1
    if #e.choices > 0 then
      show_pop (choices_html (e))
      return
    end
    local call = formula.call_at (text, pos)
    if call then
      for _, fn in ipairs (formula.catalog) do
        if fn.name == call.name then
          show_pop (calc.hint_html (fn, call.arg))
          return
        end
      end
    end
    show_pop ('')
  end

  ---Flips the list above the cell editor when the cell sits low in the view.
  local function place_pop ()
    local e = G.edit
    local geo = G.geo
    if not e or not geo or e.source ~= 'cell' then
      return
    end
    local b = calc.view_box (
      geo,
      { r1 = e.row, c1 = e.col, r2 = e.row, c2 = e.col },
      G.sx,
      G.sy,
      G.vw,
      G.vh
    )
    pop:class (
      'sheet-grid-up',
      b ~= nil and b.y + b.h > G.vh - 220 and b.y > 240
    )
  end

  -- Starting and ending an edit ------------------------------------------------------------

  ---Starts editing the active cell in the cell editor or the formula bar. `typed` is true
  ---when typing started it, so arrow keys finish it.
  ---@param source 'cell'|'bar'
  ---@param text string
  ---@param typed boolean
  function G.begin_edit (source, text, typed)
    local s = G.sheet ()
    if not s or G.edit then
      return
    end
    G.select_chart (nil)
    local r, c = G.sel.r, G.sel.c
    local m = s:merge_at (r, c)
    if m then
      r, c = m.r1, m.c1
    end
    G.edit = {
      sheet = s,
      row = r,
      col = c,
      source = source,
      original = s:edit_text (r, c),
      typed = typed,
      choices = {},
      choice = 1,
    }
    local st = s:style_at (r, c)
    local font = {} ---@type string[]
    if st.bold then
      font[#font + 1] = 'font-weight:700'
    end
    if st.italic then
      font[#font + 1] = 'font-style:italic'
    end
    if st.size and st.size ~= 13 then
      font[#font + 1] = '--fs:' .. st.size .. 'px'
    end
    G.edbox:attr ('style', table.concat (font, ';'))
    G.edbox:class ('sheet-grid-on', true)
    fbar:value (text)
    if source == 'cell' then
      -- Typing put the text in the box already. Setting it again would break an input method.
      if not typed then
        editor:value (text)
        local n = to_units (text, #text + 1)
        editor:call ('setSelectionRange', n, n)
      end
      editor:focus ()
      place_pop ()
    else
      editor:value (text)
      fwrap:class ('sheet-grid-open', true)
    end
    helpers ()
    env.emit ('editing', true)
  end

  ---Closes the editor without touching the cell.
  local function close ()
    local e = G.edit
    G.edit = nil
    G.edbox:class ('sheet-grid-on', false)
    G.edbox:class ('sheet-grid-fx', false)
    G.edbox:attr ('style', '')
    fwrap:class ('sheet-grid-open', false)
    editor:value ('')
    G.ref_css = ''
    G.set_box ('point', nil)
    show_pop ('')
    if e then
      env.emit ('editing', false)
    end
  end

  ---Shows the sheet an edit belongs to, when another one shows.
  ---@param e Sheet.GridEdit
  local function back_to (e)
    local book = G.cur_book
    local index = book and book:index_of (e.sheet)
    if book and index and index ~= book.active then
      G.show_sheet (index)
    end
  end

  ---Ends the edit and keeps the text, then moves the selection. Returns false when the
  ---cell's validation refuses the text, which leaves the editor open.
  ---@param dr integer
  ---@param dc integer
  ---@param refocus? boolean False when the focus is leaving for somewhere else.
  ---@return boolean
  function G.finish_edit (dr, dc, refocus)
    local e = G.edit
    if not e then
      return true
    end
    local box = box_of (e)
    local text = formula.normalize (box:value () or '')
    local changed = text ~= e.original
    if changed then
      local good, message, strict =
        ops.check_input (e.sheet, e.row, e.col, text)
      if not good then
        if strict then
          env.say ('error', message or 'This cell does not take that value.')
          box:focus ()
          return false
        end
        env.say (
          'warn',
          message or 'That value is outside the rule for this cell.'
        )
      end
      -- A formula that does not read, such as one with the wrong count of arguments, still
      -- goes in and shows #ERROR!, and the message says why.
      if formula.is_formula (text) then
        local ast, problem = formula.parse (text)
        if not ast then
          env.say ('warn', problem or 'The formula does not read.')
        end
      end
    end
    close ()
    back_to (e)
    if changed then
      G.change ('Typing', function (_, s)
        s:set (e.row, e.col, text)
      end)
    end
    if G.sel.r ~= e.row or G.sel.c ~= e.col then
      local rect = G.sel_rect ()
      if
        e.row < rect.r1
        or e.row > rect.r2
        or e.col < rect.c1
        or e.col > rect.c2
      then
        G.sel = {
          r = e.row,
          c = e.col,
          ar = e.row,
          ac = e.col,
          er = e.row,
          ec = e.col,
        }
      end
    end
    if dr ~= 0 or dc ~= 0 then
      G.move (dr, dc)
    else
      G.place ()
    end
    if refocus ~= false then
      editor:focus ()
    end
    return true
  end

  ---Ends the edit and puts its text into every selected cell. Formulas move their references
  ---for each cell, as a copy would.
  local function fill_selection ()
    local e = G.edit
    local s = G.sheet ()
    if not e or not s or e.sheet ~= s then
      G.finish_edit (0, 0)
      return
    end
    local rect = G.sel_rect ()
    local count = (rect.r2 - rect.r1 + 1) * (rect.c2 - rect.c1 + 1)
    if count <= 1 or count > FILL_MAX then
      G.finish_edit (0, 0)
      return
    end
    local text = formula.normalize (box_of (e):value () or '')
    close ()
    local is_formula = formula.is_formula (text)
    G.change ('Fill', function (_, sh)
      local list = {} ---@type table[]
      for r = rect.r1, rect.r2 do
        if not sh:row_hidden (r) then
          for c = rect.c1, rect.c2 do
            local m = sh:merge_at (r, c)
            if
              not sh:col_hidden (c) and (not m or (m.r1 == r and m.c1 == c))
            then
              local t = text
              if is_formula then
                t = formula.shift (text, r - e.row, c - e.col)
              end
              list[#list + 1] = { r, c, t }
            end
          end
        end
      end
      sh:set_many (list)
    end)
    G.place ()
    editor:focus ()
  end

  ---Ends the edit and throws the text away.
  function G.cancel_edit ()
    local e = G.edit
    if not e then
      return
    end
    close ()
    back_to (e)
    G.place ()
    editor:focus ()
  end

  ---After another sheet shows during an edit, the edit goes on in the formula bar, since the
  ---cell editor sits over a cell of the first sheet.
  function G.edit_moved ()
    local e = G.edit
    if not e then
      return
    end
    local here = e.sheet == G.sheet ()
    if e.source == 'cell' and not here then
      local text = editor:value () or ''
      local caret = tonumber (editor:get ('selectionStart')) or #text
      e.source = 'bar'
      fbar:value (text)
      fwrap:class ('sheet-grid-open', true)
      fbar:focus ()
      fbar:call ('setSelectionRange', caret, caret)
    end
    G.edbox:class ('sheet-grid-on', here)
    helpers ()
  end

  ---Types into the open editor at its caret, or starts editing the active cell with `text`.
  ---@param text string
  function G.type_text (text)
    local e = G.edit
    if e then
      local box = box_of (e)
      box:focus ()
      if not app.dom.exec ('insertText', text) then
        local old = box:value () or ''
        local at = to_byte (old, tonumber (box:get ('selectionStart')) or #old)
        local new = string.sub (old, 1, at - 1) .. text .. string.sub (old, at)
        box:value (new)
        other_of (e):value (new)
        local n = to_units (new, at + #text)
        box:call ('setSelectionRange', n, n)
        helpers ()
      end
      return
    end
    if not G.sheet () then
      return
    end
    G.begin_edit ('cell', text, false)
    local cur = G.edit
    if cur then
      cur.typed = true
    end
  end

  -- Pointing at cells ----------------------------------------------------------------------

  local function end_point ()
    local e = G.edit
    if e and e.point then
      e.point = nil
      G.set_box ('point', nil)
    end
  end

  ---Puts the pointed-at block into the formula, in place of the one put there before.
  local function write_point ()
    local e = G.edit
    local p = e and e.point
    local s = G.sheet ()
    if not e or not p or not s then
      return
    end
    local box = box_of (e)
    local text = box:value () or ''
    local rect = model.tidy ({ r1 = p.ar, c1 = p.ac, r2 = p.er, c2 = p.ec })
    rect = s:expand_to_merges (rect)
    local ref = model.range_name (rect)
    if s ~= e.sheet then
      ref = formula.quote_sheet (s.name) .. '!' .. ref
    end
    local new = string.sub (text, 1, p.from - 1)
      .. ref
      .. string.sub (text, p.to)
    p.to = p.from + #ref
    box:value (new)
    other_of (e):value (new)
    local caret = to_units (new, p.to)
    box:call ('setSelectionRange', caret, caret)
    G.set_box ('point', rect)
    helpers ()
    G.reveal (p.er, p.ec)
  end

  ---Points at a cell while typing a formula. Returns false when the caret is not where a
  ---reference can go.
  ---@param row integer
  ---@param col integer
  ---@param extend boolean
  ---@return boolean
  function G.point_at (row, col, extend)
    local e = G.edit
    local s = G.sheet ()
    if not e or not s then
      return false
    end
    row = math.min (math.max (1, row), s.rows)
    col = math.min (math.max (1, col), s.cols)
    local p = e.point
    if p then
      if extend then
        p.er, p.ec = row, col
      else
        p.ar, p.ac, p.er, p.ec = row, col, row, col
      end
    else
      local box = box_of (e)
      local text = box:value () or ''
      local pos = to_byte (text, tonumber (box:get ('selectionStart')) or 0)
      if not formula.can_point (text, pos) then
        return false
      end
      e.point = { from = pos, to = pos, ar = row, ac = col, er = row, ec = col }
    end
    write_point ()
    return true
  end

  ---@param dr integer
  ---@param dc integer
  ---@param extend boolean
  ---@param jump boolean
  ---@return boolean
  local function point_move (dr, dc, extend, jump)
    local e = G.edit
    local s = G.sheet ()
    if not e or not s then
      return false
    end
    local p = e.point
    local r, c = G.sel.r, G.sel.c
    if e.sheet == s then
      r, c = e.row, e.col
    end
    if p then
      r, c = p.er, p.ec
    end
    if jump then
      r, c = s:jump (r, c, dr, dc)
    else
      r, c = s:next_visible (r, c, dr, dc)
    end
    return G.point_at (r, c, extend and p ~= nil)
  end

  -- Keys while editing ---------------------------------------------------------------------

  ---Takes the highlighted function from the list: its name and an opening bracket replace the
  ---name being typed.
  local function take_choice ()
    local e = G.edit
    local fn = e and e.choices[e.choice]
    if not e or not fn then
      return
    end
    local box = box_of (e)
    local text = box:value () or ''
    local pos = to_byte (text, tonumber (box:get ('selectionStart')) or #text)
    local comp = formula.complete (text, pos)
    if not comp then
      return
    end
    local insert = fn.name
    if string.sub (text, comp.to + 1, comp.to + 1) ~= '(' then
      insert = insert .. '('
    end
    box:focus ()
    box:call (
      'setSelectionRange',
      to_units (text, comp.from),
      to_units (text, comp.to + 1)
    )
    if not app.dom.exec ('insertText', insert) then
      local new = string.sub (text, 1, comp.from - 1)
        .. insert
        .. string.sub (text, comp.to + 1)
      box:value (new)
      other_of (e):value (new)
      local n = to_units (new, comp.from + #insert)
      box:call ('setSelectionRange', n, n)
    elseif string.sub (insert, -1) ~= '(' then
      local after = to_units (text, comp.from) + #insert + 1
      box:call ('setSelectionRange', after, after)
    end
    helpers ()
  end

  ---F4: cycles the anchors of the reference at the caret.
  local function toggle_anchor ()
    local e = G.edit
    if not e then
      return
    end
    local box = box_of (e)
    local text = box:value () or ''
    local pos = to_byte (text, tonumber (box:get ('selectionStart')) or #text)
    local new, at = formula.toggle_anchor (text, pos)
    if new == text then
      return
    end
    box:value (new)
    other_of (e):value (new)
    local n = to_units (new, at)
    box:call ('setSelectionRange', n, n)
    end_point ()
    helpers ()
  end

  ---Keys while a cell is being edited, in the cell editor or in the formula bar.
  ---@param ev Proteus.DomEvent
  ---@return Proteus.EventResult
  local function edit_key (ev)
    local e = G.edit
    if not e or ev.composing then
      return nil
    end
    local key = ev.key or ''
    local mod = ev.ctrl == true or ev.meta == true
    if #e.choices > 0 then
      if key == 'ArrowDown' or key == 'ArrowUp' then
        local n = #e.choices
        e.choice = (e.choice - 1 + (key == 'ArrowDown' and 1 or -1)) % n + 1
        show_pop (choices_html (e))
        return 'prevent'
      end
      if
        key == 'Tab'
        or (key == 'Enter' and not mod and not ev.alt and not ev.shift)
      then
        take_choice ()
        return 'prevent'
      end
      if key == 'Escape' then
        e.choices = {}
        show_pop ('')
        return 'stop'
      end
    end
    if key == 'Enter' then
      if ev.alt then
        if not app.dom.exec ('insertText', '\n') then
          local box = box_of (e)
          local old = box:value () or ''
          box:value (old .. '\n')
        end
        return 'prevent'
      end
      if mod then
        fill_selection ()
        return 'prevent'
      end
      G.finish_edit (ev.shift and -1 or 1, 0)
      return 'prevent'
    end
    if key == 'Tab' then
      G.finish_edit (0, ev.shift and -1 or 1)
      return 'prevent'
    end
    if key == 'Escape' then
      G.cancel_edit ()
      return 'stop'
    end
    if key == 'F2' then
      e.typed = not e.typed
      return 'prevent'
    end
    if key == 'F4' then
      toggle_anchor ()
      return 'prevent'
    end
    local dir = ({
      ArrowUp = { -1, 0 },
      ArrowDown = { 1, 0 },
      ArrowLeft = { 0, -1 },
      ArrowRight = { 0, 1 },
    })[key]
    if dir then
      if not ev.alt and point_move (dir[1], dir[2], ev.shift == true, mod) then
        return 'prevent'
      end
      if
        e.typed
        and e.source == 'cell'
        and not ev.shift
        and not mod
        and not ev.alt
      then
        G.finish_edit (dir[1], dir[2])
        return 'prevent'
      end
      end_point ()
    end
    return nil
  end

  -- The cell editor ------------------------------------------------------------------------

  editor:on ('keydown', function (ev)
    if G.edit then
      return edit_key (ev)
    end
    return G.grid_key (ev)
  end)

  editor:on ('input', function (ev)
    local e = G.edit
    if e then
      if e.source == 'cell' then
        fbar:value (editor:value () or '')
      end
      end_point ()
      helpers ()
      return nil
    end
    local text = editor:value () or ''
    if
      ev.input_type == 'insertFromPaste'
      or ev.input_type == 'insertFromPasteAsQuotation'
      or ev.input_type == 'insertFromDrop'
    then
      editor:value ('')
      local mode = G.paste_mode
      G.paste_mode = nil
      G.paste_text (text, mode)
      return nil
    end
    if text ~= '' and G.sheet () then
      G.begin_edit ('cell', text, true)
    end
    return nil
  end)

  editor:on ('keyup', function (ev)
    local key = ev.key or ''
    if
      G.edit
      and (
        key == 'ArrowLeft'
        or key == 'ArrowRight'
        or key == 'Home'
        or key == 'End'
      )
    then
      helpers ()
    end
    return nil
  end)

  editor:on ('mousedown', function ()
    end_point ()
    return nil
  end)

  editor:on ('click', function ()
    if G.edit then
      helpers ()
    end
    return nil
  end)

  editor:on ('blur', function ()
    app.timer.after (0, function ()
      local e = G.edit
      if not e or e.source ~= 'cell' then
        return
      end
      local now = app.dom.active ()
      if now == editor.id then
        return
      end
      if now == fbar.id then
        -- A click in the formula bar carries the edit over to it.
        e.source = 'bar'
        fwrap:class ('sheet-grid-open', true)
        show_pop ('')
        return
      end
      G.finish_edit (0, 0, false)
    end)
    return nil
  end)

  -- The formula bar ------------------------------------------------------------------------

  fbar:on ('focus', function ()
    local s = G.sheet ()
    if s and not G.edit then
      G.begin_edit ('bar', s:edit_text (G.sel.r, G.sel.c), false)
    end
    return nil
  end)

  fbar:on ('input', function ()
    local s = G.sheet ()
    if not s then
      return nil
    end
    local text = fbar:value () or ''
    if not G.edit then
      G.begin_edit ('bar', text, false)
    end
    editor:value (text)
    end_point ()
    helpers ()
    return nil
  end)

  fbar:on ('keydown', function (ev)
    local e = G.edit
    if e and e.source == 'bar' then
      return edit_key (ev)
    end
    return nil
  end)

  fbar:on ('keyup', function (ev)
    local key = ev.key or ''
    if
      G.edit
      and (
        key == 'ArrowLeft'
        or key == 'ArrowRight'
        or key == 'Home'
        or key == 'End'
      )
    then
      helpers ()
    end
    return nil
  end)

  fbar:on ('scroll', function ()
    fmirror:set ('scrollTop', tonumber (fbar:get ('scrollTop')) or 0)
    return nil
  end)

  fbar:on ('mousedown', function ()
    end_point ()
    return nil
  end)

  fbar:on ('click', function ()
    if G.edit then
      helpers ()
    end
    return nil
  end)

  fbar:on ('blur', function ()
    app.timer.after (0, function ()
      local e = G.edit
      if not e or e.source ~= 'bar' then
        return
      end
      local now = app.dom.active ()
      if now == fbar.id then
        return
      end
      if now == editor.id then
        e.source = 'cell'
        fwrap:class ('sheet-grid-open', false)
        return
      end
      G.finish_edit (0, 0, false)
    end)
    return nil
  end)

  -- The function list takes a click without taking the focus from the box.
  for _, el in ipairs ({ pop, fpop }) do
    el:on ('mousedown', function (ev)
      local name = string.match (ev.item or '', '^fn:(.+)$')
      local e = G.edit
      if name and e then
        for i, fn in ipairs (e.choices) do
          if fn.name == name then
            e.choice = i
          end
        end
        take_choice ()
      end
      return 'prevent'
    end)
  end

  -- The name box ---------------------------------------------------------------------------

  G.namebox:on ('focus', function ()
    G.namebox:select ()
    return nil
  end)

  G.namebox:on ('keydown', function (ev)
    local book = G.cur_book
    if not book then
      return nil
    end
    if ev.key == 'Enter' then
      local text = G.namebox:value () or ''
      local rect, sheet_name = model.parse_ref (text)
      if not rect then
        env.say (
          'warn',
          'Type a cell such as C12, a block such as A1:C5, or Income!A1.'
        )
        return 'prevent'
      end
      if sheet_name then
        local target = book:find (sheet_name)
        if not target then
          env.say ('warn', 'There is no sheet named "' .. sheet_name .. '".')
          return 'prevent'
        end
        local index = book:index_of (target)
        if index and index ~= book.active then
          G.show_sheet (index)
        end
      end
      G.editor:focus ()
      G.select (rect)
      return 'prevent'
    end
    if ev.key == 'Escape' then
      G.editor:focus ()
      G.place ()
      return 'prevent'
    end
    return nil
  end)

  G.namebox:on ('blur', function ()
    if G.sheet () then
      G.namebox:value (model.range_name (G.sel_rect ()))
    end
    return nil
  end)

  -- Dropdown lists -------------------------------------------------------------------------

  ---Opens the choices of a list cell in a menu under it.
  ---@param row integer
  ---@param col integer
  function G.open_dropdown (row, col)
    local s = G.sheet ()
    local menus = G.menus
    local values = s and ops.dropdown (s, row, col)
    if not s or not values or not menus then
      return
    end
    local rect = G.cell_rect (row, col)
    if not rect then
      return
    end
    local now = s:text (row, col)
    ---@type Proteus.MenuItem[]
    local items = {}
    for _, v in ipairs (values) do
      local value = v
      items[#items + 1] = {
        label = value,
        icon = value == now and 'check' or nil,
        run = function ()
          G.change ('Typing', function (_, sh)
            sh:set (row, col, value)
          end)
          G.focus ()
        end,
      }
    end
    if #items == 0 then
      items[1] = { label = 'This list has no choices yet.', disabled = true }
    end
    menus.popup (items, rect.left, rect.bottom + 2, {
      on_close = function ()
        G.focus ()
      end,
    })
  end
end

return M
