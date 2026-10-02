local provider = require ('lib.provider')

---A document with this text, as the editor gives it.
---@param text string
---@return Proteus.DocInfo
local function doc_of (text)
  return {
    path = 'C:/hop/main.gd',
    external = true,
    language = 'gdscript',
    readonly = false,
    version = function ()
      return 1
    end,
    text = function ()
      return text
    end,
    dirty = function ()
      return false
    end,
  }
end

---A provider that records what reached it.
---@param seen table
---@return Proteus.ProviderFactory
local function factory_of (seen)
  return function ()
    return {
      hover = function (_, respond)
        respond ('Jumps.`br`Higher.')
      end,
      definition = function (pos)
        seen.definition = pos
      end,
      complete = function (_, respond)
        respond ({ items = {} })
      end,
    }
  end
end

test ('wrap tidies hover help', function ()
  local p = provider.wrap (factory_of ({}), function ()
    return false
  end) (doc_of ('jump()'))
  local shown = nil
  p.hover ({ line = 0, character = 1 }, function (markdown)
    shown = markdown
  end)
  eq (shown, 'Jumps.\n\nHigher.')
end)

test ('wrap keeps the other hooks', function ()
  local p = provider.wrap (factory_of ({}), function ()
    return false
  end) (doc_of (''))
  ok (type (p.complete) == 'function')
end)

test (
  'wrap opens a res:// path under the cursor instead of asking Godot',
  function ()
    local seen = {}
    local opened = nil
    local d = doc_of ('extends Node\nconst E = preload ("res://enemy.tscn")')
    local p = provider.wrap (factory_of (seen), function (_, res)
      opened = res
      return true
    end) (d)
    p.definition ({ line = 1, character = 25 })
    eq (opened, 'res://enemy.tscn')
    eq (seen.definition, nil)
  end
)

test ('wrap asks Godot for anything else', function ()
  local seen = {}
  local p = provider.wrap (factory_of (seen), function ()
    error ('nothing to open')
  end) (doc_of ('extends Node\njump()'))
  p.definition ({ line = 1, character = 2 })
  eq (seen.definition, { line = 1, character = 2 })
end)

test ('wrap gives no provider where the client gives none', function ()
  local wrapped = provider.wrap (function ()
    return nil
  end, function ()
    return false
  end)
  eq (wrapped (doc_of ('')), nil)
end)

test (
  'wrap_app wraps the providers the client sets, and passes the rest',
  function ()
    local set = {}
    local fake_editor = {
      set_provider = function (language, factory)
        set[language] = factory
        return 'remove'
      end,
      docs = function ()
        return 'docs'
      end,
    }
    local app = {
      os = 'windows',
      use = function (name)
        if name == 'editor' then
          return fake_editor
        end
        return name
      end,
    }
    local wrapped = provider.wrap_app (app, function ()
      return false
    end)
    eq (wrapped.os, 'windows')
    eq (wrapped.use ('tools'), 'tools')
    local editor = wrapped.use ('editor')
    eq (editor.docs (), 'docs')
    eq (editor.set_provider ('gdscript', factory_of ({})), 'remove')
    local p = set.gdscript (doc_of (''))
    local shown = nil
    p.hover ({ line = 0, character = 0 }, function (markdown)
      shown = markdown
    end)
    eq (shown, 'Jumps.\n\nHigher.')
  end
)
