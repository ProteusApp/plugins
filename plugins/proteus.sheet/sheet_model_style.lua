-- sheet_model_style: the styles of the Sheet app's cells. A style is a shared table that never
-- changes once made: `intern` gives the one table for a set of fields, so equal styles can be
-- compared with `==`. A cell's own style lies over its row and column styles, and patches
-- change some fields of a style and leave the rest. The module is pure: sheet_model keeps the
-- styles of a sheet, and this module only makes and compares them.

---@class Sheet.ModelStyleModule
local M = {}

M.STYLE_FIELDS = {
  'bold',
  'italic',
  'underline',
  'strike',
  'size',
  'color',
  'fill',
  'align',
  'valign',
  'wrap',
  'format',
  'border_top',
  'border_right',
  'border_bottom',
  'border_left',
  'border_color',
}

-- The value an own style holds to cancel a row or column field. Each is also the default.
M.RESET = {
  bold = false,
  italic = false,
  underline = false,
  strike = false,
  wrap = false,
  size = 13,
  color = 'none',
  fill = 'none',
  align = 'general',
  valign = 'bottom',
  format = 'General',
  border_top = 'none',
  border_right = 'none',
  border_bottom = 'none',
  border_left = 'none',
  border_color = 'none',
}

local FLAGS = {
  bold = true,
  italic = true,
  underline = true,
  strike = true,
  wrap = true,
}
local ALIGNS = { left = true, center = true, right = true, general = true }
local VALIGNS = { top = true, middle = true, bottom = true }
local LINES = {
  thin = true,
  medium = true,
  thick = true,
  dashed = true,
  dotted = true,
  double = true,
  none = true,
}
local SIDES = { 'border_top', 'border_right', 'border_bottom', 'border_left' }

---A field's value when it is valid, or nil.
---@param field string
---@param v any
---@return any
local function checked (field, v)
  if v == nil then
    return nil
  end
  if FLAGS[field] then
    if type (v) == 'boolean' then
      return v
    end
    return nil
  end
  if field == 'size' then
    local n = tonumber (v)
    if n and n > 0 and n < 1000 then
      return math.tointeger (n) or n
    end
    return nil
  end
  if type (v) ~= 'string' or v == '' then
    return nil
  end
  if field == 'align' then
    return ALIGNS[v] and v or nil
  elseif field == 'valign' then
    return VALIGNS[v] and v or nil
  elseif field ~= 'border_color' and string.sub (field, 1, 7) == 'border_' then
    return LINES[v] and v or nil
  end
  return v
end

---True when a field's value is the default.
---@param field string
---@param v any
---@return boolean
local function is_default (field, v)
  if v == nil or v == false then
    return true
  end
  if field == 'format' then
    return type (v) == 'string' and string.lower (v) == 'general'
  end
  return v == M.RESET[field]
end
M.is_default = is_default

---@type table<string, Sheet.Style>
local interned = setmetatable ({}, { __mode = 'v' })

---The shared table for a style, or nil when it sets nothing. Fields of the wrong type are
---dropped.
---@param t any
---@return Sheet.Style?
local function intern (t)
  if type (t) ~= 'table' then
    return nil
  end
  local parts = {} ---@type string[]
  local out = {} ---@type table<string, any>
  local any = false
  for i, field in ipairs (M.STYLE_FIELDS) do
    local v = checked (field, t[field])
    if v ~= nil then
      out[field] = v
      any = true
      parts[i] = type (v) == 'number' and string.format ('%.10g', v)
        or tostring (v)
    else
      parts[i] = ''
    end
  end
  if not any then
    return nil
  end
  local key = table.concat (parts, '\31')
  local hit = interned[key]
  if hit then
    return hit
  end
  local style = out --[[@as Sheet.Style]]
  interned[key] = style
  return style
end
M.intern = intern

---@param style? Sheet.Style
---@return table<string, any>
local function fields_of (style)
  local out = {} ---@type table<string, any>
  if style then
    for k, v in
      pairs (style --[[@as table<string, any>]])
    do
      out[k] = v
    end
  end
  return out
end

---A plain copy of a style, safe to hand out and change.
---@param style? Sheet.Style
---@return Sheet.Style?
function M.copy_style (style)
  if not style then
    return nil
  end
  return fields_of (style) --[[@as Sheet.Style]]
end

