local ctl = require ('sheet_ctl') --[[@as Sheet.CtlModule]]

test ('the event hub calls listeners in order until they stop', function ()
  local on, emit = ctl.events ()
  local heard = {} ---@type string[]
  local off_a = on ('selection', function (row, col)
    heard[#heard + 1] = 'a' .. row .. ',' .. col
  end)
  on ('selection', function (row, col)
    heard[#heard + 1] = 'b' .. row .. ',' .. col
  end)
  emit ('selection', 2, 3)
  off_a ()
  emit ('selection', 4, 5)
  emit ('book')
  eq (heard, { 'a2,3', 'b2,3', 'b4,5' })
end)

test ('a listener may stop listening while the event runs', function ()
  local on, emit = ctl.events ()
  local heard = {} ---@type string[]
  local off = nil ---@type fun()?
  off = on ('changed', function ()
    heard[#heard + 1] = 'once'
    if off then
      off ()
    end
  end)
  on ('changed', function ()
    heard[#heard + 1] = 'always'
  end)
  emit ('changed')
  emit ('changed')
  eq (heard, { 'once', 'always', 'always' })
end)
