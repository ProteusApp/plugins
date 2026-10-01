-- provider: adds two things to the help the app's language client gives GDScript files.
--
--   hover        Godot's help goes through hover.clean, so it reads as plain Markdown.
--   definition   F12 on a `res://` path in quotes, such as in `preload ("res://enemy.tscn")`,
--                opens that file. Godot offers those paths as links, which the editor does
--                not show, so its own answer would go nowhere.
--
-- The client hands its help to the editor through `editor.set_provider`. wrap_app gives the
-- client an app whose editor wraps that help on its way in. Everything else reaches the real
-- app untouched.

local hover = require ('lib.hover') --[[@as LangGdscript.HoverModule]]
local project = require ('lib.project') --[[@as LangGdscript.ProjectModule]]

---Opens the file a `res://` path names, for a document. Returns false when it cannot.
---@alias LangGdscript.OpenRes fun(doc: Proteus.DocInfo, res: string): boolean

---@class LangGdscript.ProviderModule
local M = {}

---The `res://` path under a position in a document.
---@param doc Proteus.DocInfo
---@param pos Proteus.CodePosition
---@return string?
function M.res_at (doc, pos)
  local line = project.line_at (doc.text (), pos.line)
  return line and project.res_path_at (line, pos.character) or nil
end

---Wraps a provider factory, so its help is tidied and `res://` paths open their files.
---@param factory Proteus.ProviderFactory
---@param open_res LangGdscript.OpenRes
---@return Proteus.ProviderFactory
function M.wrap (factory, open_res)
  return function (doc)
    local inner = factory (doc)
    if not inner then
      return nil
    end
    ---@type Proteus.CodeProvider
    local outer = {}
    for k, v in pairs (inner) do
      outer[k] = v
    end
    local ask_hover = inner.hover
    if ask_hover then
      outer.hover = function (pos, respond)
        ask_hover (pos, function (markdown)
          respond (hover.clean (markdown))
        end)
      end
    end
    local ask_definition = inner.definition
    outer.definition = function (pos)
      local res = M.res_at (doc, pos)
      if res and open_res (doc, res) then
        return
      end
      if ask_definition then
        ask_definition (pos)
      end
    end
    return outer
  end
end

---An app for the language client, whose editor wraps every provider factory it is given.
---@param app Proteus.App
---@param open_res LangGdscript.OpenRes
---@return Proteus.App
function M.wrap_app (app, open_res)
  local editor = app.use ('editor')
  local wrapped_editor = setmetatable ({
    set_provider = function (language, factory)
      return editor.set_provider (language, M.wrap (factory, open_res))
    end,
  }, { __index = editor })
  local wrapped = setmetatable ({
    use = function (name)
      if name == 'editor' then
        return wrapped_editor
      end
      return app.use (name)
    end,
  }, { __index = app })
  return wrapped --[[@as Proteus.App]]
end

return M
