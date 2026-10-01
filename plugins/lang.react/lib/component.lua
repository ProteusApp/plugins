-- component: the text of a new React component, for New React Component and for the
-- `component` completion. Nothing here calls the host, so the tests reach it.

---@class LangReact.ComponentModule
local M = {}

---True for a name a component can have: a capital letter, then letters, digits or `_`.
---@param name string
---@return boolean
function M.valid (name)
  return name:match ('^%u[%w_]*$') ~= nil
end

---Why a typed name cannot be a component's, or nil when it can.
---@param name string
---@return string?
function M.problem (name)
  if name == '' then
    return 'Type a name, such as Button.'
  end
  if not name:match ('^%u') then
    return 'A component name starts with a capital letter.'
  end
  if not M.valid (name) then
    return 'A component name holds only letters, digits and _.'
  end
  return nil
end

---The component a file is named after, such as `Button` for `Button.tsx`, or `Component`
---when the file name cannot be one.
---@param path string
---@return string
function M.name_of (path)
  local base = path:match ('([^/\\]+)$') or path
  local stem = base:match ('^([^%.]+)') or base
  return M.valid (stem) and stem or 'Component'
end

---A component's source. A TypeScript one types its props.
---@param name string
---@param typescript boolean
---@return string
function M.source (name, typescript)
  local lines = {} ---@type string[]
  if typescript then
    lines[#lines + 1] = 'type ' .. name .. 'Props = {'
    lines[#lines + 1] = '  className?: string;'
    lines[#lines + 1] = '};'
    lines[#lines + 1] = ''
    lines[#lines + 1] = 'export function '
      .. name
      .. '({ className }: '
      .. name
      .. 'Props) {'
  else
    lines[#lines + 1] = 'export function ' .. name .. '({ className }) {'
  end
  lines[#lines + 1] = '  return <div className={className}>'
    .. name
    .. '</div>;'
  lines[#lines + 1] = '}'
  return table.concat (lines, '\n') .. '\n'
end

return M
