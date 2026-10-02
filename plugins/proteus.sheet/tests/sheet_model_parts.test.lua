-- Tests for the parts of sheet_model that add methods to every sheet: sheet_model_clip, for
-- filling, copying and CSV, and sheet_model_data, for a sheet as plain data.

local model = require ('sheet_model') --[[@as Sheet.ModelModule]]

test ('each part is a function that takes the model kit', function ()
  for _, name in ipairs ({ 'sheet_model_clip', 'sheet_model_data' }) do
    eq (type (require (name)), 'function', name)
  end
  local sheet = model.new ()
  for _, method in ipairs ({
    'fill_down',
    'fill_right',
    'copy',
    'follow_move',
    'paste',
    'paste_text',
    'clone',
    'load',
    'to_data',
  }) do
    eq (type ((sheet --[[@as table<string, any>]])[method]), 'function', method)
  end
end)

test ('CSV text and rows go both ways', function ()
  local rows = model.parse_csv ('a,"b, c"\n1,"say ""hi"""\n')
  eq (rows, { { 'a', 'b, c' }, { '1', 'say "hi"' } })
  eq (model.parse_csv (model.to_csv (rows)), rows)
  eq (model.parse_csv ('x\ty', '\t'), { { 'x', 'y' } })
end)

test ('a sheet from rows, filled down and copied as data', function ()
  local sheet = model.from_grid ({ { '1', '=A1*2' }, { '3', '' } })
  eq (sheet:text (1, 2), '=A1*2')
  sheet:fill_down ({ r1 = 1, c1 = 2, r2 = 2, c2 = 2 })
  eq (sheet:text (2, 2), '=A2*2')
  local copy = sheet:clone ('Copy')
  eq (copy.name, 'Copy')
  eq (copy:text (2, 2), '=A2*2')
  local again = model.new ()
  again:load (sheet:to_data ())
  eq (again:text (1, 1), '1')
  eq (again:text (2, 2), '=A2*2')
end)