---@type table<Sheet.Style, table<Sheet.Style, Sheet.Style>>
local layered = setmetatable ({}, { __mode = 'k' })

---The style `top` laid over `base`.
---@param base? Sheet.Style
---@param top? Sheet.Style
---@return Sheet.Style?
local function layer (base, top)
  if not base then
    return top
  end
  if not top then
    return base
  end
  local memo = layered[base]
  if not memo then
    memo = setmetatable ({}, { __mode = 'k' })
    layered[base] = memo
  end
  local hit = memo[top]
  if hit then
    return hit
  end
  local t = fields_of (base)
  for k, v in
    pairs (top --[[@as table<string, any>]])
  do
    t[k] = v
  end
  hit = intern (t) --[[@as Sheet.Style]]
  memo[top] = hit
  return hit
end
M.layer = layer

-- The style of a cell with no style. Never change it.
local EMPTY = {} ---@type Sheet.Style
M.EMPTY = EMPTY

---@type table<Sheet.Style, Sheet.Style>
local cleaned = setmetatable ({}, { __mode = 'k' })

---A style without its reset and default values, as it shows.
---@param style? Sheet.Style
---@return Sheet.Style
local function clean (style)
  if not style then
    return EMPTY
  end
  local hit = cleaned[style]
  if hit then
    return hit
  end
  local t = {} ---@type table<string, any>
  for k, v in
    pairs (style --[[@as table<string, any>]])
  do
    if not is_default (k, v) then
      t[k] = v
    end
  end
  hit = intern (t) or EMPTY
  cleaned[style] = hit
  return hit
end
M.clean = clean

---A row or column style with a patch applied. A field set to false goes, or becomes its reset
---value when `keep` says a style below it sets the field.
---@param style? Sheet.Style
---@param patch Sheet.StylePatch
---@param keep? table<string, boolean>
---@return Sheet.Style?
local function patched (style, patch, keep)
  local t = fields_of (style)
  for k, v in
    pairs (patch --[[@as table<string, any>]])
  do
    if is_default (k, v) then
      if keep and keep[k] then
        t[k] = M.RESET[k]
      else
        t[k] = nil
      end
    else
      t[k] = v
    end
  end
  return intern (t)
end

---A cell's own style after a patch, given the style it inherits from its row and column, so
---that the cell shows every patched field as the patch says. A field the row or column
---already gives is left out, and a default the row or column overrides becomes a reset.
---@param own? Sheet.Style
---@param patch Sheet.StylePatch
---@param inherited Sheet.Style
---@return Sheet.Style?
local function cell_patch (own, patch, inherited)
  local t = fields_of (own)
  local have = inherited --[[@as table<string, any>]]
  for k, v in
    pairs (patch --[[@as table<string, any>]])
  do
    if is_default (k, v) then
      if have[k] ~= nil then
        t[k] = M.RESET[k]
      else
        t[k] = nil
      end
    elseif have[k] == v then
      t[k] = nil
    else
      t[k] = v
    end
  end
  return intern (t)
end
M.cell_patch = cell_patch

---A style without some fields.
---@param style? Sheet.Style
---@param fields string[]
---@return Sheet.Style?
local function strip (style, fields)
  if not style then
    return nil
  end
  local t = fields_of (style)
  for _, k in ipairs (fields) do
    t[k] = nil
  end
  return intern (t)
end

---A patch that sets every field to what `full` shows, and every other field to the default.
---@param full Sheet.Style
---@return Sheet.StylePatch
local function full_patch (full)
  local patch = {} ---@type table<string, any>
  local f = full --[[@as table<string, any>]]
  for _, k in ipairs (M.STYLE_FIELDS) do
    local v = f[k]
    if v == nil or is_default (k, v) then
      patch[k] = false
    else
      patch[k] = v
    end
  end
  return patch --[[@as Sheet.StylePatch]]
end

---The patch fields that are real style fields.
---@param patch Sheet.StylePatch
---@return string[]
local function patch_fields (patch)
  local out = {} ---@type string[]
  local p = patch --[[@as table<string, any>]]
  for _, k in ipairs (M.STYLE_FIELDS) do
    if p[k] ~= nil then
      out[#out + 1] = k
    end
  end
  return out
end

M.fields_of = fields_of
M.patched = patched
M.strip = strip
M.full_patch = full_patch
M.patch_fields = patch_fields
M.SIDES = SIDES

return M
