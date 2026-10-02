-- Tests for the modules sheet_book reads files and makes its example with: sheet_json, the
-- JSON reader, and sheet_example, the data of the workbook written on first start.

local book_mod = require ('sheet_book') --[[@as Sheet.BookModule]]
local example = require ('sheet_example') --[[@as Sheet.ExampleModule]]
local json = require ('sheet_json') --[[@as Sheet.JsonModule]]

test ('sheet_book reads JSON through sheet_json', function ()
  ok (book_mod.parse_json == json.parse_json)
end)

test ('JSON text reads into Lua values', function ()
  eq (json.parse_json (' {"a": [1, 2.5, "x"], "b": {"c": true}} '), {
    a = { 1, 2.5, 'x' },
    b = { c = true },
  })
  eq (
    json.parse_json ('"tab\\tquote\\" slash\\/ \\u00e9"'),
    'tab\tquote" slash/ é'
  )
  -- A null in a list leaves no hole.
  eq (json.parse_json ('[1, null, 3]'), { 1, 3 })
  eq (json.parse_json ('false'), false)
end)

test ('text that is not JSON gives a message with the byte', function ()
  local value, problem = json.parse_json ('{"a": 1} x')
  eq (value, nil)
  eq (problem, 'There is more text after the data at byte 10.')
  value, problem = json.parse_json ('{"a" 1}')
  eq (value, nil)
  ok (
    type (problem) == 'string' and string.find (problem, 'byte') ~= nil,
    problem
  )
  eq ({ json.parse_json (string.rep ('[', 200)) }, {
    nil,
    'The data nests too deeply at byte 102.',
  })
end)

test (
  'the example is plain book data with a budget and an income sheet',
  function ()
    local data = example.data ()
    eq (data.version, 3)
    eq (#data.sheets, 2)
    eq (data.sheets[1].name, 'Budget')
    eq (data.sheets[2].name, 'Income')
    eq (data.sheets[1].cells.D5, '=C5-B5')
    ok (example.data () ~= data, 'a new table each time')
    local book = book_mod.example ()
    eq (book:names (), { 'Budget', 'Income' })
  end
)
