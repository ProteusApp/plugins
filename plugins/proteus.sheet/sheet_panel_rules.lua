-- sheet_panel_rules: the Formatting panel of the Sheet app, for conditional formatting. It
-- lists the rules of the selection or of the whole sheet as cards, and edits one at a time in
-- a form, which saves on Done. sheet_panel_side installs it.

local model = require ('sheet_model') --[[@as Sheet.ModelModule]]
local ops = require ('sheet_ops') --[[@as Sheet.OpsModule]]
local text = require ('sheet_panel_text') --[[@as Sheet.PanelTextModule]]

---A rule being edited in the conditional formatting form.
---@class Sheet.RuleDraft
---@field index? integer The rule's place in the sheet's list, or nil for a new rule.
---@field range string
---@field cond string A condition id from `sheet_panel_text`.
---@field a string
---@field b string
---@field style Sheet.Style
---@field min_color string
---@field mid_color? string
---@field max_color string
---@field bar_color string
---@field icons string The icon set of an icon set rule.
---@field reverse boolean True to give the lowest values the first icon.
---@field stop boolean Stop if true.

---@class Sheet.RulesPanelModule
local M = {}

---@param t table
---@return table
local function copy (t)
  local out = {} ---@type table<any, any>
  for k, v in
    pairs (t --[[@as table<any, any>]])
  do
    out[k] = v
  end
  return out
end

