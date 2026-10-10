-- Tests for the parts of the formula language on their own: the ground and the tokenizer in
-- sheet_formula_lex, the parser's table of functions, the evaluator's conversions, the kit's
-- helpers, and the function modules, each of which adds the functions of its own categories.

local editing = require ('sheet_formula_edit') --[[@as Sheet.FormulaModule]]
local evaluator = require ('sheet_formula_eval') --[[@as Sheet.FormulaEval]]
local f = require ('sheet_formula') --[[@as Sheet.FormulaModule]]
local kit = require ('sheet_formula_kit') --[[@as Sheet.FormulaKit]]
local lexer = require ('sheet_formula_lex') --[[@as Sheet.FormulaLex]]
local parser = require ('sheet_formula_parse') --[[@as Sheet.FormulaParse]]

---A workbook with no cells.
---@type Sheet.Context
local CTX = {
  rows = 1,
  cols = 1,
  value = function ()
    return nil
  end,
}

test (
  'every part adds to the one module table sheet_formula returns',
  function ()
    ok (lexer.M == f, 'the table sheet_formula_lex makes')
    ok (editing == f, 'the table sheet_formula_edit adds to')
    ok (type (f.tokenize) == 'function', 'from the tokenizer')
    ok (type (f.parse) == 'function', 'from the parser')
    ok (type (f.evaluate) == 'function', 'from the evaluator')
    ok (#f.catalog > 0 and #f.functions == #f.catalog, 'from the kit')
    ok (type (f.shift) == 'function', 'from the editing helpers')
  end
)

test ('the ground: errors, Latin-1 text and rounding', function ()
  ok (lexer.ERRORS['#N/A'] == f.error ('#N/A'), 'one table per error code')
  ok (lexer.is_error (lexer.ERRORS['#REF!']))
  ok (not lexer.is_error ({ code = '#REF!' }), 'a look-alike is not an error')
  eq (lexer.upper ('café'), 'CAFÉ')
  eq (lexer.lower ('ÉTÉ'), 'été')
  eq (lexer.length ('été'), 3)
  eq (lexer.chars ('aé'), { 'a', 'é' })
  eq (lexer.round_to (2.675, 2, 'near'), 2.68)
  eq (lexer.round_to (-2.5, 0, 'near'), -3)
  eq (lexer.trunc (-2.7), -2)
  eq (lexer.clean (0.1 + 0.2), 0.3)
  local ok_raise, err = pcall (lexer.raise, '#NUM!')
  ok (
    not ok_raise and err == lexer.ERRORS['#NUM!'],
    'raise throws the error value'
  )
end)

test ('the ground: wildcards, sheet names and tokens', function ()
  ok (string.find ('apple', lexer.wildcard ('a*e', true)) ~= nil)
  ok (string.find ('apples', lexer.wildcard ('a*e', true)) == nil)
  ok (string.find ('a*', lexer.wildcard ('a~*', true)) ~= nil, '~* is a star')
  local name, after = lexer.sheet_prefix ("'My Sheet'!A1", 1)
  eq (name, 'My Sheet')
  eq (after, 12)
  eq ((lexer.sheet_prefix ('A1+1', 1)), nil)
  local tokens = assert (lexer.lex ('SUM(A1:B2)', 1, false))
  local kinds = {}
  for i, t in ipairs (tokens) do
    kinds[i] = t.kind
  end
  eq (kinds, { 'name', 'open', 'range', 'close' })
  eq (lexer.lex ('"open', 1, false), nil, 'strict mode stops at an open quote')
  ok (lexer.lex ('"open', 1, true) ~= nil, 'lenient mode ends it')
end)

test (
  'the parser knows every function in the catalog, and only those',
  function ()
    local count = 0
    for name, spec in pairs (parser.FUNCS) do
      count = count + 1
      ok (type (spec.min) == 'number' and spec.max >= spec.min, name)
      ok (spec.run ~= nil or spec.map ~= nil, name .. ' runs')
    end
    eq (count, #f.functions)
    for _, name in ipairs (f.functions) do
      ok (parser.FUNCS[name] ~= nil, name)
    end
    ok (
      parser.COMPARE['<>'] and parser.COMPARE['>='],
      'the comparison operators'
    )
  end
)

test ('the evaluator: conversions and comparisons', function ()
  eq (evaluator.to_number ('12'), 12)
  eq (evaluator.to_number (true), 1)
  eq (evaluator.to_number (nil), 0)
  eq (evaluator.to_text (2.5), '2.5')
  eq (evaluator.to_text (false), 'FALSE')
  eq (evaluator.to_bool (0), false)
  eq (evaluator.text_number ('15%'), 0.15)
  eq (evaluator.text_number ('(5)'), -5)
  eq (evaluator.compare (1, 'a'), -1, 'numbers sort before text')
  eq (evaluator.compare ('a', 'A'), 0, 'text compares without case')
  local a = evaluator.new_array (2, 3, {})
  eq ({ evaluator.dims (a) }, { 2, 3 })
  eq ({ evaluator.dims (5) }, { 1, 1 })
  ok (evaluator.is_grid (a) and not evaluator.is_grid (5))
  eq (evaluator.eval (assert (f.parse ('1+2*3')), CTX), 7)
end)

test ('the kit: criteria, sums, spreads and fits', function ()
  ok (kit.equals ('a*', true) ('apple'))
  ok (not kit.equals ('a*', false) ('apple'), 'no wildcards without wild')
  eq (kit.total_of ({ 1, 2, 3.5 }), 6.5)
  eq (kit.variance ({ 2, 4, 4, 4, 5, 5, 7, 9 }, false), 4)
  eq (kit.percentile ({ 1, 2, 3, 4 }, 0.5), 2.5)
  local slope, intercept = kit.fit ({ 3, 5, 7 }, { 1, 2, 3 })
  eq ({ slope, intercept }, { 2, 1 })
  eq (kit.math1 (math.abs).map ({ -3 }, 1, CTX), 3)
  eq (kit.text1 (string.upper).map ({ 'ab' }, 1, CTX), 'AB')
  ok (kit.is_weekend (kit.make_date (2026, 10, 3)), 'a Saturday')
  ok (not kit.is_weekend (kit.make_date (2026, 10, 5)), 'a Monday')
end)

-- Which categories each function module adds functions in.
local MODULES = {
  sheet_fn_math = { Math = true },
  sheet_fn_stats = { Statistics = true, Math = true },
  sheet_fn_logic_info = { Logic = true, Info = true },
  sheet_fn_text = { Text = true },
  sheet_fn_regex = { Text = true },
  sheet_fn_lookup = { Lookup = true },
  sheet_fn_date = { Date = true },
  sheet_fn_finance = { Financial = true, Date = true },
  sheet_fn_arrays = { Logic = true, Lookup = true, Math = true },
  sheet_fn_more = { Math = true, Text = true, Info = true, Lookup = true },
}

test (
  'each function module adds its own functions, and together they make the catalog',
  function ()
    local seen = {} ---@type table<string, string>
    local total = 0
    for name, categories in pairs (MODULES) do
      local add = require (name) --[[@as fun(kit: Sheet.FormulaKit)]]
      local own = setmetatable ({
        define = function (fn, category)
          ok (categories[category], name .. ' adds ' .. fn .. ' in ' .. category)
          ok (seen[fn] == nil, fn .. ' comes from one module only')
          seen[fn] = name
          total = total + 1
        end,
      }, { __index = kit })
      add (own --[[@as Sheet.FormulaKit]])
    end
    eq (total, #f.functions)
    for _, fn in ipairs (f.functions) do
      ok (seen[fn] ~= nil, fn .. ' comes from a function module')
    end
  end
)
