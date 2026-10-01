local hooks = require ('lib.hooks') --[[@as LangReact.HooksModule]]

---@param items Proteus.CompletionItem[]
---@return string[]
local function labels (items)
  local out = {}
  for _, item in ipairs (items) do
    out[#out + 1] = item.label
  end
  return out
end

test ('context wants a word alone on its line', function ()
  eq (hooks.context ('  useS'), { word = 'useS', indent = '  ', from = 2 })
  eq (hooks.context ('const x = useS'), nil)
  eq (hooks.context ('  foo.use'), nil)
  eq (hooks.context ('  '), nil)
end)

test ('useState becomes a whole statement', function ()
  local text = 'function A() {\n  useSt\n}'
  local result =
    assert (hooks.complete (text, { line = 1, character = 7 }, 'A.jsx'))
  eq (result.from, 2)
  eq (labels (result.items), { 'useState' })
  eq (result.items[1].insert, 'const [value, setValue] = useState()')
end)

test ('a statement of several lines takes the indent of its line', function ()
  local result = assert (
    hooks.complete ('    useEff', { line = 0, character = 10 }, 'A.tsx')
  )
  eq (result.items[1].insert, 'useEffect(() => {\n      \n    }, [])')
end)

test (
  'use offers every hook, and component comes only without an indent',
  function ()
    local result =
      assert (hooks.complete ('use', { line = 0, character = 3 }, 'A.jsx'))
    eq (labels (result.items), {
      'useState',
      'useEffect',
      'useMemo',
      'useCallback',
      'useRef',
      'useContext',
      'useReducer',
    })
    local top = assert (
      hooks.complete ('comp', { line = 0, character = 4 }, 'src/Card.tsx')
    )
    eq (labels (top.items), { 'component' })
    ok (
      top.items[1].insert:find (
        'export function Card({ className }: CardProps)',
        1,
        true
      )
    )
    eq (hooks.complete ('  comp', { line = 0, character = 6 }, 'Card.tsx'), nil)
  end
)

test ('nothing fits a word that starts no item', function ()
  eq (hooks.complete ('xyz', { line = 0, character = 3 }, 'A.jsx'), nil)
end)
