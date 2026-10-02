-- Runs the API client against a stand-in for the app: elements that keep their handlers,
-- files in memory, and an app.net.fetch the test answers. The `http` service comes from the
-- app's proteus.lib.http beside this registry, so these tests run only where the app is
-- checked out at ../app, as it is for the app's own checks.

local HTTP_DIR = '../app/lua/plugins/core/proteus.lib.http/'

---@param path string
---@return string?
local function app_file (path)
  local found, text = pcall (read, HTTP_DIR .. path)
  return found and text or nil
end

---The `http` service, loaded from the app with its own modules.
---@return Proteus.Http?
local function load_http ()
  if not app_file ('http.lua') then
    return nil
  end
  local loaded = {} ---@type table<string, any>
  -- The modules run with the standard library only, as a plugin's do.
  local env = {
    string = string,
    table = table,
    math = math,
    utf8 = utf8,
    os = os,
    tostring = tostring,
    tonumber = tonumber,
    type = type,
    pairs = pairs,
    ipairs = ipairs,
    next = next,
    error = error,
    pcall = pcall,
    select = select,
    assert = assert,
    setmetatable = setmetatable,
    getmetatable = getmetatable,
    rawget = rawget,
    rawequal = rawequal,
  } ---@type table<string, any>
  ---@param name string
  ---@return any
  local function req (name)
    if loaded[name] == nil then
      local chunk = assert (
        load (assert (app_file (name .. '.lua')), '=' .. name, 't', env)
      )
      loaded[name] = chunk ()
    end
    return loaded[name]
  end
  env.require = req
  return req ('http')
end

local http = load_http ()

---@class Fake.El
---@field props table<string, any>
---@field handlers table<string, fun(ev: table): any>
---@field val string
---@field code string
---@field visible boolean
---@field shown_text string
---@field classes table<string, boolean>
local El = {}

local el_meta = {
  __index = function (_, key)
    return El[key] or function () end
  end,
}

---@param props? table<string, any>
---@return Fake.El
local function element (props)
  local p = type (props) == 'table' and props or {}
  return setmetatable ({
    props = p,
    handlers = {},
    val = '',
    code = p.text or '',
    visible = true,
    shown_text = '',
    classes = {},
  }, el_meta)
end

function El:on (name, fn)
  self.handlers[name] = fn
end
function El:value (v)
  if v == nil then
    return self.val
  end
  self.val = v
end
function El:show (on)
  self.visible = on ~= false
end
function El:text (t)
  self.shown_text = tostring (t)
end
function El:html (h)
  self.shown_text = tostring (h)
end
function El:class (name, on)
  self.classes[name] = on ~= false
end
function El:rect ()
  return { x = 0, y = 0, w = 600, h = 400 }
end
function El:get ()
  return 0
end
function El:widget (method, arg)
  if method == 'get_text' then
    return self.code
  elseif method == 'set_text' or method == 'replace_text' then
    self.code = arg
  end
end
-- The kernel refuses a restricted plugin the DOM methods that reach past its elements.
function El:call (method)
  if method == 'insertAdjacentHTML' or method == 'setAttribute' then
    error ('a restricted plugin may not call ' .. method)
  end
end
---Runs the element's handler for an event.
---@param name string
---@param ev? table
function El:fire (name, ev)
  local fn = self.handlers[name]
  assert (fn, 'no ' .. name .. ' handler')
  return fn (ev or {})
end
---Types into a code widget, as its own change handler hears it.
---@param text string
function El:type_code (text)
  self.code = text
  self.props.on_change ()
end

