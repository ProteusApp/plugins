local actions = require ('lib.actions') --[[@as LangGitfiles.ActionsModule]]
local data = require ('lib.actions_data') --[[@as LangGitfiles.ActionsDataModule]]

---The labels of a completion list.
---@param items Proteus.CompletionItem[]
---@return table<string, Proteus.CompletionItem>
local function by_label (items)
  local out = {}
  for _, item in ipairs (items) do
    out[item.label] = item
  end
  return out
end

test ('an action goes in with its version', function ()
  local checkout = by_label (actions.action_items ())['actions/checkout']
  ok (checkout, 'actions/checkout is offered')
  eq (checkout.insert, 'actions/checkout@' .. checkout.detail)
  ok (checkout.documentation ~= '')
end)

test (
  'every bundled action names a repository, a version and what it does',
  function ()
    local seen = {}
    for _, a in ipairs (data.actions) do
      ok (a.repo:match ('^[%w_%.%-]+/[%w_%.%-]+'), a.repo)
      ok (a.version:match ('^[%w%.%-]+$'), a.repo .. ' version')
      ok (a.doc:match ('%.$'), a.repo .. ' doc ends a sentence')
      ok (not seen[a.repo:lower ()], a.repo .. ' is listed once')
      seen[a.repo:lower ()] = true
    end
    ok (#data.actions >= 20)
  end
)

test ('data.action finds an entry whatever the case', function ()
  eq (data.action ('Actions/Checkout').repo, 'actions/checkout')
  eq (data.action ('nobody/nothing'), nil)
end)

test ('the start of an expression offers contexts and functions', function ()
  local items = by_label (actions.expression_items (nil, {}))
  for _, name in ipairs ({
    'github',
    'env',
    'vars',
    'secrets',
    'inputs',
    'matrix',
    'steps',
    'needs',
    'runner',
    'job',
    'strategy',
  }) do
    ok (items[name], name .. ' is offered')
  end
  for _, name in ipairs ({
    'contains',
    'startsWith',
    'endsWith',
    'format',
    'join',
    'toJSON',
    'fromJSON',
    'hashFiles',
    'success',
    'always',
    'cancelled',
    'failure',
  }) do
    ok (items[name] and items[name].kind == 'function', name .. ' is offered')
  end
  eq (items.contains.insert, 'contains(')
  eq (items.always.insert, 'always()')
end)

test ('a context offers its properties', function ()
  local github = by_label (actions.expression_items ('github', {}))
  ok (github.ref and github.sha and github.event_name and github.ref_name)
  local runner = by_label (actions.expression_items ('runner', {}))
  ok (runner.os and runner.arch and runner.temp)
  eq (#actions.expression_items ('env', {}), 0)
end)

test ('steps and needs offer the ids the file defines', function ()
  local lines = {
    'jobs:',
    '  build:',
    '    steps:',
    '      - id: cache',
    '  test:',
    '    needs: build',
  }
  eq (
    by_label (actions.expression_items ('steps', lines)).cache.kind,
    'variable'
  )
  local jobs = by_label (actions.expression_items ('needs', lines))
  ok (jobs.build and jobs.test)
  local step = by_label (actions.expression_items ('steps.cache', lines))
  ok (step.outputs and step.outcome and step.conclusion)
  local need = by_label (actions.expression_items ('needs.build', lines))
  ok (need.outputs and need.result)
end)

test ('tag_names reads GitHub answers, newest first', function ()
  eq (
    actions.tag_names ({
      { name = 'v1.0.0' },
      { name = 'v2' },
      { name = 'v2.1.0' },
      { nope = true },
    }),
    { 'v2', 'v2.1.0', 'v1.0.0' }
  )
  eq (actions.tag_names ('not a list'), {})
end)

test ('every property and function says what it does', function ()
  for context, list in pairs (data.properties) do
    for _, p in ipairs (list) do
      ok (p.doc ~= '', context .. '.' .. p.name)
    end
  end
  for _, f in ipairs (data.functions) do
    ok (f.signature:sub (1, #f.name + 1) == f.name .. '(', f.name)
  end
end)
