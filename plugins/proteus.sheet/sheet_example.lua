-- sheet_example: the example workbook of the Sheet app, written on first start. It is plain
-- data in the shape of a `.sheet.json` file, which sheet_book turns into a book.

local formula = require ('sheet_formula') --[[@as Sheet.FormulaModule]]

---@class Sheet.ExampleModule
local M = {}

local MONEY = '$#,##0.00'
local TITLE = { bold = true, size = 20 }
local HEADER = {
  bold = true,
  fill = '#e8eefc',
  border_bottom = 'medium',
  border_color = '#3b5bdb',
}
local TOTAL = { bold = true, border_top = 'thin' }

---The rows of the budget sheet, by row number. Columns D to F of rows 5 to 11 are added below,
---since each row has the same formulas.
---@type table<integer, string[]>
local BUDGET = {
  [1] = { 'Monthly budget' },
  [2] = { 'Change a number in column B or C, and every total follows.' },
  [4] = { 'Item', 'Planned', 'Actual', 'Difference', 'Share', 'Status' },
  [5] = { 'Rent', '1200', '1200' },
  [6] = { 'Groceries', '450', '482.35' },
  [7] = { 'Utilities', '160', '141.2' },
  [8] = { 'Transport', '120', '96.5' },
  [9] = { 'Phone and internet', '75', '75' },
  [10] = { 'Eating out', '150', '212.4' },
  [11] = { 'Total', '=SUM(B5:B10)', '=SUM(C5:C10)' },
  [13] = { 'Average spent', '', '=ROUND(AVERAGE(C5:C10), 2)' },
  [14] = {
    'Biggest item',
    '',
    '=INDEX(A5:A10, MATCH(MAX(C5:C10), C5:C10, 0))',
  },
  [15] = { 'Items over plan', '', '=COUNTIF(F5:F10, "Over")' },
  [17] = { 'Income', '', '=Income!D11' },
  [18] = { 'Savings goal', '', '=C17*10%' },
  [19] = { 'Left over', '', '=C17-C11' },
  [20] = {
    '=IF(C19>=C18, "On track: "&TEXT(C19/C17, "0%")&" of income is left over.", "Short of the savings goal by "&TEXT(C18-C19, "$#,##0.00")&".")',
  },
}

---The income sheet: six months, each a date shown as its month.
---@type table<integer, string[]>
local INCOME = {
  [1] = { 'Monthly income' },
  [3] = { 'Month', 'Salary', 'Other', 'Total' },
  [4] = { '46113', '3000', '120' },
  [5] = { '46143', '3000', '0' },
  [6] = { '46174', '3000', '85' },
  [7] = { '46204', '3150', '200' },
  [8] = { '46235', '3150', '280' },
  [9] = { '46266', '3150', '65' },
  [11] = { 'Average', '', '', '=AVERAGE(D4:D9)' },
}

---@param rows table<integer, string[]>
---@return table<string, string>
local function cells_of (rows)
  local out = {} ---@type table<string, string>
  for row, line in pairs (rows) do
    for col, text in ipairs (line) do
      if text ~= '' then
        out[formula.address (row, col)] = text
      end
    end
  end
  return out
end

---The data of the workbook written on first start: a monthly budget that shows off formulas,
---formats, a chart, a conditional rule and a note, and an income sheet the budget reads.
---@return Sheet.BookData
function M.data ()
  local budget = cells_of (BUDGET)
  for row = 5, 11 do
    local r = string.format ('%d', row)
    budget['D' .. r] = '=C' .. r .. '-B' .. r
    budget['E' .. r] = '=C' .. r .. '/C$11'
    budget['F' .. r] = row == 11
        and '=IF(C11>B11, "Over budget", "Within budget")'
      or ('=IF(C' .. r .. '>B' .. r .. ', "Over", "OK")')
  end
  local styles = { A1 = TITLE } ---@type table<string, Sheet.Style>
  for col = 1, 6 do
    styles[formula.address (4, col)] = HEADER
    styles[formula.address (11, col)] = TOTAL
  end
  for row = 5, 11 do
    styles['E' .. row] = row == 11
        and { bold = true, border_top = 'thin', format = '0.0%' }
      or { format = '0.0%' }
  end
  for _, addr in ipairs ({ 'C13', 'C17', 'C18', 'C19' }) do
    styles[addr] = { format = MONEY }
  end
  -- A count in the money column cancels the column's format.
  styles.C15 = { format = 'General' }
  styles.A20 = { italic = true }
  local income = cells_of (INCOME)
  local income_styles = { A1 = TITLE, D11 = { bold = true, format = MONEY } } ---@type table<string, Sheet.Style>
  for col = 1, 4 do
    income_styles[formula.address (3, col)] = HEADER
  end
  for row = 4, 9 do
    income['D' .. row] = '=B' .. row .. '+C' .. row
    income_styles['A' .. row] = { format = 'mmmm yyyy', align = 'left' }
  end
  ---@type Sheet.BookData
  local data = {
    version = 3,
    active = 1,
    sheets = {
      {
        name = 'Budget',
        widths = { A = 170, B = 110, C = 110, D = 110, F = 120 },
        freeze = { rows = 4 },
        cells = budget,
        styles = styles,
        col_styles = {
          B = { format = MONEY },
          C = { format = MONEY },
          D = { format = MONEY },
        },
        notes = { B5 = 'Rent went up in March.' },
        rules = {
          {
            range = 'D5:D10',
            type = 'compare',
            op = '>',
            value = '0',
            style = { color = '#c62828', bold = true },
          },
        },
        charts = {
          {
            id = 'c1',
            type = 'column',
            range = 'A4:C10',
            title = 'Planned and actual',
            legend = 'bottom',
            x = 720,
            y = 100,
            w = 480,
            h = 300,
          },
        },
      },
      {
        name = 'Income',
        widths = { A = 140, B = 110, C = 110, D = 110 },
        freeze = { rows = 3 },
        cells = income,
        styles = income_styles,
        col_styles = {
          B = { format = MONEY },
          C = { format = MONEY },
          D = { format = MONEY },
        },
      },
    },
  }
  return data
end

return M
