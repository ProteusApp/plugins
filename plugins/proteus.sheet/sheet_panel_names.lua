-- sheet_panel_names: the Names panel of the Sheet app. It lists the workbook's defined names
-- and edits one at a time in a form. sheet_panel_side installs it.

local formula = require ('sheet_formula') --[[@as Sheet.FormulaModule]]
local model = require ('sheet_model') --[[@as Sheet.ModelModule]]

---A defined name being edited.
---@class Sheet.NameDraft
---@field old? string The name as it was, or nil for a new one.
---@field name string
---@field formula string

---@class Sheet.NamesPanelModule
local M = {}

---@param K Sheet.SidePanelKit
---@return Sheet.NamesPanel
function M.install (K)
  local ctl, ui, bodies, renders = K.ctl, K.ui, K.bodies, K.renders
  local field, empty, input, icon_button =
    K.field, K.empty, K.input, K.icon_button

  -- Defined names ----------------------------------------------------------------------

  local name_draft = nil ---@type Sheet.NameDraft?

  ---A new name's formula: the selection on the sheet that shows, such as
  ---`=Sheet1!$B$2:$B$9`.
  ---@return string
  local function selection_formula ()
    local rect = ctl.selection ()
    local sheet = ctl.sheet ()
    ---@param row integer
    ---@param col integer
    ---@return string
    local function fixed (row, col)
      return '$' .. model.col_name (col) .. '$' .. row
    end
    local text_now = fixed (rect.r1, rect.c1)
    if rect.r1 ~= rect.r2 or rect.c1 ~= rect.c2 then
      text_now = text_now .. ':' .. fixed (rect.r2, rect.c2)
    end
    return '='
      .. formula.quote_sheet (sheet and sheet.name or 'Sheet1')
      .. '!'
      .. text_now
  end

  ---@param body Proteus.El
  ---@param book Sheet.Book
  local function names_list (body, book)
    local list = ui.div ({ class = 'sheet-panel-list' })
    for _, n in ipairs (book.defined_names) do
      local item = n
      local card = ui.div ({
        class = 'sheet-panel-card',
        title = 'Edit this name',
        ui.icon ('tag', 16),
        ui.div ({
          class = 'sheet-panel-card-main',
          ui.span ({ class = 'sheet-panel-desc', item.name }),
          ui.span ({ class = 'sheet-panel-range', item.formula }),
        }),
        ui.div ({
          class = 'sheet-panel-tools',
          icon_button ('trash-2', 'Delete the name', function ()
            ctl.change ('Delete name', function (b)
              b:delete_name (item.name)
            end)
          end),
        }),
      })
      card:on ('click', function ()
        name_draft =
          { old = item.name, name = item.name, formula = item.formula }
        renders.names ()
        return nil
      end)
      list:append (card)
    end
    if #book.defined_names == 0 then
      list:append (empty ('This workbook has no names yet.'))
    end
    body:append (
      list,
      ui.button ({
        'Define name',
        icon = 'plus',
        class = 'sheet-panel-wide',
        onclick = function ()
          name_draft = { name = '', formula = selection_formula () }
          renders.names ()
          return nil
        end,
      }),
      ui.div ({
        class = 'sheet-panel-hint',
        'A formula anywhere in the workbook can use a name in place of what it stands for, such as =SUM(Sales).',
      })
    )
  end

  ---@param body Proteus.El
  ---@param draft Sheet.NameDraft
  local function names_form (body, draft)
    local name_box = input (draft.name, function (value)
      draft.name = value
    end, { placeholder = 'Sales' })
    local formula_box = input (draft.formula, function (value)
      draft.formula = value
    end, { placeholder = '=Sheet1!$B$2:$B$9', mono = true })
    body:append (
      field ('Name', name_box),
      field (
        'Stands for',
        formula_box,
        ui.div ({
          class = 'sheet-panel-hint',
          'A reference such as =Sheet1!$B$2:$B$9, a value such as =0.2, or a function such as =LAMBDA(x, x*2).',
        })
      ),
      ui.div ({
        class = 'sheet-panel-actions',
        draft.old and ui.button ({
          'Delete',
          variant = 'danger',
          onclick = function ()
            local old = draft.old --[[@as string]]
            ctl.change ('Delete name', function (b)
              b:delete_name (old)
            end)
            name_draft = nil
            renders.names ()
            return nil
          end,
        }) or nil,
        ui.span ({ class = 'sheet-panel-spacer' }),
        ui.button ({
          'Cancel',
          onclick = function ()
            name_draft = nil
            renders.names ()
            return nil
          end,
        }),
        ui.button ({
          'Done',
          variant = 'primary',
          onclick = function ()
            draft.name = string.match (name_box:value (), '^%s*(.-)%s*$')
            draft.formula = string.match (formula_box:value (), '^%s*(.-)%s*$')
            local problem = ctl.change (
              draft.old and 'Change name' or 'Define name',
              function (b)
                local done, why =
                  b:set_name (draft.name, draft.formula, draft.old)
                if not done then
                  return why or 'The name could not be defined.'
                end
                return nil
              end
            )
            if type (problem) == 'string' then
              ctl.say ('warn', problem)
              return nil
            end
            name_draft = nil
            renders.names ()
            return nil
          end,
        }),
      })
    )
    name_box:focus ()
  end

  renders.names = function ()
    local body = bodies.names
    body:clear ()
    local book = ctl.book ()
    if not book then
      name_draft = nil
      body:append (empty ('Open a workbook to define names.'))
      return
    end
    if name_draft then
      names_form (body, name_draft)
    else
      names_list (body, book)
    end
  end

  ---@class Sheet.NamesPanel
  local panel = {
    reset = function ()
      name_draft = nil
    end,
    ---@return boolean
    editing = function ()
      return name_draft ~= nil
    end,
  }
  return panel
end

return M
