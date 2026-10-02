-- log_ansi: the ANSI colour codes programs write in their output. It splits a line into runs
-- of one colour, so the list can colour them, and strips the codes for the plain text.

---A run of text in one colour.
---@class Logs.Segment
---@field text string
---@field fg? integer An ANSI colour from 0 to 15.
---@field bold boolean

---@class Logs.AnsiModule
---@field parse_ansi fun(text: string): Logs.Segment[]
---@field strip_ansi fun(text: string): string

-- Any control character except a tab. The escape that starts a colour code is one.
local CONTROL = '[^%C\t]'

---Applies the numbers of one colour code, such as `1;31`, to the current colour and weight.
---@param params string
---@param fg integer?
---@param bold boolean
---@return integer? fg
---@return boolean bold
local function apply_sgr (params, fg, bold)
  ---@type integer[]
  local codes = {}
  for part in (params .. ';'):gmatch ('([^;:]*)[;:]') do
    codes[#codes + 1] = math.floor (tonumber (part) or 0)
  end
  local i = 1
  while i <= #codes do
    local c = codes[i]
    if c == 0 then
      fg, bold = nil, false
    elseif c == 1 then
      bold = true
    elseif c == 22 then
      bold = false
    elseif c >= 30 and c <= 37 then
      fg = c - 30
    elseif c == 39 then
      fg = nil
    elseif c >= 90 and c <= 97 then
      fg = c - 82
    elseif c == 38 or c == 48 then
      -- 38;5;n picks one of 256 colours, and 38;2;r;g;b gives one exactly. Only the first 16
      -- of the 256 have a theme colour here. The numbers after the others are skipped, so
      -- they are not read as codes of their own.
      local mode = codes[i + 1]
      if mode == 5 then
        local n = codes[i + 2]
        if c == 38 and n and n < 16 then
          fg = n
        end
        i = i + 2
      elseif mode == 2 then
        i = i + 4
      end
    end
    i = i + 1
  end
  return fg, bold
end

---Splits text into runs of one colour. Reset, bold and the 16 foreground colours count.
---Every other escape sequence and control character is dropped.
---@param text string
---@return Logs.Segment[]
local function parse_ansi (text)
  ---@type Logs.Segment[]
  local segs = {}
  if text == '' then
    return segs
  end
  if not text:find (CONTROL) then
    segs[1] = { text = text, bold = false }
    return segs
  end
  local fg = nil ---@type integer?
  local bold = false

  ---@param piece string
  local function add (piece)
    if piece == '' then
      return
    end
    local last = segs[#segs]
    if last and last.fg == fg and last.bold == bold then
      last.text = last.text .. piece
    else
      segs[#segs + 1] = { text = piece, fg = fg, bold = bold }
    end
  end

  local pos = 1
  while pos <= #text do
    local at = text:find (CONTROL, pos)
    if not at then
      add (text:sub (pos))
      break
    end
    add (text:sub (pos, at - 1))
    if text:byte (at) == 27 then
      local params, final, after =
        text:match ('^\27%[([0-?]*)[ -/]*([@-~])()', at)
      if params then
        if final == 'm' then
          fg, bold = apply_sgr (params, fg, bold)
        end
        pos = after
      else
        -- A title or link sequence ends with a bell or with ESC \. One with no end runs to
        -- the end of the line. Anything else is ESC and one or two more characters.
        pos = text:match ('^\27%][^\7\27]*\7()', at)
          or text:match ('^\27%][^\7\27]*\27\\()', at)
          or (text:match ('^\27%]', at) and #text + 1)
          or text:match ('^\27[ -/]*[0-~]()', at)
          or at + 1
      end
    else
      pos = at + 1
    end
  end
  return segs
end

---@param text string
---@return string
local function strip_ansi (text)
  if not text:find (CONTROL) then
    return text
  end
  ---@type string[]
  local parts = {}
  for i, seg in ipairs (parse_ansi (text)) do
    parts[i] = seg.text
  end
  return table.concat (parts)
end

---@type Logs.AnsiModule
local M = {
  parse_ansi = parse_ansi,
  strip_ansi = strip_ansi,
}

return M
