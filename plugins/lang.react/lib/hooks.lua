-- hooks: React completion the language server lacks. A word alone on its line offers the
-- common hooks as whole statements, such as `useState` becoming
-- `const [value, setValue] = useState()`, and `component` offers a component named after the
-- file. Nothing here calls the host, so the tests reach it.

local component = require ('lib.component') --[[@as LangReact.ComponentModule]]

-- Each hook and the statement it inserts. A line break in a statement takes the line's
-- indent.
local HOOKS = {
  { 'useState', 'const [value, setValue] = useState()' },
  { 'useEffect', 'useEffect(() => {\n  \n}, [])' },
  { 'useMemo', 'const value = useMemo(() => {\n  \n}, [])' },
  { 'useCallback', 'const handle = useCallback(() => {\n  \n}, [])' },
  { 'useRef', 'const ref = useRef(null)' },
  { 'useContext', 'const value = useContext(Context)' },
  {
    'useReducer',
    'const [state, dispatch] = useReducer(reducer, initialState)',
  },
}

---Where the cursor is, when it ends a word alone on its line.
---@class LangReact.HookContext
---@field word string
---@field indent string The line's leading spaces and tabs.
---@field from integer Where the word starts, counted from 0.

---@class LangReact.HooksModule
local M = {}

---The word before the cursor, when nothing else is on the line before it.
---@param before string The line up to the cursor.
---@return LangReact.HookContext?
function M.context (before)
  local indent, word = before:match ('^([ \t]*)([%a_$][%w_$]*)$')
  if not indent then
    return nil
  end
  return { word = word, indent = indent, from = #indent }
end

---@param text string
---@param indent string
---@return string
local function indented (text, indent)
  return (text:gsub ('\n', '\n' .. indent))
end

---@param language string
---@param text string
---@return string
local function fenced (language, text)
  return '```' .. language .. '\n' .. text .. '\n```'
end

---The items that fit a context, for a file with this path.
---@param at LangReact.HookContext
---@param path string
---@param typescript boolean True in a `.tsx` file.
---@return Proteus.CompletionItem[]
function M.items (at, path, typescript)
  local typed = at.word:lower ()
  ---@param label string
  ---@return boolean
  local function fits (label)
    return label:lower ():sub (1, #typed) == typed
  end
  local language = typescript and 'tsx' or 'jsx'
  local items = {} ---@type Proteus.CompletionItem[]
  for _, hook in ipairs (HOOKS) do
    local name, text = hook[1], hook[2]
    if fits (name) then
      items[#items + 1] = {
        label = name,
        kind = 'snippet',
        detail = 'React hook',
        documentation = fenced (language, text),
        insert = indented (text, at.indent),
      }
    end
  end
  -- A component goes at the top of a file, so only with no indent.
  if at.indent == '' and fits ('component') then
    local text = component.source (component.name_of (path), typescript)
    items[#items + 1] = {
      label = 'component',
      kind = 'snippet',
      detail = 'React component',
      documentation = fenced (language, text),
      insert = text,
    }
  end
  return items
end

---The line a position is on, counted from 0.
---@param text string
---@param line integer
---@return string?
function M.line (text, line)
  local n = 0
  for each in (text .. '\n'):gmatch ('([^\n]*)\n') do
    if n == line then
      return (each:gsub ('\r$', ''))
    end
    n = n + 1
  end
  return nil
end

---Completion for a position in a file, or nil when none fits.
---@param text string
---@param pos Proteus.CodePosition
---@param path string
---@return { items: Proteus.CompletionItem[], from: integer }?
function M.complete (text, pos, path)
  local line = M.line (text, pos.line)
  local at = line and M.context (line:sub (1, pos.character))
  if not at then
    return nil
  end
  local typescript = path:lower ():match ('%.tsx$') ~= nil
  local items = M.items (at, path, typescript)
  if #items == 0 then
    return nil
  end
  return { items = items, from = at.from }
end

return M
