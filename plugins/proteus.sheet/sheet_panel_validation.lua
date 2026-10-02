-- sheet_panel_validation: the Validation panel of the Sheet app. It lists the data validation
-- rules of the selection or of the whole sheet, and edits one at a time in a form, which saves
-- on Done. sheet_panel_side installs it.

local format = require ('sheet_format') --[[@as Sheet.FormatModule]]
local formula = require ('sheet_formula') --[[@as Sheet.FormulaModule]]
local model = require ('sheet_model') --[[@as Sheet.ModelModule]]
local ops = require ('sheet_ops') --[[@as Sheet.OpsModule]]
local text = require ('sheet_panel_text') --[[@as Sheet.PanelTextModule]]

---A validation rule being edited.
---@class Sheet.ValidationDraft
---@field index? integer
---@field range string
---@field type 'list'|'number'|'date'|'length'|'formula'
---@field items string The items one per line, or a reference to cells such as `=$A$1:$A$9`.
---@field formula string The formula of a formula rule.
---@field op string
---@field a string
---@field b string
---@field integer boolean
---@field message string
---@field strict boolean

---@class Sheet.ValidationPanelModule
local M = {}

---@param K Sheet.SidePanelKit
---@return Sheet.ValidationPanel
function M.install (K)
  local ctl, ui, bodies, renders = K.ctl, K.ui, K.bodies, K.renders
  local field, empty, select, segmented =
    K.field, K.empty, K.select, K.segmented
  local check, input, icon_button, selection_text =
    K.check, K.input, K.icon_button, K.selection_text
  local read_range = K.read_range

  -- Data validation --------------------------------------------------------------------

  local checks_scope = 'selection' ---@type 'selection'|'all'
  local check_draft = nil ---@type Sheet.ValidationDraft?

  ---@param v? Sheet.Validation
  ---@param index? integer
  ---@return Sheet.ValidationDraft
  local function new_check_draft (v, index)
    if v then
      local items = table.concat (v.values or {}, '\n')
      if v.type == 'list' and type (v.formula) == 'string' then
        items = v.formula
      end
      return {
        index = index,
        range = v.range,
        type = v.type or 'list',
        items = items,
        formula = v.type == 'formula' and v.formula or '',
        op = v.op or 'between',
        a = v.value or '',
        b = v.value2 or '',
        integer = v.integer == true,
        message = v.message or '',
        strict = v.strict ~= false,
      }
    end
    return {
      range = selection_text (),
      type = 'list',
      items = '',
      formula = '',
      op = 'between',
      a = '',
      b = '',
      integer = false,
      message = '',
      strict = true,
    }
  end

  ---@param body Proteus.El
  ---@param sheet Sheet.Sheet
  local function checks_list (body, sheet)
    local sel = ctl.selection ()
    body:append (segmented (
      {
        { value = 'selection', label = 'This selection' },
        { value = 'all', label = 'Whole sheet' },
      },
      checks_scope,
      function (value)
        checks_scope = value == 'all' and 'all' or 'selection'
        renders.validation ()
      end
    ))
    local list = ui.div ({ class = 'sheet-panel-list' })
    local count = 0
    for i, v in ipairs (sheet.validation) do
      local rect = model.parse_range (v.range)
      if checks_scope == 'all' or (rect and model.overlaps (rect, sel)) then
        count = count + 1
        local index = i
        local card = ui.div ({
          class = 'sheet-panel-card',
          title = 'Edit this rule',
          ui.icon (
            v.type == 'list' and 'list'
              or v.type == 'date' and 'calendar'
              or v.type == 'length' and 'type'
              or v.type == 'formula' and 'sigma'
              or 'hash',
            16
          ),
          ui.div ({
            class = 'sheet-panel-card-main',
            ui.span ({
              class = 'sheet-panel-desc',
              text.describe_validation (v),
            }),
            ui.div ({
              class = 'sheet-panel-meta',
              ui.span ({ class = 'sheet-panel-range', v.range }),
              ui.span ({
                class = 'sheet-panel-badge',
                v.strict == false and 'Warns' or 'Refuses',
              }),
            }),
          }),
          ui.div ({
            class = 'sheet-panel-tools',
            icon_button ('trash-2', 'Delete the rule', function ()
              ctl.change ('Delete validation', function (_, s)
                ops.set_validation (s, index, nil)
              end)
            end),
          }),
        })
        card:on ('click', function ()
          check_draft = new_check_draft (v, index)
          renders.validation ()
          return nil
        end)
        list:append (card)
      end
    end
    if count == 0 then
      list:append (
        empty (
          checks_scope == 'all' and 'This sheet has no validation rules yet.'
            or 'No validation rules cover the selected cells.'
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
          check_draft = new_check_draft ()
          renders.validation ()
          return nil
        end,
      }),
      ui.div ({
        class = 'sheet-panel-hint',
        'Where rules cover the same cell, the last one decides.',
      })
    )
  end

  ---@param body Proteus.El
  ---@param draft Sheet.ValidationDraft
  local function checks_form (body, draft)
    local range = input (draft.range, function (value, el)
      local rect = read_range (el, value)
      if rect then
        draft.range = model.range_name (rect)
        el:value (draft.range)
      end
    end, { mono = true })
    local items = ui.input ({
      multiline = true,
      value = draft.items,
      placeholder = 'Yes\nNo\nMaybe',
      spellcheck = false,
      rows = 5,
    })
    local list_part = field (
      'Items',
      items,
      ui.div ({
        class = 'sheet-panel-hint',
        'One item per line, or split by commas on one line, or cells such as =$A$1:$A$9. The cell gets a dropdown of them.',
      })
    )
    local a_box = input (draft.a, function (value)
      draft.a = value
    end, { placeholder = 'Number' })
    local b_box = input (draft.b, function (value)
      draft.b = value
    end, { placeholder = 'Number' })
    local formula_box = input (draft.formula, function (value)
      draft.formula = value
    end, { placeholder = '=AND(A1>0, A1<=$B$1)', mono = true })
    local formula_part = field (
      'Formula',
      formula_box,
      ui.div ({
        class = 'sheet-panel-hint',
        'Write the formula for the top left cell of the range. A value goes in when it gives TRUE.',
      })
    )
    local and_word = ui.span ({ class = 'sheet-panel-hint', 'and' })
    local function show_op ()
      local two = draft.op == 'between' or draft.op == 'not_between'
      b_box:show (two)
      and_word:show (two)
    end
    local op_options = {} ---@type { value: string, label: string }[]
    for _, o in ipairs (text.VALIDATION_OPS) do
      op_options[#op_options + 1] = { value = o.id, label = o.label }
    end
    local op = select (op_options, draft.op, function (value)
      draft.op = value
      show_op ()
    end)
    show_op ()
    local whole = check ('Whole numbers only', draft.integer, function (on)
      draft.integer = on
    end)
    local number_part = field (
      'Value',
      op,
      ui.div ({ class = 'sheet-panel-row', a_box, and_word, b_box }),
      whole
    )
    local function show_type ()
      local kind = draft.type
      list_part:show (kind == 'list')
      number_part:show (kind == 'number' or kind == 'date' or kind == 'length')
      formula_part:show (kind == 'formula')
      whole:show (kind == 'number')
      local hint = kind == 'date' and '1/1/2026'
        or kind == 'length' and 'Characters'
        or 'Number'
      a_box:set ('placeholder', hint)
      b_box:set ('placeholder', hint)
    end
    show_type ()
    local message = input (draft.message, function (value)
      draft.message = value
    end, { placeholder = 'Leave empty for the default message' })

    ---@return boolean
    local function valid ()
      local rect = read_range (range, range:value ())
      if not rect then
        return false
      end
      draft.range = model.range_name (rect)
      draft.items = items:value ()
      draft.a = a_box:value ()
      draft.b = b_box:value ()
      draft.formula = formula_box:value ()
      draft.message = message:value ()
      if draft.type == 'list' then
        local source = string.match (draft.items, '^%s*(=.-)%s*$')
        local good = #text.list_values (draft.items) > 0
        if source then
          good = formula.parse (source) ~= nil
        end
        items:class ('sheet-panel-bad', not good)
        return good
      elseif draft.type == 'formula' then
        local good = formula.is_formula (draft.formula)
          and formula.parse (draft.formula) ~= nil
        formula_box:class ('sheet-panel-bad', not good)
        return good
      end
      ---@param s string
      ---@return boolean
      local function readable (s)
        if draft.type == 'date' then
          return type (format.parse_input (s)) == 'number'
        end
        return tonumber (s) ~= nil
      end
      local two = draft.op == 'between' or draft.op == 'not_between'
      local good_a = readable (draft.a)
      local good_b = not two or readable (draft.b)
      a_box:class ('sheet-panel-bad', not good_a)
      b_box:class ('sheet-panel-bad', not good_b)
      return good_a and good_b
    end

    ---@return Sheet.Validation
    local function rule_of_draft ()
      local rule = { range = draft.range, type = draft.type } ---@type Sheet.Validation
      local source = string.match (draft.items, '^%s*(=.-)%s*$')
      if draft.type == 'list' and source then
        rule.formula = formula.normalize (source)
      elseif draft.type == 'list' then
        rule.values = text.list_values (draft.items)
      elseif draft.type == 'formula' then
        rule.formula = formula.normalize (draft.formula)
      else
        rule.op = draft.op
        rule.value = draft.a
        if draft.op == 'between' or draft.op == 'not_between' then
          rule.value2 = draft.b
        end
        rule.integer = draft.type == 'number' and draft.integer or nil
      end
      if draft.message ~= '' then
        rule.message = draft.message
      end
      if not draft.strict then
        rule.strict = false
      end
      return rule
    end

    body:append (
      field ('Apply to range', range),
      field (
        'Criteria',
        select (
          {
            { value = 'list', label = 'List of items' },
            { value = 'number', label = 'Number' },
            { value = 'date', label = 'Date' },
            { value = 'length', label = 'Text length' },
            { value = 'formula', label = 'Formula' },
          },
          draft.type,
          function (value)
            if
              value == 'number'
              or value == 'date'
              or value == 'length'
              or value == 'formula'
            then
              draft.type = value
            else
              draft.type = 'list'
            end
            show_type ()
          end
        )
      ),
      list_part,
      number_part,
      formula_part,
      field ('Message for data that breaks the rule', message),
      field (
        'When data breaks the rule',
        segmented (
          {
            { value = 'refuse', label = 'Refuse it' },
            { value = 'warn', label = 'Show a warning' },
          },
          draft.strict and 'refuse' or 'warn',
          function (value)
            draft.strict = value == 'refuse'
          end
        )
      ),
      ui.div ({
        class = 'sheet-panel-actions',
        draft.index and ui.button ({
          'Delete',
          variant = 'danger',
          onclick = function ()
            local index = draft.index
            ctl.change ('Delete validation', function (_, s)
              ops.set_validation (s, index --[[@as integer]], nil)
            end)
            check_draft = nil
            renders.validation ()
            return nil
          end,
        }) or nil,
        ui.span ({ class = 'sheet-panel-spacer' }),
        ui.button ({
          'Cancel',
          onclick = function ()
            check_draft = nil
            renders.validation ()
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
            local rule = rule_of_draft ()
            local index = draft.index
            ctl.change (
              index and 'Change validation' or 'Add validation',
              function (_, s)
                if index and s.validation[index] then
                  ops.set_validation (s, index, rule)
                else
                  ops.add_validation (s, rule)
                end
              end
            )
            check_draft = nil
            renders.validation ()
            return nil
          end,
        }),
      })
    )
  end

  renders.validation = function ()
    local body = bodies.validation
    body:clear ()
    local sheet = ctl.sheet ()
    if not sheet then
      check_draft = nil
      body:append (empty ('Open a workbook to add validation rules.'))
      return
    end
    if check_draft then
      checks_form (body, check_draft)
    else
      checks_list (body, sheet)
    end
  end

  ---@class Sheet.ValidationPanel
  local panel = {
    reset = function ()
      check_draft = nil
    end,
    ---@return boolean
    editing = function ()
      return check_draft ~= nil
    end,
    ---@return 'selection'|'all'
    scope = function ()
      return checks_scope
    end,
  }
  return panel
end

return M
