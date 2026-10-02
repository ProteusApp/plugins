-- sheet_fn_text: the text functions of the Sheet app's formulas: joining and cutting text,
-- case, searching and replacing, character codes, and numbers written as text with TEXT,
-- VALUE, FIXED and DOLLAR. sheet_formula_kit loads the module.

---@param K Sheet.FormulaKit
return function (K)
  local define, text1, raise = K.define, K.text1, K.raise
  local ERRORS, MANY = K.ERRORS, K.MANY
  local each, text_of, bool_of = K.each, K.text_of, K.bool_of
  local opt, opt_int, opt_bool = K.opt, K.opt_int, K.opt_bool
  local to_number, to_text, text_number = K.to_number, K.to_text, K.text_number
  local trunc, round_to = K.trunc, K.round_to
  local upper, lower, length, byte_of, wildcard =
    K.upper, K.lower, K.length, K.byte_of, K.wildcard
  local parse_number, format_number = K.parse_number, K.format

  -------------------------------------------------------------------------------------------
  -- Text
  -------------------------------------------------------------------------------------------

  ---@type Sheet.Function
  local CONCAT = {
    min = 1,
    max = MANY,
    run = function (args, ctx)
      local parts = {} ---@type string[]
      ---@param v Sheet.Value
      local function add (v)
        parts[#parts + 1] = to_text (v)
      end
      for _, node in ipairs (args) do
        each (node, ctx, add)
      end
      return table.concat (parts)
    end,
  }
  define (
    'CONCAT',
    'Text',
    'CONCAT(text1, [text2], ...)',
    'Joins text and the text in ranges into one.',
    CONCAT
  )
  define (
    'CONCATENATE',
    'Text',
    'CONCATENATE(text1, [text2], ...)',
    'Joins pieces of text into one.',
    CONCAT
  )

  define (
    'TEXTJOIN',
    'Text',
    'TEXTJOIN(delimiter, ignore_empty, text1, [text2], ...)',
    'Joins text with a delimiter between the pieces, leaving out empty ones when asked.',
    {
      min = 3,
      max = MANY,
      run = function (args, ctx)
        local delim = text_of (args[1], ctx)
        local skip = bool_of (args[2], ctx)
        local parts = {} ---@type string[]
        ---@param v Sheet.Value
        local function add (v)
          local s = to_text (v)
          if s ~= '' or not skip then
            parts[#parts + 1] = s
          end
        end
        for i = 3, #args do
          each (args[i], ctx, add)
        end
        return table.concat (parts, delim)
      end,
    }
  )

  define (
    'LEN',
    'Text',
    'LEN(text)',
    'Counts the characters in text.',
    text1 (length)
  )

  define (
    'LEFT',
    'Text',
    'LEFT(text, [count])',
    'Gives the first characters of text.',
    {
      min = 1,
      max = 2,
      map = function (v, n)
        local s = to_text (v[1])
        local count = opt_int (v, n, 2, 1)
        if count < 0 then
          return raise ('#VALUE!')
        end
        return string.sub (s, 1, byte_of (s, count + 1) - 1)
      end,
    }
  )

  define (
    'RIGHT',
    'Text',
    'RIGHT(text, [count])',
    'Gives the last characters of text.',
    {
      min = 1,
      max = 2,
      map = function (v, n)
        local s = to_text (v[1])
        local count = opt_int (v, n, 2, 1)
        if count < 0 then
          return raise ('#VALUE!')
        end
        local len = length (s)
        if count >= len then
          return s
        end
        return string.sub (s, byte_of (s, len - count + 1))
      end,
    }
  )

  define (
    'MID',
    'Text',
    'MID(text, start, count)',
    'Gives the characters of text from a start position.',
    {
      min = 3,
      max = 3,
      map = function (v)
        local s = to_text (v[1])
        local start, count = trunc (to_number (v[2])), trunc (to_number (v[3]))
        if start < 1 or count < 0 then
          return raise ('#VALUE!')
        end
        local a = byte_of (s, start)
        return string.sub (s, a, byte_of (s, start + count) - 1)
      end,
    }
  )

  define (
    'UPPER',
    'Text',
    'UPPER(text)',
    'Turns text into capital letters.',
    text1 (upper)
  )
  define (
    'LOWER',
    'Text',
    'LOWER(text)',
    'Turns text into small letters.',
    text1 (lower)
  )

  ---True for a character that has a case or belongs to a word, for PROPER.
  ---@param ch string
  ---@return boolean
  local function is_letter (ch)
    if #ch == 1 then
      return string.match (ch, '%a') ~= nil
    end
    local b1, b2 = string.byte (ch, 1, 2)
    if b1 == 194 or b1 == 226 then
      -- Symbols and punctuation such as ©, « and the typographic quotes and dashes.
      return false
    end
    return not (b1 == 195 and (b2 == 151 or b2 == 183))
  end

  define (
    'PROPER',
    'Text',
    'PROPER(text)',
    'Gives each word a capital first letter and small letters after it.',
    text1 (function (s)
      local out = {} ---@type string[]
      local inside = false
      for ch in string.gmatch (s, utf8.charpattern) do
        local letter = is_letter (ch)
        if letter then
          out[#out + 1] = inside and lower (ch) or upper (ch)
        else
          out[#out + 1] = ch
        end
        inside = letter
      end
      return table.concat (out)
    end)
  )

  define (
    'TRIM',
    'Text',
    'TRIM(text)',
    'Takes spaces off both ends of text and leaves one space between words.',
    text1 (function (s)
      local out = string.gsub (s, '^ +', '')
      out = string.gsub (out, ' +$', '')
      out = string.gsub (out, '  +', ' ')
      return out
    end)
  )

  define (
    'CLEAN',
    'Text',
    'CLEAN(text)',
    'Takes the control characters out of text.',
    text1 (function (s)
      return (string.gsub (s, '[\0-\31]', ''))
    end)
  )

  define (
    'SUBSTITUTE',
    'Text',
    'SUBSTITUTE(text, old_text, new_text, [instance])',
    'Replaces old text with new text, every time or only at one instance.',
    {
      min = 3,
      max = 4,
      map = function (v, n)
        local s = to_text (v[1])
        local old, new = to_text (v[2]), to_text (v[3])
        local which = n >= 4 and trunc (to_number (v[4])) or nil
        if which and which < 1 then
          return raise ('#VALUE!')
        end
        if old == '' then
          return s
        end
        local out = {} ---@type string[]
        local i, count = 1, 0
        while true do
          local a, b = string.find (s, old, i, true)
          if not a then
            break
          end
          count = count + 1
          if not which or count == which then
            out[#out + 1] = string.sub (s, i, a - 1) .. new
          else
            out[#out + 1] = string.sub (s, i, b)
          end
          i = b + 1
          if which and count == which then
            break
          end
        end
        out[#out + 1] = string.sub (s, i)
        return table.concat (out)
      end,
    }
  )

  define (
    'REPLACE',
    'Text',
    'REPLACE(text, start, count, new_text)',
    'Replaces a number of characters of text from a start position.',
    {
      min = 4,
      max = 4,
      map = function (v)
        local s = to_text (v[1])
        local start, count = trunc (to_number (v[2])), trunc (to_number (v[3]))
        if start < 1 or count < 0 then
          return raise ('#VALUE!')
        end
        local new = to_text (v[4])
        return string.sub (s, 1, byte_of (s, start) - 1)
          .. new
          .. string.sub (s, byte_of (s, start + count))
      end,
    }
  )

  ---FIND and SEARCH. Returns the character position where `needle` starts in `hay`.
  ---@param v Sheet.Values
  ---@param n integer
  ---@param search boolean True for SEARCH: no case, and wildcards.
  ---@return integer
  local function find_text (v, n, search)
    local needle, hay = to_text (v[1]), to_text (v[2])
    local start = opt_int (v, n, 3, 1)
    if start < 1 or start > length (hay) + 1 then
      return raise ('#VALUE!')
    end
    if needle == '' then
      return start
    end
    local byte = byte_of (hay, start)
    local pos ---@type integer?
    if search then
      pos = string.find (lower (hay), wildcard (lower (needle), false), byte)
    else
      pos = string.find (hay, needle, byte, true)
    end
    if not pos then
      return raise ('#VALUE!')
    end
    return length (string.sub (hay, 1, pos - 1)) + 1
  end

  define (
    'FIND',
    'Text',
    'FIND(find_text, within_text, [start])',
    'Gives the position of text inside other text, minding case.',
    {
      min = 2,
      max = 3,
      map = function (v, n)
        return find_text (v, n, false)
      end,
    }
  )

  define (
    'SEARCH',
    'Text',
    'SEARCH(find_text, within_text, [start])',
    'Gives the position of text inside other text, ignoring case and allowing wildcards.',
    {
      min = 2,
      max = 3,
      map = function (v, n)
        return find_text (v, n, true)
      end,
    }
  )

  define (
    'REPT',
    'Text',
    'REPT(text, times)',
    'Repeats text a number of times.',
    {
      min = 2,
      max = 2,
      map = function (v)
        local s = to_text (v[1])
        local times = trunc (to_number (v[2]))
        if times < 0 or #s * times > 32767 then
          return raise ('#VALUE!')
        end
        return string.rep (s, times)
      end,
    }
  )

  define (
    'EXACT',
    'Text',
    'EXACT(text1, text2)',
    'Gives TRUE when two pieces of text are the same, minding case.',
    {
      min = 2,
      max = 2,
      map = function (v)
        return to_text (v[1]) == to_text (v[2])
      end,
    }
  )

  define (
    'TEXT',
    'Text',
    'TEXT(value, format)',
    'Formats a number as text, such as "0.00" or "yyyy-mm-dd".',
    {
      min = 2,
      max = 2,
      map = function (v)
        local x = v[1]
        local fmt = to_text (v[2])
        local n = 0.0
        if type (x) == 'number' then
          n = x
        elseif type (x) == 'string' then
          local parsed = parse_number (x)
          if not parsed then
            return x
          end
          n = parsed
        elseif type (x) == 'boolean' then
          return x and 'TRUE' or 'FALSE'
        end
        return format_number (n, fmt)
      end,
    }
  )

  define (
    'VALUE',
    'Text',
    'VALUE(text)',
    'Turns text that shows a number, a date or a time into a number.',
    {
      min = 1,
      max = 1,
      map = function (v)
        local x = v[1]
        if type (x) == 'number' then
          return x
        end
        if x == nil then
          return 0
        end
        if type (x) == 'string' then
          local n = text_number (x)
          if n then
            return n
          end
        end
        return raise ('#VALUE!')
      end,
    }
  )

  define (
    'CHAR',
    'Text',
    'CHAR(number)',
    'Gives the character with a code from 1 to 255.',
    {
      min = 1,
      max = 1,
      map = function (v)
        local code = trunc (to_number (v[1]))
        if code < 1 or code > 255 then
          return raise ('#VALUE!')
        end
        return utf8.char (code)
      end,
    }
  )

  ---The code of the first character of text.
  ---@param s string
  ---@return integer
  local function first_code (s)
    if s == '' then
      return raise ('#VALUE!')
    end
    local ok, code = pcall (utf8.codepoint, s, 1)
    if ok then
      return code
    end
    return string.byte (s, 1)
  end

  define (
    'CODE',
    'Text',
    'CODE(text)',
    'Gives the code of the first character of text.',
    text1 (first_code)
  )

  define (
    'UNICHAR',
    'Text',
    'UNICHAR(number)',
    'Gives the character with a Unicode number.',
    {
      min = 1,
      max = 1,
      map = function (v)
        local code = trunc (to_number (v[1]))
        if code < 1 or code > 1114111 or (code >= 55296 and code <= 57343) then
          return raise ('#VALUE!')
        end
        return utf8.char (code)
      end,
    }
  )

  define (
    'UNICODE',
    'Text',
    'UNICODE(text)',
    'Gives the Unicode number of the first character of text.',
    text1 (first_code)
  )

  define (
    'T',
    'Text',
    'T(value)',
    'Gives a value when it is text, and empty text otherwise.',
    {
      min = 1,
      max = 1,
      map = function (v)
        if type (v[1]) == 'string' then
          return v[1]
        end
        return ''
      end,
    }
  )

  define (
    'N',
    'Text',
    'N(value)',
    'Gives a value when it is a number, 1 or 0 for TRUE or FALSE, and 0 otherwise.',
    {
      min = 1,
      max = 1,
      map = function (v)
        local x = v[1]
        if type (x) == 'number' then
          return x
        end
        if type (x) == 'boolean' then
          return x and 1 or 0
        end
        return 0
      end,
    }
  )

  ---A number rounded to `digits` decimals and written with a format code.
  ---@param x number
  ---@param digits integer
  ---@param head string The format before the decimals, such as `#,##0`.
  ---@return string
  ---@return number rounded
  local function fixed_text (x, digits, head)
    if digits > 127 then
      error (ERRORS['#VALUE!'], 0)
    end
    local r = round_to (x, digits, 'near')
    local code = head
    if digits > 0 then
      code = code .. '.' .. string.rep ('0', digits)
    end
    return format_number (math.abs (r), code), r
  end

  define (
    'FIXED',
    'Text',
    'FIXED(number, [decimals], [no_commas])',
    'Rounds a number and writes it as text, with commas unless asked not to.',
    {
      min = 1,
      max = 3,
      map = function (v, n)
        local plain = opt_bool (v, n, 3, false)
        local text, r = fixed_text (
          to_number (v[1]),
          opt_int (v, n, 2, 2),
          plain and '0' or '#,##0'
        )
        return (r < 0 and '-' or '') .. text
      end,
    }
  )

  define (
    'DOLLAR',
    'Text',
    'DOLLAR(number, [decimals])',
    'Rounds a number and writes it as money, such as $1,234.57.',
    {
      min = 1,
      max = 2,
      map = function (v, n)
        local text, r =
          fixed_text (to_number (v[1]), opt_int (v, n, 2, 2), '$#,##0')
        -- A negative amount goes in brackets, as the US money format writes it.
        if r < 0 then
          return '(' .. text .. ')'
        end
        return text
      end,
    }
  )

  ---TEXTBEFORE and TEXTAFTER.
  ---@param after boolean
  ---@return Sheet.Function
  local function text_around (after)
    return {
      min = 2,
      max = 6,
      map = function (v, n)
        local s, delim = to_text (v[1]), to_text (v[2])
        local instance = opt_int (v, n, 3, 1)
        local no_case = opt (v, n, 4, 0) ~= 0
        local match_end = opt (v, n, 5, 0) ~= 0
        if instance == 0 then
          return raise ('#VALUE!')
        end
        local starts = {} ---@type integer[]
        if delim ~= '' then
          local hay = no_case and lower (s) or s
          local needle = no_case and lower (delim) or delim
          local i = 1
          while true do
            local a, b = string.find (hay, needle, i, true)
            if not a then
              break
            end
            starts[#starts + 1] = a
            i = b + 1
          end
        end
        local k = instance > 0 and instance or #starts + instance + 1
        local cut ---@type integer?
        if delim == '' then
          cut = instance > 0 and 1 or #s + 1
        elseif k >= 1 and k <= #starts then
          cut = starts[k]
        elseif match_end and instance > 0 and k == #starts + 1 then
          cut = #s + 1
        elseif match_end and instance < 0 and k == 0 then
          -- The start of the text counts as a delimiter with no width.
          if after then
            return s
          end
          return ''
        end
        if not cut then
          if n >= 6 then
            return v[6]
          end
          return raise ('#N/A')
        end
        if after then
          local width = cut <= #s and #delim or 0
          return string.sub (s, cut + width)
        end
        return string.sub (s, 1, cut - 1)
      end,
    }
  end

  define (
    'TEXTBEFORE',
    'Text',
    'TEXTBEFORE(text, delimiter, [instance], [match_mode], [match_end], [if_not_found])',
    'Gives the text before a delimiter.',
    text_around (false)
  )
  define (
    'TEXTAFTER',
    'Text',
    'TEXTAFTER(text, delimiter, [instance], [match_mode], [match_end], [if_not_found])',
    'Gives the text after a delimiter.',
    text_around (true)
  )
end
