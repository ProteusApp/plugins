-- attach: gives Some Sass's help to the editor. `.sass` files have a language of their own,
-- `sass`. `.scss` files share `css` with `.css` and `.less` files, and the editor keeps one
-- provider for each language. When lang.css runs, it owns `css`, and this plugin claims
-- `.scss` files through lang.css's `css` service, so both plugins keep their files. Without
-- lang.css, this plugin sets the provider for `css` itself.
--
-- Nothing here needs anything but the editor and the service, so the tests reach it with
-- stand-ins.

---The part of lang.css's `css` service this plugin uses.
---@class LangSass.CssService
---@field route fun(spec: { extensions: string[], factory: Proteus.ProviderFactory }): fun()

---The part of the editor this module uses.
---@class LangSass.AttachEditor
---@field set_provider fun(language: string, factory: Proteus.ProviderFactory): fun()

---@class LangSass.AttachOptions
---@field editor LangSass.AttachEditor
---@field languages string[] The editor's languages to give help in, such as `{ 'css', 'sass' }`.
---@field providers table<string, Proteus.ProviderFactory> The help, by editor language.
---@field css fun(): LangSass.CssService? lang.css's service, while it runs.

---@class LangSass.Attach
---@field attach fun() Gives the help to the editor, or gives it again the way it should go now.
---@field detach fun() Takes the help away.

---@class LangSass.AttachModule
local M = {}

-- The files this plugin claims from lang.css.
M.CLAIMED = { 'scss' }

---The `css` service, when the plugin that provides it is lang.css's kind.
---@param try_use fun(name: string): any Such as `app.try_use`.
---@return LangSass.CssService?
function M.find_css (try_use)
  local service = try_use ('css')
  if type (service) == 'table' and type (service.route) == 'function' then
    return service
  end
  return nil
end

---@param opts LangSass.AttachOptions
---@return LangSass.Attach
function M.new (opts)
  local removers = {} ---@type fun()[]

  local function detach ()
    for _, remove in ipairs (removers) do
      remove ()
    end
    removers = {}
  end

  ---@type LangSass.Attach
  return {
    attach = function ()
      detach ()
      local css = opts.css ()
      for _, language in ipairs (opts.languages) do
        local factory = opts.providers[language]
        if language == 'css' and css then
          removers[#removers + 1] =
            css.route ({ extensions = M.CLAIMED, factory = factory })
        else
          removers[#removers + 1] = opts.editor.set_provider (language, factory)
        end
      end
    end,
    detach = detach,
  }
end

return M
