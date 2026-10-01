local context = require ('lib.actions_context') --[[@as LangGitfiles.ActionsContextModule]]

---Where the cursor is, with `|` marking it in one line.
---@param line string
---@return LangGitfiles.ActionsContext?
local function at (line)
  local column = line:find ('|', 1, true) - 1
  local text = line:sub (1, column) .. line:sub (column + 2)
  return context.at ({ text }, 0, column)
end

test ('an action name after uses:', function ()
  eq (
    at ('      - uses: actions/che|'),
    { where = 'action', word = 'actions/che', from = 14 }
  )
  eq (at ('    uses: |'), { where = 'action', word = '', from = 10 })
end)

test ('an action name in quotes', function ()
  eq (
    at ('  - uses: "docker/lo|'),
    { where = 'action', word = 'docker/lo', from = 11 }
  )
end)

test ('a version after @', function ()
  eq (at ('      - uses: actions/checkout@v|'), {
    where = 'version',
    repo = 'actions/checkout',
    word = 'v',
    from = 31,
  })
  eq (at ('  - uses: actions/cache@|'), {
    where = 'version',
    repo = 'actions/cache',
    word = '',
    from = 24,
  })
end)

test ('a version of an action inside a repository', function ()
  eq (at ('  - uses: github/codeql-action/init@v|'), {
    where = 'version',
    repo = 'github/codeql-action',
    word = 'v',
    from = 36,
  })
end)

test ('local actions and Docker images get nothing', function ()
  eq (at ('  - uses: ./.github/actions/bu|'), nil)
  eq (at ('  - uses: docker://alpine:3|'), nil)
end)

test ('a context at the start of an expression', function ()
  eq (
    at ('        run: echo ${{ gith|'),
    { where = 'expression', word = 'gith', from = 22 }
  )
  eq (
    at ('        run: echo ${{ |'),
    { where = 'expression', word = '', from = 22 }
  )
end)

test ('a property after a context and a dot', function ()
  eq (at ('    if: ${{ github.event_|'), {
    where = 'expression',
    object = 'github',
    word = 'event_',
    from = 19,
  })
  eq (at ('  key: ${{ runner.|'), {
    where = 'expression',
    object = 'runner',
    word = '',
    from = 18,
  })
end)

test ('a step output path keeps every name before the last dot', function ()
  eq (at ('  x: ${{ steps.build.out|'), {
    where = 'expression',
    object = 'steps.build',
    word = 'out',
    from = 21,
  })
  eq (at ('  x: ${{ strategy.job-in|'), {
    where = 'expression',
    object = 'strategy',
    word = 'job-in',
    from = 18,
  })
end)

test ('a name after an operator or inside a function call', function ()
  eq (at ("  if: ${{ github.ref == 'main' && runner.o|"), {
    where = 'expression',
    object = 'runner',
    word = 'o',
    from = 41,
  })
  eq (at ('  key: ${{ hashFiles(gith|'), {
    where = 'expression',
    word = 'gith',
    from = 21,
  })
end)

test ('an if: condition is an expression without braces', function ()
  eq (at ('    if: succ|'), { where = 'expression', word = 'succ', from = 8 })
  eq (at ('  - if: github.|'), {
    where = 'expression',
    object = 'github',
    word = '',
    from = 15,
  })
end)

test ('nothing inside quoted text or after the expression closes', function ()
  eq (at ("  if: ${{ github.ref == 'refs/he|"), nil)
  eq (at ('  run: echo ${{ github.sha }} and m|'), nil)
  eq (at ('  run: echo plain te|'), nil)
end)

test ('a second expression on the line counts', function ()
  eq (at ('  run: ${{ env.A }}-${{ matrix.|'), {
    where = 'expression',
    object = 'matrix',
    word = '',
    from = 31,
  })
end)

test ('nothing in a comment', function ()
  eq (at ('  # uses: actions/che|'), nil)
end)

test ('nothing past the end of the file', function ()
  eq (context.at ({ 'a' }, 3, 0), nil)
end)

test ('lines splits on line breaks and drops carriage returns', function ()
  eq (context.lines ('a\r\nb\n'), { 'a', 'b', '' })
end)

local WORKFLOW = context.lines ([[
name: CI
on: push
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7
      - id: setup
        uses: actions/setup-node@v7
      - name: Test
        id: test-run
        run: npm test
  # a comment between jobs
  deploy-site:
    needs: build
    steps:
      - id: setup
        run: echo again
env:
  A: 1
]])

test ('step_ids finds each id once, in order', function ()
  eq (context.step_ids (WORKFLOW), { 'setup', 'test-run' })
end)

test ('job_ids finds the keys under jobs: only', function ()
  eq (context.job_ids (WORKFLOW), { 'build', 'deploy-site' })
  eq (context.job_ids ({ 'name: x' }), {})
end)

test (
  'sort_tags puts the newest version first, a major tag before its releases',
  function ()
    eq (
      context.sort_tags ({
        'v4.1.0',
        'v4',
        'v5.0.0-beta',
        'v4.10.2',
        'latest',
        'v5',
        'v5.0.0',
        'v4.2',
        '3.0.0',
      }),
      {
        'v5',
        'v5.0.0',
        'v5.0.0-beta',
        'v4',
        'v4.10.2',
        'v4.2',
        'v4.1.0',
        '3.0.0',
        'latest',
      }
    )
  end
)
