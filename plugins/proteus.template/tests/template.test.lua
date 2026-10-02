-- The greetings logic, and what the plugin adds when it starts. Run with `npm test` from the
-- top of the registry, or `node scripts/lua-test.mjs <part of the id>` for this one.

local greetings = require ('lib.greetings')
local plugin = require ('init')

-- lib/greetings.lua ------------------------------------------------------------------------

test ('a greeting starts with the word and ends with the name', function ()
  eq (greetings.make ('Hello', 'Ada'), 'Hello, Ada!')
  eq (greetings.make (' Hi ', '  Grace '), 'Hi, Grace!')
end)

test ('no name greets the world, and no word says Hello', function ()
  eq (greetings.make ('Hello', nil), 'Hello, world!')
  eq (greetings.make ('Hello', '   '), 'Hello, world!')
  eq (greetings.make ('', 'Ada'), 'Hello, Ada!')
end)

test (
  'the newest greeting comes first, and the list stops at the limit',
  function ()
    local list = {} ---@type string[]
    for i = 1, greetings.LIMIT + 5 do
      list = greetings.add (list, 'g' .. i)
    end
    eq (#list, greetings.LIMIT)
    eq (list[1], 'g' .. (greetings.LIMIT + 5))
    eq (list[#list], 'g6')
  end
)

test ('the list writes as Markdown', function ()
  eq (greetings.markdown ({}), '# Greetings\n\nNone yet.\n')
  eq (
    greetings.markdown ({ 'Hi, Ada!', 'Hi, world!' }),
    '# Greetings\n\n- Hi, Ada!\n- Hi, world!\n'
  )
end)

-- init.lua ---------------------------------------------------------------------------------

---An element that takes every call and keeps its children.
---@return table
local function element ()
  local el = { children = {} }
  setmetatable (el, {
    __index = function ()
      return function ()
        return el
      end
    end,
  })
  function el.append (_, ...)
    for _, child in ipairs ({ ... }) do
      el.children[#el.children + 1] = child
    end
    return el
  end
  function el.clear ()
    el.children = {}
    return el
  end
  function el.value ()
    return ''
  end
  return el
end

---Starts the plugin on a stand-in app, and returns what it added.
---@return table added
local function start ()
  local added = {
    commands = {},
    settings = {},
    views = {},
    services = {},
    files = {},
    store = {},
  }
  local ui = setmetatable ({}, {
    __index = function ()
      return function ()
        return element ()
      end
    end,
  })
  local services = {
    ui = ui,
    views = {
      add = function (dock, spec)
        added.views[spec.id] = dock
      end,
    },
    commands = {
      register = function (spec)
        added.commands[spec.id] = spec
      end,
    },
    settings = {
      define = function (key, spec)
        added.settings[key] = spec
      end,
      get = function (key)
        return added.settings[key].default
      end,
    },
  }
  local app = {
    use = function (name)
      return assert (services[name], 'no service ' .. name)
    end,
    try_use = function ()
      return nil
    end,
    provide = function (name, value)
      added.services[name] = value
    end,
    store = {
      get = function (key, default)
        local v = added.store[key]
        if v == nil then
          return default
        end
        return v
      end,
      set = function (key, value)
        added.store[key] = value
      end,
    },
    fs = {
      write = function (path, text)
        added.files[path] = text
      end,
    },
  }
  plugin.activate (app)
  return added
end

test ('it names everything after the last part of its id', function ()
  local added = start ()
  ok (added.commands['template.greet'], 'the command')
  ok (added.settings['template.greeting'], 'the setting')
  eq (added.views, { template = 'right' })
  ok (added.services.template, 'the service')
end)

test (
  'a greeting from the service is kept and written to its folder',
  function ()
    local added = start ()
    local service = added.services.template
    eq (service.greet ('Ada'), 'Hello, Ada!')
    added.commands['template.greet'].run ()
    eq (service.list (), { 'Hello, world!', 'Hello, Ada!' })
    eq (added.store.said, { 'Hello, world!', 'Hello, Ada!' })
    eq (
      added.files['template/greetings.md'],
      '# Greetings\n\n- Hello, world!\n- Hello, Ada!\n'
    )
    eq (plugin.folders, { 'template' })
  end
)
