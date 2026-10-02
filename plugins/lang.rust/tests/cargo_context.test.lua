local context = require ('lib.cargo_context') --[[@as LangRust.CargoContextModule]]

local CARGO = table.concat ({
  '[package]',
  'name = "app"',
  '',
  '[dependencies]',
  'serde = "1.0"',
  'tokio = { version = "1.3", features = ["full"] }',
  'ra',
  '',
  '[dependencies.rand]',
  'version = "0.8"',
  'features = ["small_rng"]',
  '',
  "[target.'cfg(unix)'.dev-dependencies]",
  'libc = "0.2"',
}, '\r\n')

local lines = context.lines (CARGO)

---What is typed at the end of a line, counted from 0.
---@param line integer
---@return LangRust.CargoContext?
local function at_end (line)
  return context.at (lines, line, #lines[line + 1])
end

test ('lines splits on line breaks and drops carriage returns', function ()
  eq (context.lines ('a\r\nb\n\nc'), { 'a', 'b', '', 'c' })
  eq (lines[1], '[package]')
end)

test ('a crate name being typed in a dependencies table', function ()
  eq (at_end (6), { where = 'name', word = 'ra', from = 0 })
  eq (context.at (lines, 4, 3), { where = 'name', word = 'ser', from = 0 })
end)

test ('a version after the name, plain or in an inline table', function ()
  eq (
    context.at (lines, 4, 11),
    { where = 'version', crate = 'serde', word = '1.', from = 9 }
  )
  eq (
    context.at (lines, 5, 23),
    { where = 'version', crate = 'tokio', word = '1.', from = 21 }
  )
end)

test ('a version in a table for one crate', function ()
  eq (
    context.at (lines, 9, 13),
    { where = 'version', crate = 'rand', word = '0.', from = 11 }
  )
  eq (at_end (10), nil, 'features are not a version')
end)

test ('a target table with quotes still counts as dependencies', function ()
  eq (
    context.at (lines, 13, 10),
    { where = 'version', crate = 'libc', word = '0.', from = 8 }
  )
end)

test ('outside a dependencies table there is nothing to complete', function ()
  eq (at_end (1), nil, '[package]')
  eq (at_end (0), nil, 'a table header')
  eq (at_end (3), nil, 'the dependencies header itself')
  eq (context.at (lines, 99, 0), nil, 'past the end')
  eq (context.at ({ 'serde = "1"' }, 0, 9), nil, 'before any table')
end)
