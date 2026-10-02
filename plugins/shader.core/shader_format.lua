-- Numbers and colours as the fields of the builder show them. The canvas and the Preview
-- both use these, so a value reads the same in each.

local M = {}

---A number without the zeros at its end, such as `2` or `0.25`.
---@param v number
---@param places? integer Digits after the point at most. 4 when nil.
---@return string
function M.fmt (v, places)
  if v == math.floor (v) and math.abs (v) < 1e9 then
    return string.format ('%d', v)
  end
  local text = string.format ('%.' .. (places or 4) .. 'f', v)
  return (text:gsub ('0+$', ''):gsub ('%.$', ''))
end

---A colour as #rrggbb from numbers from 0 to 1.
---@param rgb number[]
---@return string
function M.to_hex (rgb)
  local parts = {} ---@type string[]
  for i = 1, 3 do
    local v = math.max (0, math.min (1, tonumber (rgb[i]) or 0))
    parts[i] = string.format ('%02x', math.floor (v * 255 + 0.5))
  end
  return '#' .. table.concat (parts)
end

---Numbers from 0 to 1 from #rrggbb, or nil for any other text.
---@param hex string
---@return number[]?
function M.from_hex (hex)
  local r, g, b = tostring (hex):match ('^#(%x%x)(%x%x)(%x%x)$')
  if not r then
    return nil
  end
  ---@param h string
  ---@return number
  local function part (h)
    return math.floor (tonumber (h, 16) / 255 * 1000 + 0.5) / 1000
  end
  return { part (r), part (g), part (b) }
end

return M