---A stand-in app. `made` holds every element by its class, in the order made.
---@return table app
---@return table world What the test reads and answers.
local function fake_app ()
  local world = {
    made = {}, ---@type table<string, Fake.El[]>
    files = {}, ---@type table<string, string>
    reads = 0,
    fetches = {}, ---@type { request: Proteus.HttpRequest, cb: fun(reply: any, err: any), cancelled: boolean }[]
    commands = {}, ---@type table<string, Proteus.CommandSpec>
    said = {}, ---@type string[]
    timers = {}, ---@type fun()[]
    picks = {}, ---@type Proteus.FileGrant[]
    grant_text = {}, ---@type table<string, string>
    now = 1000000,
  }
  local store = {} ---@type table<string, any>

  local ui = setmetatable ({}, {
    __index = function (_, name)
      return function (a, b)
        local props = type (a) == 'table' and a or b
        if name == 'widget' then
          props = b
        end
        local el = element (props)
        if name == 'widget' then
          local key = 'widget:' .. tostring (a)
          world.made[key] = world.made[key] or {}
          table.insert (world.made[key], el)
        end
        local class = type (props) == 'table' and props.class or nil
        if type (class) == 'string' then
          for c in class:gmatch ('%S+') do
            world.made[c] = world.made[c] or {}
            table.insert (world.made[c], el)
          end
        end
        return el
      end
    end,
  })

  ---@param path string
  ---@return boolean
  local function is_dir (path)
    local prefix = path .. '/'
    for p in pairs (world.files) do
      if p:sub (1, #prefix) == prefix then
        return true
      end
    end
    return false
  end

  local app = {
    platform = 'desktop',
    id = 'proteus.api',
    log = function () end,
    warn = function (...)
      world.said[#world.said + 1] = table.concat ({ ... }, ' ')
    end,
    util = {
      escape = function (t)
        return (tostring (t):gsub ('[<>&"]', ''))
      end,
      icon = function ()
        return ''
      end,
      now = function ()
        return world.now
      end,
    },
    store = {
      get = function (k, default)
        if store[k] == nil then
          return default
        end
        return store[k]
      end,
      set = function (k, v)
        store[k] = v
      end,
    },
    timer = {
      after = function (_, fn)
        world.timers[#world.timers + 1] = fn
        return function () end
      end,
      every = function () end,
    },
    dom = {
      on_global = function ()
        return function () end
      end,
    },
    system = {
      clipboard = function (t)
        world.clipboard = t
      end,
    },
    on = function () end,
    dispose = function () end,
    fs = {
      read = function (path)
        world.reads = world.reads + 1
        return world.files[path]
      end,
      write = function (path, text)
        world.files[path] = text
      end,
      exists = function (path)
        return world.files[path] ~= nil or is_dir (path)
      end,
      mkdir = function () end,
      remove = function (path)
        world.files[path] = nil
      end,
      rename = function (from, to)
        world.files[to] = world.files[from]
        world.files[from] = nil
      end,
      list = function (dir)
        local out, seen = {}, {}
        local prefix = dir .. '/'
        for p in pairs (world.files) do
          if p:sub (1, #prefix) == prefix then
            local rest = p:sub (#prefix + 1)
            local name = rest:match ('^[^/]+')
            if name and not seen[name] then
              seen[name] = true
              out[#out + 1] = {
                name = name,
                path = prefix .. name,
                dir = rest:find ('/', 1, true) ~= nil,
              }
            end
          end
        end
        table.sort (out, function (x, y)
          return x.name < y.name
        end)
        return out
      end,
    },
    net = {
      fetch = function (request, cb)
        local call = { request = request, cb = cb, cancelled = false }
        world.fetches[#world.fetches + 1] = call
        return {
          cancel = function ()
            if not call.cancelled then
              call.cancelled = true
              cb (nil, 'cancelled')
            end
          end,
          done = function ()
            return call.cancelled
          end,
        }
      end,
    },
    grants = {
      open = function (_, cb)
        cb ({ table.remove (world.picks, 1) })
      end,
      read = function (id, cb)
        cb (world.grant_text[id])
      end,
      forget = function () end,
    },
  }
  local commands = {
    register = function (spec)
      world.commands[spec.id] = spec
    end,
    run = function () end,
  }
  local services = {
    ui = ui,
    http = http,
    views = {
      add = function ()
        return { remove = function () end }
      end,
      show = function () end,
    },
    commands = commands,
    status = {
      add = function ()
        return { set = function () end }
      end,
    },
    notify = {
      info = function (t)
        world.said[#world.said + 1] = t
      end,
      warn = function (t)
        world.said[#world.said + 1] = t
      end,
      error = function (t)
        world.said[#world.said + 1] = t
      end,
    },
    tabs = {
      open = function ()
        return {
          set_dirty = function () end,
          is_active = function ()
            return true
          end,
          focus = function () end,
        }
      end,
    },
  }
  app.use = function (name)
    return services[name]
  end
  app.try_use = function (name)
    return services[name]
  end
  return app, world
end

---Starts the client in a stand-in app.
---@return table world
local function start ()
  local app, world = fake_app ()
  local plugin = require ('init') --[[@as Proteus.Plugin]]
  plugin.activate (app)
  return world
end

---@param world table
---@param id string
local function run (world, id)
  world.commands[id].run ()
end

---@param world table
---@param class string
---@param n? integer
---@return Fake.El
local function find (world, class, n)
  local list = world.made[class]
  assert (list, 'no element of the class ' .. class)
  return list[n or 1]
end

---@param world table
---@param url string
local function new_request (world, url)
  run (world, 'api.new')
  find (world, 'api-url'):fire ('input', { value = url })
end

---@param world table
---@param mode string
local function auth_mode (world, mode)
  find (world, 'api-modes', 2):fire ('click', { item = mode })
end

---@param world table
---@param class string
---@param n integer
---@param text string
local function type_into (world, class, n, text)
  find (world, class, n):fire ('input', { value = text })
end

if not http then
  test ('the client tests need the app at ../app', function ()
    ok (true)
  end)
  return
end

test ('GraphQL goes out as JSON, and the answer keeps its timing', function ()
  local world = start ()
  new_request (world, 'https://api.x.io/graphql')
  find (world, 'api-method'):fire ('change', { value = 'POST' })
  find (world, 'api-modes', 1):fire ('click', { item = 'graphql' })
  -- The body editor and the variables editor are the first two code widgets.
  find (world, 'widget:code', 1):type_code ('query ($id: ID!) { pet(id: $id) }')
  find (world, 'widget:code', 2):type_code ('{ "id": 7 }')
  run (world, 'api.send')
  local call = world.fetches[1]
  ok (call, 'the request went out')
  eq (call.request.method, 'POST')
  eq (
    call.request.body,
    '{"query":"query ($id: ID!) { pet(id: $id) }","variables":{ "id": 7 }}'
  )
  eq (call.request.headers['Content-Type'], 'application/json')
  call.cb ({
    status = 200,
    headers = { ['content-type'] = 'application/json' },
    header_list = { { name = 'content-type', value = 'application/json' } },
    body = '{"data":{}}',
    encoding = 'text',
    size = 11,
    url = 'https://api.x.io/graphql',
    redirects = 0,
    ms = 42,
  })
  local status = find (world, 'api-sum')
  ok (status.shown_text:find ('200 OK', 1, true), status.shown_text)
  ok (status.shown_text:find ('42 ms', 1, true), status.shown_text)
end)

test ('Cancel stops the request itself', function ()
  local world = start ()
  new_request (world, 'https://slow.x.io')
  run (world, 'api.send')
  run (world, 'api.send')
  eq (world.fetches[1].cancelled, true)
  ok (find (world, 'api-hint').shown_text:find ('Cancelled', 1, true))
end)

test ('Digest answers the challenge in a second request', function ()
  local world = start ()
  new_request (world, 'https://x.io/private?a=1')
  auth_mode (world, 'digest')
  type_into (world, 'api-mono', 2, 'Mufasa')
  type_into (world, 'api-mono', 3, 'Circle of Life')
  run (world, 'api.send')
  eq (world.fetches[1].request.headers.Authorization, nil)
  world.fetches[1].cb ({
    status = 401,
    headers = {
      ['www-authenticate'] = 'Digest realm="r", nonce="n", qop="auth"',
    },
    body = '',
  })
  local again = world.fetches[2]
  ok (again, 'the request went again')
  local header = again.request.headers.Authorization
  ok (header and header:find ('^Digest username="Mufasa"'), header)
  ok (header and header:find ('uri="/private?a=1"', 1, true), header)
  again.cb ({ status = 200, headers = {}, body = 'ok' })
  ok (find (world, 'api-sum').shown_text:find ('200 OK', 1, true))
end)

test ('OAuth 2 gets a token once and keeps it', function ()
  local world = start ()
  new_request (world, 'https://api.x.io/reports')
  auth_mode (world, 'oauth2')
  for _, el in ipairs (world.made['api-mono']) do
    if el.props.placeholder == 'https://auth.example.com/oauth/token' then
      el:fire ('input', { value = 'https://id.x.io/token' })
    elseif el.props.placeholder == 'Client id, or {{client_id}}' then
      el:fire ('input', { value = 'app' })
    end
  end
  run (world, 'api.send')
  local ask = world.fetches[1]
  eq (ask.request.url, 'https://id.x.io/token')
  eq (ask.request.body, 'grant_type=client_credentials&client_id=app')
  ask.cb ({
    status = 200,
    headers = {},
    body = '{"access_token":"T1","expires_in":3600}',
  })
  eq (world.fetches[2].request.headers.Authorization, 'Bearer T1')
  world.fetches[2].cb ({ status = 200, headers = {}, body = '' })
  run (world, 'api.send')
  eq (#world.fetches, 3, 'the kept token goes again with no new ask')
  eq (world.fetches[3].request.headers.Authorization, 'Bearer T1')
end)

test ('From folder uses the sign-in in the folder file', function ()
  local world = start ()
  world.files['data/proteus.api/.folder.json'] =
    http.encode_folder (http.normalize_auth ({ mode = 'bearer', token = 'F' }))
  new_request (world, 'https://x.io')
  auth_mode (world, 'inherit')
  run (world, 'api.send')
  eq (world.fetches[1].request.headers.Authorization, 'Bearer F')
end)

test (
  'a picked file goes by its id, and a missing one stops the send',
  function ()
    local world = start ()
    new_request (world, 'https://x.io/up')
    find (world, 'api-method'):fire ('change', { value = 'PUT' })
    find (world, 'api-modes', 1):fire ('click', { item = 'file' })
    run (world, 'api.send')
    eq (#world.fetches, 0)
    ok (find (world, 'api-error').shown_text:find ('Pick the file', 1, true))
    world.picks = { { id = 'f4', name = 'cat.png', mode = 'read' } }
    for _, el in ipairs (world.made['api-small']) do
      if el.props[1] == 'Pick File…' then
        el:fire ('click')
      end
    end
    run (world, 'api.send')
    eq (world.fetches[1].request.file, 'f4')
    eq (world.fetches[1].request.headers['Content-Type'], 'image/png')
  end
)

test (
  'Import Collection writes requests, folder sign-ins and an environment',
  function ()
    local world = start ()
    world.picks = { { id = 'f1', name = 'pets.yaml', mode = 'read' } }
    world.grant_text.f1 = [[
openapi: 3.0.0
info: { title: Pets }
servers: [{ url: 'https://pets.x.io' }]
security: [{ key: [] }]
components:
  securitySchemes:
    key: { type: apiKey, in: header, name: X-Key }
paths:
  /pets:
    get: { summary: List pets, tags: [pets] }
]]
    run (world, 'api.import')
    local saved = world.files['data/proteus.api/Pets/pets/List pets.json']
    ok (saved, 'the request was written')
    local folder = world.files['data/proteus.api/Pets/.folder.json']
    eq (http.parse_folder (folder).key, 'X-Key')
    local said = table.concat (world.said, '\n')
    ok (said:find ('Imported 1 request into "Pets".', 1, true), said)

    world.picks = { { id = 'f2', name = 'old.json', mode = 'read' } }
    world.grant_text.f2 =
      '{ "swagger": "2.0", "info": { "title": "Pets" }, "paths": { "/a": { "get": {} } } }'
    run (world, 'api.import')
    ok (
      world.files['data/proteus.api/Pets copy/GET a.json'],
      'a second import gets its own folder'
    )
    local envs = assert (
      http.parse_envs (world.files['data/proteus.api/environments.json'])
    )
    eq (envs.environments['Pets copy'], { base_url = 'http://localhost' })
  end
)

test ('searching the list reads no file again', function ()
  local world = start ()
  for i = 1, 5 do
    world.files['data/proteus.api/r' .. i .. '.json'] = http.encode_request (
      http.normalize ({ name = 'r' .. i, url = 'https://x.io/' .. i })
    )
  end
  local search = find (world, 'api-search')
  search:fire ('input', { value = 'r' })
  local before = world.reads
  search:fire ('input', { value = 'r1' })
  search:fire ('input', { value = 'r12' })
  eq (world.reads, before)
end)

test ('typing in the blank row of a grid adds a row', function ()
  local world = start ()
  new_request (world, 'https://x.io')
  local grid = find (world, 'api-kv', 2)
  grid:fire ('input', { item = '1:key', value = 'Accept' })
  grid:fire ('input', { item = '1:value', value = 'text/csv' })
  grid:fire ('input', { item = '2:key', value = 'X-Two' })
  run (world, 'api.send')
  eq (world.fetches[1].request.headers.Accept, 'text/csv')
  eq (world.fetches[1].request.headers['X-Two'], '')
end)
