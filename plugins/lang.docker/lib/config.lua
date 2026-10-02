-- config: what the server gets when it asks for its settings. It asks for two sections, one
-- for its checks and one for its formatter, once for each open file.
--
-- The checks section names every check with `'warning'`, the server's own default. A check
-- the answer leaves out is turned off, so an empty answer would hide them all.
-- Nothing here calls the app, so the tests reach it.

---@class LangDocker.ConfigModule
local M = {}

-- The checks the server makes on its own, each `'ignore'`, `'warning'` or `'error'`.
local CHECKS = {
  'deprecatedMaintainer',
  'directiveCasing',
  'emptyContinuationLine',
  'instructionCasing',
  'instructionCmdMultiple',
  'instructionEntrypointMultiple',
  'instructionHealthcheckMultiple',
  'instructionJSONInSingleQuotes',
  'instructionWorkdirRelative',
}

---The answer for one section, or nil for a section the server does not read.
---@param section string
---@return table?
function M.section (section)
  if section == 'docker.languageserver.diagnostics' then
    local out = {} ---@type table<string, string>
    for _, name in ipairs (CHECKS) do
      out[name] = 'warning'
    end
    return out
  elseif section == 'docker.languageserver.formatter' then
    -- False indents the lines that continue an instruction, as the server does by default.
    return { ignoreMultilineInstructions = false }
  end
  return nil
end

return M
