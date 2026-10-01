-- hadolint: turns Hadolint's findings into problems for the Problems panel. `hadolint --format
-- json -` prints a list, one entry for each finding:
--
--   [{"code":"DL3006","column":1,"file":"-","level":"warning","line":1,
--     "message":"Always tag the version of an image explicitly"}]
--
-- Lines and columns count from 1. A finding names an instruction rather than a word, so its
-- underline runs to the end of the line.
-- Nothing here calls the app, so the tests reach it.

---@class LangDocker.HadolintModule
local M = {}

-- Hadolint's levels as the editor's. Style findings are the mildest.
---@type table<string, Proteus.Severity>
local LEVELS = {
  error = 'error',
  warning = 'warning',
  info = 'info',
  style = 'hint',
}

---Each line's length in UTF-16 units, as the editor counts columns, without its line break.
---@param text string
---@return integer[]
local function line_lengths (text)
  local out = {} ---@type integer[]
  for line in (text .. '\n'):gmatch ('([^\n]*)\n') do
    line = line:gsub ('\r$', '')
    local units = 0
    for i = 1, #line do
      local b = line:byte (i)
      -- Each character counts at its first byte. One of four bytes counts twice.
      if b < 0x80 or b >= 0xC0 then
        units = units + (b >= 0xF0 and 2 or 1)
      end
    end
    out[#out + 1] = units
  end
  return out
end

---The problems in Hadolint's decoded output, for the text it checked.
---@param findings any The decoded JSON list.
---@param text string The file's text.
---@return Proteus.Diagnostic[]
function M.diagnostics (findings, text)
  local out = {} ---@type Proteus.Diagnostic[]
  if type (findings) ~= 'table' then
    return out
  end
  local lengths = line_lengths (text)
  for _, f in ipairs (findings) do
    if type (f) == 'table' and type (f.message) == 'string' then
      local line = math.max ((tonumber (f.line) or 1) - 1, 0)
      local character = math.max ((tonumber (f.column) or 1) - 1, 0)
      local length = lengths[line + 1] or 0
      out[#out + 1] = {
        line = line,
        character = character,
        end_line = line,
        end_character = math.max (length, character),
        severity = LEVELS[tostring (f.level)] or 'warning',
        message = f.message,
        source = 'hadolint',
        code = f.code and tostring (f.code) or nil,
      }
    end
  end
  return out
end

return M
