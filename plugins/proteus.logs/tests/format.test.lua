local lf = require ('log_filter') --[[@as Logs.FilterModule]]
local lfmt = require ('log_format') --[[@as Logs.FormatModule]]

---@param n integer
---@param text string
---@return Logs.Line
local function line (n, text)
  return lf.make_line (n, text)
end

test ('log_filter hands out log_format', function ()
  ok (lf.compile_format == lfmt.compile)
  ok (lf.apply_format == lfmt.apply)
  ok (lf.sort_lines == lfmt.sort_lines)
  ok (lf.clean_formats == lfmt.clean_formats)
end)

test (
  'json_fields reads the object a line ends with, nested keys and all',
  function ()
    local fields, keys = lfmt.json_fields (
      '12:00 {"level":"warn","msg":"a \\"b\\"\\u00e9","user":{"id":7},"tags":[1,{"x":2}],"ok":true,"gone":null}'
    )
    eq (keys, { 'level', 'msg', 'user.id', 'tags', 'ok', 'gone' })
    eq (fields, {
      level = 'warn',
      msg = 'a "b"é',
      ['user.id'] = '7',
      tags = '[1,{"x":2}]',
      ok = 'true',
      gone = '',
    })
    eq (lfmt.json_fields ('no json here'), nil)
    eq (lfmt.json_fields ('{"a":1} and more'), nil)
    eq ((lfmt.json_fields ('{broken {"a":-1.5e3}')), { a = '-1.5e3' })
  end
)

test ('logfmt_fields reads key=value pairs, quoted values too', function ()
  local fields, keys = lfmt.logfmt_fields (
    'ts=2024-03-01T12:00:00Z level=info msg="disk \\"sda\\" full" took=3ms bare word'
  )
  eq (keys, { 'ts', 'level', 'msg', 'took' })
  eq (fields, {
    ts = '2024-03-01T12:00:00Z',
    level = 'info',
    msg = 'disk "sda" full',
    took = '3ms',
  })
  eq (lfmt.logfmt_fields ('GET /a?b=c HTTP/1.1'), nil)
end)

test ('compile reads a regular expression with named groups', function ()
  local parser = assert (lfmt.compile ({
    name = 'App',
    kind = 'regex',
    pattern = '^(?<time>\\S+) (?<level>\\w+) (?<msg>.*)$',
    fields = {},
  }))
  eq (parser.fields, { 'time', 'level', 'msg' })
  eq (parser.extract ('12:00 WARN slow disk'), {
    time = '12:00',
    level = 'WARN',
    msg = 'slow disk',
  })
  eq (parser.extract ('nothing'), nil)
  local _, none = lfmt.compile ({
    name = 'x',
    kind = 'regex',
    pattern = '\\d+',
    fields = {},
  })
  ok (none and none:find ('names no group', 1, true), none)
  local _, broken = lfmt.compile ({
    name = 'x',
    kind = 'regex',
    pattern = '(?<a>',
    fields = {},
  })
  ok (broken and broken:find ('not valid', 1, true), broken)
  local _, missing = lfmt.compile ({
    name = 'x',
    kind = 'regex',
    pattern = '(?<a>x)',
    fields = { 'b' },
  })
  eq (missing, 'The regular expression has no group named b.')
  local _, empty = lfmt.compile ({ name = 'j', kind = 'json', fields = {} })
  eq (empty, 'Name at least one field to show.')
end)

test ('apply sets the fields, and a level field sets the level', function ()
  local parser = assert (lfmt.compile ({
    name = 'App',
    kind = 'regex',
    pattern = '^\\[(?<severity>\\w+)\\] (?<msg>.*)$',
    fields = {},
  }))
  local l = line (1, '[crit] something info-ish')
  lfmt.apply (l, parser)
  eq (l.level, 'error')
  eq (l.fields.msg, 'something info-ish')
  lfmt.apply (l, nil)
  eq (l.fields, nil)
  eq (l.level, lf.detect_level ('[crit] something info-ish'))
end)

test ('discover suggests the most common fields first', function ()
  local lines = {
    line (1, '{"msg":"a","level":"info"}'),
    line (2, '{"level":"warn","code":3}'),
    line (3, 'plain'),
  }
  eq (lfmt.discover (lines, 'json', 5), { 'level', 'msg', 'code' })
  eq (lfmt.discover (lines, 'json', 1), { 'level' })
  eq (lfmt.discover ({ line (1, 'a=1 b=2') }, 'logfmt', 5), { 'a', 'b' })
end)