---The CSS a rule's style shows in a small preview box.
---@param style? Sheet.Style
---@return string
local function style_css (style)
  local s = style or {}
  local parts = {} ---@type string[]
  if s.fill then
    parts[#parts + 1] = 'background:' .. s.fill
  end
  if s.color then
    parts[#parts + 1] = 'color:' .. s.color
  elseif s.fill then
    parts[#parts + 1] = 'color:'
      .. (text.is_dark (s.fill) and '#ffffff' or '#1f1f1f')
  end
  if s.bold then
    parts[#parts + 1] = 'font-weight:700'
  end
  if s.italic then
    parts[#parts + 1] = 'font-style:italic'
  end
  local lines = {} ---@type string[]
  if s.strike then
    lines[#lines + 1] = 'line-through'
  end
  if s.underline then
    lines[#lines + 1] = 'underline'
  end
  if #lines > 0 then
    parts[#parts + 1] = 'text-decoration:' .. table.concat (lines, ' ')
  end
  return table.concat (parts, ';')
end

---The CSS background of a colour scale or data bar preview.
---@param rule Sheet.Rule
---@return string
local function rule_background (rule)
  if rule.type == 'scale' then
    local stops = { rule.min_color or text.SCALE_MIN }
    if rule.mid_color then
      stops[#stops + 1] = rule.mid_color
    end
    stops[#stops + 1] = rule.max_color or text.SCALE_MAX
    return 'background:linear-gradient(90deg,'
      .. table.concat (stops, ',')
      .. ')'
  end
  local color = rule.color or text.BAR_COLOR
  return 'background:linear-gradient(90deg,'
    .. color
    .. ' 0 62%,transparent 62%)'
end

---@param K Sheet.SidePanelKit
---@return Sheet.RulesPanel
function M.install (K)
  local ctl, ui, bodies, renders = K.ctl, K.ui, K.bodies, K.renders
  local field, empty, select, segmented =
    K.field, K.empty, K.select, K.segmented
  local check, input, color_button, icon_button =
    K.check, K.input, K.color_button, K.icon_button
  local selection_text, read_range = K.selection_text, K.read_range

  -- Conditional formatting --------------------------------------------------------------

  local rules_scope = 'selection' ---@type 'selection'|'all'
  local rule_draft = nil ---@type Sheet.RuleDraft?

  ---@param rule? Sheet.Rule
  ---@param index? integer
  ---@return Sheet.RuleDraft
  local function new_rule_draft (rule, index)
    if rule then
      local style = copy (rule.style or {}) --[[@as Sheet.Style]]
      return {
        index = index,
        range = rule.range,
        cond = text.condition_of (rule),
        a = rule.formula
          or (rule.count and tostring (rule.count))
          or rule.value
          or '',
        b = rule.value2 or '',
        style = style,
        min_color = rule.min_color or text.SCALE_MIN,
        mid_color = rule.mid_color,
        max_color = rule.max_color or text.SCALE_MAX,
        bar_color = rule.color or text.BAR_COLOR,
        icons = rule.icons or 'arrows',
        reverse = rule.reverse == true,
        stop = rule.stop == true,
      }
    end
    return {
      range = selection_text (),
      cond = '>',
      a = '',
      b = '',
      style = { color = text.RULE_COLOR, fill = text.RULE_FILL },
      min_color = text.SCALE_MIN,
      mid_color = text.SCALE_MID,
      max_color = text.SCALE_MAX,
      bar_color = text.BAR_COLOR,
      icons = 'arrows',
      reverse = false,
      stop = false,
    }
  end

  ---@param draft Sheet.RuleDraft
  ---@return Sheet.Rule
  local function rule_of (draft)
    local rule = text.rule_fields (draft.cond, draft.a, draft.b) --[[@as Sheet.Rule]]
    rule.range = draft.range
    if rule.type == 'scale' then
      rule.min_color = draft.min_color
      rule.mid_color = draft.mid_color
      rule.max_color = draft.max_color
    elseif rule.type == 'bar' then
      rule.color = draft.bar_color
    elseif rule.type == 'icons' then
      rule.icons = draft.icons
      rule.reverse = draft.reverse or nil
    else
      local style = {} ---@type table<string, any>
      for k, v in
        pairs (draft.style --[[@as table<string, any>]])
      do
        if v ~= false and v ~= nil then
          style[k] = v
        end
      end
      rule.style = style --[[@as Sheet.Style]]
    end
    rule.stop = draft.stop or nil
    return rule
  end

  ---The rule list: cards for the rules in scope, and Add rule.
  ---@param body Proteus.El
  ---@param sheet Sheet.Sheet
  local function rules_list (body, sheet)
    local sel = ctl.selection ()
    body:append (segmented (
      {
        { value = 'selection', label = 'This selection' },
        { value = 'all', label = 'Whole sheet' },
      },
      rules_scope,
      function (value)
        rules_scope = value == 'all' and 'all' or 'selection'
        renders.rules ()
      end
    ))
    local list = ui.div ({ class = 'sheet-panel-list' })
    local count = 0
    for i, rule in ipairs (sheet.rules) do
      local rect = model.parse_range (rule.range)
      local shown = rules_scope == 'all'
        or (rect ~= nil and model.overlaps (rect, sel))
      if shown then
        count = count + 1
        local preview ---@type Proteus.El
        if rule.type == 'scale' or rule.type == 'bar' then
          preview = ui.div ({
            class = 'sheet-panel-preview',
            style = rule_background (rule),
          })
        else
          preview = ui.div ({
            class = 'sheet-panel-preview',
            style = style_css (rule.style),
            '123',
          })
        end
        local index = i
        local card = ui.div ({
          class = 'sheet-panel-card',
          title = 'Edit this rule',
          preview,
          ui.div ({
            class = 'sheet-panel-card-main',
            ui.span ({ class = 'sheet-panel-desc', text.describe_rule (rule) }),
            ui.span ({ class = 'sheet-panel-range', rule.range }),
          }),
          ui.div ({
            class = 'sheet-panel-tools',
            icon_button (
              'arrow-up',
              'Move up, so it wins over the rules below it',
              function ()
                ctl.change ('Move rule', function (_, s)
                  local a, b = s.rules[index - 1], s.rules[index]
                  ops.set_rule (s, index - 1, b)
                  ops.set_rule (s, index, a)
                end)
              end,
              index == 1
            ),
            icon_button (
              'arrow-down',
              'Move down, so the rules above it win over it',
              function ()
                ctl.change ('Move rule', function (_, s)
                  local a, b = s.rules[index], s.rules[index + 1]
                  ops.set_rule (s, index, b)
                  ops.set_rule (s, index + 1, a)
                end)
              end,
              index == #sheet.rules
            ),
            icon_button ('trash-2', 'Delete the rule', function ()
              ctl.change ('Delete rule', function (_, s)
                ops.set_rule (s, index, nil)
              end)
            end),
          }),
        })
        card:on ('click', function ()
          rule_draft = new_rule_draft (rule, index)
          renders.rules ()
          return nil
        end)
        list:append (card)
      end
    end
    if count == 0 then
      list:append (
        empty (
          rules_scope == 'all' and 'This sheet has no rules yet.'
            or 'No rules touch the selected cells.'
        )
      )
    end
    body:append (
      list,
      ui.button ({
        'Add rule',
        icon = 'plus',
        class = 'sheet-panel-wide',
        onclick = function ()
          rule_draft = new_rule_draft ()
          renders.rules ()
          return nil
        end,
      }),
      ui.div ({
        class = 'sheet-panel-hint',
        'A rule higher in the list wins where two set the same thing, and a rule set to stop keeps the rules below it from applying.',
      })
    )
  end

  ---The form for one rule.
  ---@param body Proteus.El
  ---@param draft Sheet.RuleDraft
  local function rules_form (body, draft)
    local range = input (draft.range, function (value, el)
      local rect = read_range (el, value)
      if rect then
        draft.range = model.range_name (rect)
        el:value (draft.range)
      end
    end, { mono = true })

    local a_box = input (draft.a, function (value)
      draft.a = value
    end)
    local b_box = input (draft.b, function (value)
      draft.b = value
    end)
    local and_word = ui.span ({ class = 'sheet-panel-hint', 'and' })
    local values =
      ui.div ({ class = 'sheet-panel-row', a_box, and_word, b_box })
    local values_hint = ui.div ({ class = 'sheet-panel-hint' })

    local sample = ui.div ({ class = 'sheet-panel-sample', 'Sample 123' })
    local function show_sample ()
      sample:attr ('style', style_css (draft.style))
    end
    ---@param field_name 'bold'|'italic'|'strike'|'underline'
    ---@param icon string
    ---@param title string
    ---@return Proteus.El
    local function style_toggle (field_name, icon, title)
      local on = draft.style[field_name] == true
      local b = ui.h ('button', {
        class = 'sheet-panel-toggle' .. (on and ' on' or ''),
        title = title,
        ui.icon (icon, 15),
      })
      b:on ('click', function ()
        local flags = draft.style --[[@as table<string, boolean?>]]
        local now = not (flags[field_name] == true)
        flags[field_name] = now or nil
        b:class ('on', now)
        show_sample ()
        return nil
      end)
      return b
    end
    local style_part = field (
      'Formatting style',
      ui.div ({
        class = 'sheet-panel-row',
        ui.div ({
          class = 'sheet-panel-toggles',
          style_toggle ('bold', 'bold', 'Bold'),
          style_toggle ('italic', 'italic', 'Italic'),
          style_toggle ('underline', 'underline', 'Underline'),
          style_toggle ('strike', 'strikethrough', 'Strikethrough'),
        }),
        ui.span ({ class = 'sheet-panel-spacer', style = 'flex:1' }),
        ui.span ({ class = 'sheet-panel-hint', 'Text' }),
        color_button (draft.style.color, 'Text colour', function (c)
          draft.style.color = c
          show_sample ()
        end),
        ui.span ({ class = 'sheet-panel-hint', 'Fill' }),
        color_button (draft.style.fill, 'Fill colour', function (c)
          draft.style.fill = c
          show_sample ()
        end),
      }),
      sample
    )
    show_sample ()

    local gradient = ui.div ({ class = 'sheet-panel-sample' })
    local function show_gradient ()
      gradient:attr (
        'style',
        rule_background ({
          range = '',
          type = 'scale',
          min_color = draft.min_color,
          mid_color = draft.mid_color,
          max_color = draft.max_color,
        })
      )
    end
    local mid_button = color_button (
      draft.mid_color,
      'Midpoint colour',
      function (c)
        draft.mid_color = c
        show_gradient ()
      end
    )
    local scale_part = field (
      'Colour scale',
      ui.div ({
        class = 'sheet-panel-row',
        ui.span ({ class = 'sheet-panel-hint', 'Lowest' }),
        color_button (
          draft.min_color,
          'Colour of the lowest value',
          function (c)
            draft.min_color = c or text.SCALE_MIN
            show_gradient ()
          end
        ),
        ui.span ({ class = 'sheet-panel-hint', 'Middle' }),
        mid_button,
        ui.span ({ class = 'sheet-panel-hint', 'Highest' }),
        color_button (
          draft.max_color,
          'Colour of the highest value',
          function (c)
            draft.max_color = c or text.SCALE_MAX
            show_gradient ()
          end
        ),
      }),
      gradient,
      ui.div ({
        class = 'sheet-panel-hint',
        'Reset the middle colour for a scale of two colours.',
      })
    )
    show_gradient ()

    local bar_part = field (
      'Data bar',
      ui.div ({
        class = 'sheet-panel-row',
        ui.span ({ class = 'sheet-panel-hint', 'Bar colour' }),
        color_button (draft.bar_color, 'Bar colour', function (c)
          draft.bar_color = c or text.BAR_COLOR
        end),
      })
    )

    local icons_part = field (
      'Icon set',
      select (text.ICON_SETS, draft.icons, function (value)
        draft.icons = value
      end),
      check ('Lowest values get the first icon', draft.reverse, function (on)
        draft.reverse = on
      end),
      ui.div ({
        class = 'sheet-panel-hint',
        'The top third of the range from the lowest value to the highest gets the first icon, the middle third the second, and the rest the last.',
      })
    )

    local function show_condition ()
      local c = text.condition (draft.cond) or text.CONDITIONS[1]
      local kind = c.input
      values:show (kind ~= 'none')
      b_box:show (kind == 'two')
      and_word:show (kind == 'two')
      a_box:set (
        'placeholder',
        kind == 'count' and '10'
          or kind == 'formula' and '=$B1>100'
          or 'Value or number'
      )
      a_box:class ('sheet-panel-mono', kind == 'formula')
      values_hint:show (kind == 'formula' or kind == 'count')
      if kind == 'formula' then
        values_hint:text (
          'Write the formula for the top left cell of the range. It moves to each cell as a copied formula does.'
        )
      elseif kind == 'count' then
        values_hint:text (
          c.percent and 'The percent of values to mark.'
            or 'How many values to mark.'
        )
      end
      style_part:show (
        c.type ~= 'scale' and c.type ~= 'bar' and c.type ~= 'icons'
      )
      scale_part:show (c.type == 'scale')
      bar_part:show (c.type == 'bar')
      icons_part:show (c.type == 'icons')
    end

    local options = {} ---@type { value: string, label: string }[]
    for _, c in ipairs (text.CONDITIONS) do
      options[#options + 1] = { value = c.id, label = c.label }
    end
    local cond = select (options, draft.cond, function (value)
      draft.cond = value
      show_condition ()
    end)
    show_condition ()

    ---@return boolean
    local function valid ()
      local rect = read_range (range, range:value ())
      if not rect then
        return false
      end
      draft.range = model.range_name (rect)
      draft.a = a_box:value ()
      draft.b = b_box:value ()
      local c = text.condition (draft.cond)
      local good = true
      if
        c and (c.input == 'one' or c.input == 'two' or c.input == 'formula')
      then
        a_box:class ('sheet-panel-bad', draft.a == '')
        good = draft.a ~= ''
      end
      if c and c.input == 'two' then
        b_box:class ('sheet-panel-bad', draft.b == '')
        good = good and draft.b ~= ''
      end
      if c and c.input == 'count' then
        local n = tonumber (draft.a)
        a_box:class ('sheet-panel-bad', not n or n <= 0)
        good = n ~= nil and n > 0
      end
      return good
    end

    local stop = check (
      'Stop if true: the rules below do not apply where this one holds',
      draft.stop,
      function (on)
        draft.stop = on
      end
    )
    body:append (
      field ('Apply to range', range),
      field ('Format cells if', cond, values, values_hint),
      style_part,
      scale_part,
      bar_part,
      icons_part,
      stop,
      ui.div ({
        class = 'sheet-panel-actions',
        draft.index and ui.button ({
          'Delete',
          variant = 'danger',
          onclick = function ()
            local index = draft.index
            ctl.change ('Delete rule', function (_, s)
              ops.set_rule (s, index --[[@as integer]], nil)
            end)
            rule_draft = nil
            renders.rules ()
            return nil
          end,
        }) or nil,
        ui.span ({ class = 'sheet-panel-spacer' }),
        ui.button ({
          'Cancel',
          onclick = function ()
            rule_draft = nil
            renders.rules ()
            return nil
          end,
        }),
        ui.button ({
          'Done',
          variant = 'primary',
          onclick = function ()
            if not valid () then
              return nil
            end
            local rule = rule_of (draft)
            local index = draft.index
            ctl.change (index and 'Change rule' or 'Add rule', function (_, s)
              if index and s.rules[index] then
                ops.set_rule (s, index, rule)
              else
                ops.add_rule (s, rule)
              end
            end)
            rule_draft = nil
            renders.rules ()
            return nil
          end,
        }),
      })
    )
  end

  renders.rules = function ()
    local body = bodies.rules
    body:clear ()
    local sheet = ctl.sheet ()
    if not sheet then
      rule_draft = nil
      body:append (empty ('Open a workbook to add formatting rules.'))
      return
    end
    if rule_draft then
      rules_form (body, rule_draft)
    else
      rules_list (body, sheet)
    end
  end

  ---@class Sheet.RulesPanel
  local panel = {
    reset = function ()
      rule_draft = nil
    end,
    ---@return boolean
    editing = function ()
      return rule_draft ~= nil
    end,
    ---@return 'selection'|'all'
    scope = function ()
      return rules_scope
    end,
  }
  return panel
end

return M
