-- sheet_fn_regex: the regular expression functions of the Sheet app's formulas: REGEXTEST and
-- REGEXMATCH, which say whether text matches, REGEXEXTRACT, which takes out what matched, and
-- REGEXREPLACE. The patterns are read by sheet_regex.lua. sheet_formula_kit loads the module.

local regex = require ('sheet_regex')

-- Compiled patterns, by case and pattern, so a column of formulas compiles each pattern once.
local cache = {} ---@type table<string, SheetRegex.Program|false>
local cached = 0
local CACHE_MAX = 200

---@param K Sheet.FormulaKit
return function (K)
  local define, raise = K.define, K.raise
  local text_of, int_of, given = K.text_of, K.int_of, K.given
  local to_text, opt_int = K.to_text, K.opt_int
  local new_array = K.new_array

  ---The program for a pattern, or raises #VALUE! for one that does not read.
  ---@param pattern string
  ---@param fold boolean
  ---@return SheetRegex.Program
  local function program (pattern, fold)
    local key = (fold and 'i' or 's') .. pattern
    local found = cache[key]
    if found == nil then
      if cached >= CACHE_MAX then
        cache, cached = {}, 0
      end
      found = regex.compile (pattern, { fold = fold }) or false
      cache[key] = found
      cached = cached + 1
    end
    if not found then
      return raise ('#VALUE!')
    end
    return found
  end

  ---Runs a search, and turns a search that ran too long into #VALUE!.
  ---@param prog SheetRegex.Program
  ---@param subject string
  ---@param init integer
  ---@return integer?
  ---@return integer?
  ---@return SheetRegex.Captures?
  local function find (prog, subject, init)
    local ok, a, b, caps = pcall (prog.find, subject, init)
    if not ok then
      return raise ('#VALUE!')
    end
    return a, b, caps
  end

  ---The text a search runs on: as it is, or in lower case when case does not count. Lower
  ---case keeps every byte where it was, so a match's place reads the text as it was.
  ---@param text string
  ---@param fold boolean
  ---@return string
  local function subject_of (text, fold)
    return fold and string.lower (text) or text
  end

  ---Every match, each as where it starts and ends and what its groups caught. A match of
  ---nothing moves on one byte, so the search ends.
  ---@param prog SheetRegex.Program
  ---@param subject string
  ---@param limit? integer Stop after this many.
  ---@return { [1]: integer, [2]: integer, [3]: SheetRegex.Captures }[]
  local function all_matches (prog, subject, limit)
    local out = {} ---@type { [1]: integer, [2]: integer, [3]: SheetRegex.Captures }[]
    local init = 1
    while init <= #subject + 1 do
      local a, b, caps = find (prog, subject, init)
      if not a or not b then
        break
      end
      out[#out + 1] = { a, b, caps or {} }
      if limit and #out >= limit then
        break
      end
      init = b >= a and b + 1 or a + 1
    end
    return out
  end

  ---Whether case counts: 0, the default, matches case, and 1 ignores it.
  ---@param v Sheet.Values
  ---@param n integer
  ---@param i integer
  ---@return boolean
  local function folds (v, n, i)
    local mode = opt_int (v, n, i, 0)
    if mode ~= 0 and mode ~= 1 then
      return raise ('#VALUE!')
    end
    return mode == 1
  end

  ---@type Sheet.Function
  local TEST = {
    min = 2,
    max = 3,
    map = function (v, n)
      local fold = folds (v, n, 3)
      local prog = program (to_text (v[2]), fold)
      return find (prog, subject_of (to_text (v[1]), fold), 1) ~= nil
    end,
  }
  define (
    'REGEXTEST',
    'Text',
    'REGEXTEST(text, pattern, [case_sensitivity])',
    'Says whether text matches a regular expression. 1 for case_sensitivity ignores case.',
    TEST
  )
  define (
    'REGEXMATCH',
    'Text',
    'REGEXMATCH(text, pattern)',
    'Says whether text matches a regular expression.',
    { min = 2, max = 2, map = TEST.map }
  )

  ---Fills a replacement: `$1` to `$9` stand for what those groups caught, `$0` and `$&` for
  ---the whole match, and `$$` for a dollar sign.
  ---@param with string
  ---@param text string
  ---@param a integer
  ---@param b integer
  ---@param caps SheetRegex.Captures
  ---@return string
  local function expand (with, text, a, b, caps)
    return (
      string.gsub (with, '%$([%d%$&])', function (c)
        if c == '$' then
          return '$'
        elseif c == '&' or c == '0' then
          return string.sub (text, a, b)
        end
        local span = caps[
          tonumber (c) --[[@as integer]]
        ]
        return span and string.sub (text, span[1], span[2]) or ''
      end)
    )
  end

  define (
    'REGEXREPLACE',
    'Text',
    'REGEXREPLACE(text, pattern, replacement, [occurrence], [case_sensitivity])',
    'Replaces what matches a regular expression. $1 in the replacement stands for the first group. occurrence picks one match, counting from the end when below 0.',
    {
      min = 3,
      max = 5,
      map = function (v, n)
        local text = to_text (v[1])
        local fold = folds (v, n, 5)
        local prog = program (to_text (v[2]), fold)
        local with = to_text (v[3])
        local which = opt_int (v, n, 4, 0)
        local found = all_matches (prog, subject_of (text, fold))
        if which > 0 then
          found = { found[which] }
        elseif which < 0 then
          found = { found[#found + 1 + which] }
        end
        local parts = {} ---@type string[]
        local at = 1
        for _, m in ipairs (found) do
          parts[#parts + 1] = string.sub (text, at, m[1] - 1)
          parts[#parts + 1] = expand (with, text, m[1], m[2], m[3])
          at = m[2] + 1
        end
        parts[#parts + 1] = string.sub (text, at)
        return table.concat (parts)
      end,
    }
  )

  define (
    'REGEXEXTRACT',
    'Text',
    'REGEXEXTRACT(text, pattern, [return_mode], [case_sensitivity])',
    'Takes out what matches a regular expression: the first match, every match in a column (return_mode 1), or the groups of the first match in a row (return_mode 2).',
    {
      min = 2,
      max = 4,
      run = function (args, ctx)
        local text = text_of (args[1], ctx)
        local mode = given (args[3]) and int_of (args[3], ctx) or 0
        local fold = given (args[4]) and int_of (args[4], ctx) or 0
        if (mode < 0 or mode > 2) or (fold ~= 0 and fold ~= 1) then
          return raise ('#VALUE!')
        end
        local prog = program (text_of (args[2], ctx), fold == 1)
        local found = all_matches (
          prog,
          subject_of (text, fold == 1),
          mode ~= 1 and 1 or nil
        )
        local first = found[1]
        if not first then
          return raise ('#N/A')
        end
        if mode == 0 then
          return string.sub (text, first[1], first[2])
        elseif mode == 1 then
          local out = {} ---@type Sheet.Values
          for i, m in ipairs (found) do
            out[i] = string.sub (text, m[1], m[2])
          end
          return #out == 1 and out[1] or new_array (#out, 1, out)
        end
        if prog.groups == 0 then
          return raise ('#N/A')
        end
        local out = {} ---@type Sheet.Values
        for i = 1, prog.groups do
          local span = first[3][i]
          out[i] = span and string.sub (text, span[1], span[2]) or ''
        end
        return #out == 1 and out[1] or new_array (1, #out, out)
      end,
    }
  )
end