test ('clean_formats keeps well-formed formats, one to a name', function ()
  eq (lfmt.clean_formats ('x'), {})
  eq (
    lfmt.clean_formats ({
      { name = 'A', kind = 'json', fields = { 'level', 3, '' } },
      { name = 'A', kind = 'logfmt', fields = {} },
      { name = 'R', kind = 'regex' },
      { name = 'R', kind = 'regex', pattern = '(?<a>x)' },
      { name = ' ', kind = 'json' },
      { name = 'B', kind = 'yaml' },
    }),
    {
      { name = 'A', kind = 'json', fields = { 'level' } },
      { name = 'R', kind = 'regex', pattern = '(?<a>x)', fields = {} },
    }
  )
  eq (
    lfmt.split_names ('level, msg  user.id,level'),
    { 'level', 'msg', 'user.id' }
  )
end)

test (
  'sort_lines sorts numbers by size, text by letter, and keeps ties in order',
  function ()
    local lines = {} ---@type Logs.Line[]
    for i, v in ipairs ({ '10', '9', 'b', 'A', '9' }) do
      lines[i] = line (i, 'x')
      lines[i].fields = { v = v }
    end
    lines[6] = line (6, 'no field')
    ---@param list Logs.Line[]
    ---@return integer[]
    local function ns (list)
      local out = {} ---@type integer[]
      for i, l in ipairs (list) do
        out[i] = l.n
      end
      return out
    end
    eq (ns (lfmt.sort_lines (lines, 'v', false)), { 2, 5, 1, 4, 3, 6 })
    eq (ns (lfmt.sort_lines (lines, 'v', true)), { 3, 4, 1, 2, 5, 6 })
  end
)

test ('widths fit the widest value, up to 40 characters', function ()
  local a, b = line (1, 'a'), line (2, 'b')
  a.fields = { k = 'é', msg = string.rep ('x', 99) }
  b.fields = { k = 'abcd' }
  eq (lfmt.widths ({ a, b }, { 'k', 'msg' }), { 4, 40 })
  eq (lfmt.text_width ('héé'), 3)
end)

test (
  'field:value tests a field, and -field:value hides what it finds',
  function ()
    local known = { status = 'status', user = 'User', msg = 'msg' }
    local l = line (1, 'GET /a')
    l.fields = { status = '503', User = 'Ann Lee', msg = 'disk full' }
    ---@param text string
    ---@return boolean
    local function passes (text)
      return lf.matches_line (l, lf.parse_query (text, known))
    end
    ok (passes ('status:50'))
    ok (passes ('status:>=500'))
    ok (not passes ('status:<500'))
    ok (passes ('status:=503'))
    ok (not passes ('status:=50'))
    ok (passes ('user:"ann lee"'))
    ok (passes ('msg:"disk full" get'))
    ok (not passes ('-user:ann'))
    ok (passes ('-user:bob'))
    ok (not passes ('missing:x'), 'a name that is no field is a word')
    ok (passes ('user:'), 'a half-typed test hides nothing')
    local q = lf.parse_query ('user:"ann lee" rest', known)
    eq (#q.fields, 1)
    eq (q.terms, { 'rest' })
    eq (lf.parse_query ('status:!x', known).problem ~= nil, false)
    ok (
      lf.parse_query ('status:<>5', known).problem,
      'a test it cannot read says so'
    )
    local plain = line (2, 'status:503 here')
    ok (
      lf.matches_line (plain, lf.parse_query ('status:503')),
      'with no such field it stays a word'
    )
  end
)

test (
  'row_html adds a cell for each column, and head_html names them',
  function ()
    local l = line (3, 'hello')
    l.id = 9
    l.fields = { level = 'warn', msg = '<b>' }
    local cols = { names = { 'level', 'msg' }, widths = { 5, 6 } }
    local html = lf.row_html (l, lf.parse_query (''), nil, cols)
    ok (
      html:find (
        '<span class="logs-n">3</span><span class="logs-f" style="width:5ch">warn</span><span class="logs-f" style="width:6ch">&lt;b&gt;</span><span class="logs-t">hello</span>',
        1,
        true
      ),
      html
    )
    local head = lf.head_html (cols, { field = 'msg', desc = true })
    ok (head:find ('data-item="col:level"', 1, true), head)
    ok (head:find ('class="logs-hcol on" data-item="col:msg"', 1, true), head)
    ok (head:find ('msg ▼', 1, true), head)
  end
)
