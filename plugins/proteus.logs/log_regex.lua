-- log_regex: regular expressions for the log filter, since Lua's patterns have no `|` and no
-- groups. It reads the common syntax: `.`, `[...]` and `[^...]`, `\d \w \s` and their capitals,
-- `\b`, `^` and `$`, groups `(...)` and `(?:...)`, `|`, and `* + ? {n} {n,} {n,m}`, each with
-- a `?` after it to take as little as it can. It matches bytes, and backtracks.
--
-- A pattern compiles once into a tree of nodes. Matching walks the tree with continuations,
-- and a repeat of one character, such as `.*` or `\d+`, loops instead of recursing, so a long
-- line does not run out of stack.

---@alias LogRegex.Test fun(c: integer): boolean

---@class LogRegex.Node
---@field t 'char'|'any'|'set'|'bol'|'eol'|'word'|'group'|'rep'
---@field c? integer The byte of a `char`.
---@field test? LogRegex.Test What a `set` lets through.
---@field neg? boolean For `word`: `\B` rather than `\b`.
---@field alts? LogRegex.Node[][] The branches of a `group`.
---@field node? LogRegex.Node What a `rep` repeats.
---@field min? integer
---@field max? integer Nil for no limit.
---@field lazy? boolean

---@class LogRegex.Program
---@field find fun(s: string, init?: integer): integer?, integer? The first match at or after `init`: where it starts and ends, or nil.

local BYTE_0, BYTE_9 = 48, 57
local BYTE_A, BYTE_Z = 65, 90
local BYTE_LA, BYTE_LZ = 97, 122
local BYTE_US = 95

---@param c integer
---@return boolean
local function is_digit (c)
  return c >= BYTE_0 and c <= BYTE_9
end

---@param c integer
---@return boolean
local function is_word (c)
  return is_digit (c)
    or (c >= BYTE_A and c <= BYTE_Z)
    or (c >= BYTE_LA and c <= BYTE_LZ)
    or c == BYTE_US
end

---@param c integer
---@return boolean
local function is_space (c)
  return c == 32 or (c >= 9 and c <= 13)
end

---@param c integer
---@return integer
local function lower (c)
  if c >= BYTE_A and c <= BYTE_Z then
    return c + 32
  end
  return c
end

---@param c integer
---@return integer
local function upper (c)
  if c >= BYTE_LA and c <= BYTE_LZ then
    return c - 32
  end
  return c
end

---@type table<string, LogRegex.Test>
local CLASSES = {
  d = is_digit,
  w = is_word,
  s = is_space,
  D = function (c)
    return not is_digit (c)
  end,
  W = function (c)
    return not is_word (c)
  end,
  S = function (c)
    return not is_space (c)
  end,
}

---@type table<string, integer>
local ESCAPES = {
  n = 10,
  t = 9,
  r = 13,
  f = 12,
  v = 11,
  ['0'] = 0,
}

-- What stops a parse, so its message tells itself from a bug.
local STOP = 'log regex: '

---@param what string
local function fail (what)
  error (STOP .. what, 0)
end

