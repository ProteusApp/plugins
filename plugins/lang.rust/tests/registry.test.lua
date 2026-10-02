local registry = require ('lib.registry') --[[@as LangRust.RegistryModule]]

test ('index paths follow the sparse index layout', function ()
  eq (registry.index_path ('a'), '1/a')
  eq (registry.index_path ('io'), '2/io')
  eq (registry.index_path ('syn'), '3/s/syn')
  eq (registry.index_path ('serde'), 'se/rd/serde')
  eq (registry.index_path ('Serde_JSON'), 'se/rd/serde_json')
end)

local INDEX = table.concat ({
  '{"name":"x","vers":"0.1.0","yanked":false}',
  '{"name":"x","vers":"0.2.0","yanked":true}',
  '{"name":"x","vers":"1.0.0-beta.1","yanked":false}',
  '{"name":"x","vers":"1.0.0","yanked":false}',
  '{"name":"x", "vers" : "1.1.0", "yanked" : false}',
  'not a record',
}, '\n')

test ('versions come newest first, without yanked ones', function ()
  eq (registry.versions (INDEX, false), { '1.1.0', '1.0.0', '0.1.0' })
end)

test ('a pre-release comes only when asked for', function ()
  eq (
    registry.versions (INDEX, true),
    { '1.1.0', '1.0.0', '1.0.0-beta.1', '0.1.0' }
  )
  eq (registry.versions ('', true), {})
end)

---A fake app whose fetches wait until the test answers them.
---@return Proteus.App app
---@return { url: string, cb: fun(reply: table?) }[] asked
local function fake_app ()
  local asked = {} ---@type { url: string, cb: fun(reply: table?) }[]
  local app = {
    net = {
      fetch = function (req, cb)
        asked[#asked + 1] = { url = req.url, cb = cb }
      end,
    },
    json = {
      decode = function (body)
        assert (body == 'CRATES', 'unexpected body ' .. tostring (body))
        return {
          crates = {
            {
              name = 'serde',
              description = 'Serialize',
              max_stable_version = '1.0.200',
            },
            { name = 'serde_json', newest_version = '1.0.1' },
          },
        }
      end,
    },
    try = function (fn, ...)
      return fn (...)
    end,
  }
  return app, --[[@as Proteus.App]]
    asked
end

---A document whose text is a Cargo.toml.
---@param text string
---@return Proteus.DocInfo
local function doc (text)
  local d = {
    text = function ()
      return text
    end,
  }
  return d --[[@as Proteus.DocInfo]]
end

test (
  'a crate name searches crates.io once, and both callers get the answer',
  function ()
    local app, asked = fake_app ()
    local complete = registry.new (app)
    local got = {} ---@type table[]
    local cargo = doc ('[dependencies]\nser')
    for _ = 1, 2 do
      complete (cargo, { line = 1, character = 3 }, function (result)
        got[#got + 1] = result
      end)
    end
    eq (#asked, 1, 'one request for both')
    ok (asked[1].url:find ('crates.io/api/v1/crates', 1, true))
    ok (asked[1].url:find ('q=ser', 1, true))
    asked[1].cb ({ status = 200, body = 'CRATES' })
    eq (#got, 2)
    eq (got[1].from, 0)
    eq (got[1].items[1], {
      label = 'serde',
      kind = 'module',
      detail = '1.0.200',
      documentation = 'Serialize',
      insert = 'serde = "1.0.200"',
    })
    eq (got[1].items[2].insert, 'serde_json = "1.0.1"')

    -- The answer is kept, so the next completion asks nothing.
    complete (cargo, { line = 1, character = 3 }, function () end)
    eq (#asked, 1)
  end
)

test ('one letter is too few to search', function ()
  local app, asked = fake_app ()
  local answer = 'unset' ---@type any
  registry.new (app) (
    doc ('[dependencies]\ns'),
    { line = 1, character = 1 },
    function (r)
      answer = r
    end
  )
  eq (asked, {})
  eq (answer, nil)
end)

test ('versions come from the index, newest short version first', function ()
  local app, asked = fake_app ()
  local got ---@type table?
  registry.new (app) (
    doc ('[dependencies]\nx = "1'),
    { line = 1, character = 6 },
    function (r)
      got = r
    end
  )
  eq (asked[1].url, 'https://index.crates.io/1/x')
  asked[1].cb ({ status = 200, body = INDEX })
  local result = assert (got, 'no answer')
  eq (result.from, 5)
  eq (
    result.items[1],
    { label = '1.1', kind = 'constant', detail = 'newest 1.1.0' }
  )
  eq (result.items[2], { label = '1.1.0', kind = 'constant' })
  eq (#result.items, 4)
end)

test ('a failed request is tried again next time', function ()
  local app, asked = fake_app ()
  local complete = registry.new (app)
  local got = {} ---@type table[]
  local cargo = doc ('[dependencies]\nx = "')
  complete (cargo, { line = 1, character = 5 }, function (r)
    got[#got + 1] = r
  end)
  asked[1].cb ({ status = 503, body = '' })
  eq (got[1].items, {}, 'nothing to offer')
  complete (cargo, { line = 1, character = 5 }, function () end)
  eq (#asked, 2, 'asked again')
end)