---Reads a pattern into nodes.
---@param pattern string
---@param fold boolean Letters match in either case.
---@return LogRegex.Node[][]
local function parse (pattern, fold)
  local pos = 1
  local len = #pattern

  ---@return string
  local function peek ()
    return pattern:sub (pos, pos)
  end

  ---A test for one byte, folded when the pattern ignores case.
  ---@param test LogRegex.Test
  ---@return LogRegex.Test
  local function folded (test)
    if not fold then
      return test
    end
    return function (c)
      return test (c) or test (lower (c)) or test (upper (c))
    end
  end

  ---The byte an escape stands for, or the test of a class such as `\d`.
  ---@return integer?
  ---@return LogRegex.Test?
  local function escape ()
    local e = pattern:sub (pos, pos)
    if e == '' then
      fail ('the pattern ends with a \\')
    end
    pos = pos + 1
    if CLASSES[e] then
      return nil, CLASSES[e]
    end
    if ESCAPES[e] then
      return ESCAPES[e], nil
    end
    if e == 'x' then
      local hex = pattern:sub (pos, pos + 1)
      local code = tonumber (hex, 16)
      if not code or #hex < 2 then
        fail ('\\x needs two hex digits')
      end
      pos = pos + 2
      return code, --[[@as integer]]
        nil
    end
    return e:byte (), nil
  end

  ---@return LogRegex.Node
  local function set ()
    local negate = false
    if peek () == '^' then
      negate = true
      pos = pos + 1
    end
    local tests = {} ---@type LogRegex.Test[]
    local first = true
    while true do
      local c = peek ()
      if c == '' then
        fail ('a [ has no ]')
      end
      if c == ']' and not first then
        pos = pos + 1
        break
      end
      first = false
      local from ---@type integer?
      if c == '\\' then
        pos = pos + 1
        local byte, class = escape ()
        if class then
          tests[#tests + 1] = class
        end
        from = byte
      else
        from = c:byte ()
        pos = pos + 1
      end
      if from then
        if
          peek () == '-'
          and pattern:sub (pos + 1, pos + 1) ~= ']'
          and pos + 1 <= len
        then
          pos = pos + 1
          local to_c = peek ()
          local to ---@type integer?
          if to_c == '\\' then
            pos = pos + 1
            to = escape ()
          else
            to = to_c:byte ()
            pos = pos + 1
          end
          if not to or to < from then
            fail ('a range in [ ] runs backwards')
          end
          local low, high = from, to --[[@as integer]]
          tests[#tests + 1] = function (b)
            return b >= low and b <= high
          end
        else
          local only = from
          tests[#tests + 1] = function (b)
            return b == only
          end
        end
      end
    end
    local any = function (b)
      for _, t in ipairs (tests) do
        if t (b) then
          return true
        end
      end
      return false
    end
    local test = folded (any)
    if negate then
      return {
        t = 'set',
        test = function (b)
          return b ~= 10 and not test (b)
        end,
      }
    end
    return { t = 'set', test = test }
  end

  local alternation ---@type fun(): LogRegex.Node[][]

  ---One item, before any quantifier.
  ---@return LogRegex.Node?
  local function atom ()
    local c = peek ()
    if c == '(' then
      pos = pos + 1
      if pattern:sub (pos, pos + 1) == '?:' then
        pos = pos + 2
      elseif peek () == '?' then
        fail ('(? is supported only as (?:')
      end
      local alts = alternation ()
      if peek () ~= ')' then
        fail ('a ( has no )')
      end
      pos = pos + 1
      return { t = 'group', alts = alts }
    elseif c == '[' then
      pos = pos + 1
      return set ()
    elseif c == '.' then
      pos = pos + 1
      return { t = 'any' }
    elseif c == '^' then
      pos = pos + 1
      return { t = 'bol' }
    elseif c == '$' then
      pos = pos + 1
      return { t = 'eol' }
    elseif c == '\\' then
      pos = pos + 1
      local e = peek ()
      if e == 'b' or e == 'B' then
        pos = pos + 1
        return { t = 'word', neg = e == 'B' }
      end
      local byte, class = escape ()
      if class then
        return { t = 'set', test = folded (class) }
      end
      return {
        t = 'char',
        c = fold and lower (byte --[[@as integer]]) or byte,
      }
    elseif c == '*' or c == '+' or c == '?' then
      fail ('nothing comes before ' .. c)
    elseif c == ')' then
      fail ('a ) has no (')
    end
    pos = pos + 1
    local b = c:byte ()
    return { t = 'char', c = fold and lower (b) or b }
  end

  ---An item with its quantifier.
  ---@param node LogRegex.Node
  ---@return LogRegex.Node
  local function quantified (node)
    local c = peek ()
    local min, max ---@type integer, integer?
    if c == '*' then
      min, max = 0, nil
      pos = pos + 1
    elseif c == '+' then
      min, max = 1, nil
      pos = pos + 1
    elseif c == '?' then
      min, max = 0, 1
      pos = pos + 1
    elseif c == '{' then
      local a, b, close = pattern:match ('^{(%d*)(,?%d*)}()', pos)
      if not a or (a == '' and (b == '' or b == ',')) then
        -- Not a count, so the brace stands for itself.
        return node
      end
      min = math.floor (tonumber (a) or 0)
      if b == '' then
        max = min
      elseif b == ',' then
        max = nil
      else
        max = math.floor (tonumber (b:sub (2)) or 0)
        if max < min then
          fail ('a {n,m} has m below n')
        end
      end
      pos = close --[[@as integer]]
    else
      return node
    end
    if node.t == 'bol' or node.t == 'eol' or node.t == 'word' then
      fail ('an anchor cannot repeat')
    end
    local lazy = false
    if peek () == '?' then
      lazy = true
      pos = pos + 1
    end
    return { t = 'rep', node = node, min = min, max = max, lazy = lazy }
  end

  ---@return LogRegex.Node[]
  local function sequence ()
    local seq = {} ---@type LogRegex.Node[]
    while pos <= len do
      local c = peek ()
      if c == '|' or c == ')' then
        break
      end
      local node = atom ()
      if node then
        seq[#seq + 1] = quantified (node)
      end
    end
    return seq
  end

  alternation = function ()
    local alts = { sequence () }
    while peek () == '|' do
      pos = pos + 1
      alts[#alts + 1] = sequence ()
    end
    return alts
  end

  local alts = alternation ()
  if pos <= len then
    fail ('a ) has no (')
  end
  return alts
end

---@param node LogRegex.Node
---@return boolean
local function single (node)
  return node.t == 'char' or node.t == 'any' or node.t == 'set'
end

---Compiles a pattern. Returns the program, or nil and what is wrong with the pattern.
---@param pattern string
---@param opts? { fold?: boolean } `fold` matches letters in either case, for a subject in lower case.
---@return LogRegex.Program?
---@return string?
local function compile (pattern, opts)
  local fold = opts ~= nil and opts.fold == true
  local ok, alts = pcall (parse, pattern, fold)
  if not ok then
    local message = tostring (alts)
    if message:sub (1, #STOP) == STOP then
      return nil, message:sub (#STOP + 1)
    end
    return nil, message
  end
  local top = { t = 'group', alts = alts } ---@type LogRegex.Node

  local subject = ''
  local slen = 0

  ---True when one byte matches a single-byte node.
  ---@param node LogRegex.Node
  ---@param i integer
  ---@return boolean
  local function one (node, i)
    if i > slen then
      return false
    end
    local b = subject:byte (i)
    if node.t == 'char' then
      return b == node.c
    elseif node.t == 'any' then
      return b ~= 10
    end
    return node.test (b)
  end

  local match_seq ---@type fun(seq: LogRegex.Node[], k: integer, i: integer, after: fun(i: integer): integer?): integer?

  ---Matches one node at `i`, then the rest through `after`. Returns where the whole match
  ---ends, or nil.
  ---@param node LogRegex.Node
  ---@param i integer
  ---@param after fun(i: integer): integer?
  ---@return integer?
  local function match_node (node, i, after)
    local t = node.t
    if t == 'char' or t == 'any' or t == 'set' then
      if one (node, i) then
        return after (i + 1)
      end
      return nil
    elseif t == 'bol' then
      if i == 1 then
        return after (i)
      end
      return nil
    elseif t == 'eol' then
      if i == slen + 1 then
        return after (i)
      end
      return nil
    elseif t == 'word' then
      local before = i > 1 and is_word (subject:byte (i - 1))
      local here = i <= slen and is_word (subject:byte (i))
      if (before ~= here) ~= (node.neg == true) then
        return after (i)
      end
      return nil
    elseif t == 'group' then
      for _, seq in ipairs (node.alts) do
        local stop = match_seq (seq, 1, i, after)
        if stop then
          return stop
        end
      end
      return nil
    end
    -- A repeat.
    local inner = node.node --[[@as LogRegex.Node]]
    local min, max =
      node.min, --[[@as integer]]
      node.max
    if single (inner) then
      -- Count how far it can go, then try the rest from each place.
      local n = 0
      while (not max or n < max) and one (inner, i + n) do
        n = n + 1
      end
      if n < min then
        return nil
      end
      if node.lazy then
        for count = min, n do
          local stop = after (i + count)
          if stop then
            return stop
          end
        end
      else
        for count = n, min, -1 do
          local stop = after (i + count)
          if stop then
            return stop
          end
        end
      end
      return nil
    end
    ---@param count integer
    ---@param at integer
    ---@return integer?
    local function step (count, at)
      local function more ()
        if max and count >= max then
          return nil
        end
        return match_node (inner, at, function (j)
          -- A pass that matches nothing would repeat for ever.
          if j == at then
            return nil
          end
          return step (count + 1, j)
        end)
      end
      if count < min then
        return more ()
      end
      if node.lazy then
        return after (at) or more ()
      end
      return more () or after (at)
    end
    return step (0, i)
  end

  match_seq = function (seq, k, i, after)
    local node = seq[k]
    if not node then
      return after (i)
    end
    return match_node (node, i, function (j)
      return match_seq (seq, k + 1, j, after)
    end)
  end

  ---@param j integer
  ---@return integer
  local function done (j)
    return j
  end

  -- A pattern that starts with a plain byte only needs trying where that byte is.
  local first = alts[1] and alts[1][1]
  local lead = #alts == 1
      and first
      and first.t == 'char'
      and string.char (first.c)
    or nil
  local anchored = #alts == 1 and first and first.t == 'bol'

  ---@param s string
  ---@param init? integer
  ---@return integer?
  ---@return integer?
  local function find (s, init)
    subject = s
    slen = #s
    local i = init or 1
    while i <= slen + 1 do
      if lead then
        local at = s:find (lead, i, true)
        if not at then
          return nil, nil
        end
        i = at
      end
      local stop = match_node (top, i, done)
      if stop then
        return i, stop - 1
      end
      if anchored then
        return nil, nil
      end
      i = i + 1
    end
    return nil, nil
  end

  return { find = find }, nil
end

return { compile = compile }
