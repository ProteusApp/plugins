-- The value types a shader graph passes along its wires, and how each one reads in GLSL and
-- WGSL. Any wire fits any input: a float spreads to every component, a longer vector drops
-- the components it has too many of, and a shorter one fills the rest with 0 and alpha 1.

---@type table<Shader.Type, integer>
local DIMS = { float = 1, vec2 = 2, vec3 = 3, vec4 = 4 }

---@type Shader.Type[]
local BY_DIM = { 'float', 'vec2', 'vec3', 'vec4' }

---@type table<Shader.Lang, table<Shader.Type, string>>
local NAMES = {
  glsl = { float = 'float', vec2 = 'vec2', vec3 = 'vec3', vec4 = 'vec4' },
  wgsl = { float = 'f32', vec2 = 'vec2f', vec3 = 'vec3f', vec4 = 'vec4f' },
}

local SWIZZLE = { 'x', 'y', 'z', 'w' }

local M = {}

M.names = BY_DIM

---@param t any
---@return boolean
function M.is_type (t)
  return DIMS[t] ~= nil
end

---How many components a type has.
---@param t Shader.Type
---@return integer
function M.dim (t)
  return DIMS[t] or 1
end

---The type with `n` components.
---@param n integer
---@return Shader.Type
function M.of_dim (n)
  return BY_DIM[math.max (1, math.min (4, n))]
end

---The widest of the types given, or float for none.
---@param list Shader.Type[]
---@return Shader.Type
function M.widest (list)
  local n = 1
  for _, t in ipairs (list) do
    n = math.max (n, M.dim (t))
  end
  return M.of_dim (n)
end

---The type's name in one language, such as `vec3` or `vec3f`.
---@param t Shader.Type
---@param lang Shader.Lang
---@return string
function M.name (t, lang)
  return NAMES[lang][t]
end

---A number as a float literal both languages read, such as `1.0` or `0.25`.
---@param n number
---@return string
function M.number (n)
  if n ~= n or n == math.huge or n == -math.huge then
    return '0.0'
  end
  local text = string.format ('%.6g', n)
  if text == '-0' then
    return '0.0'
  end
  if not text:find ('[%.eEn]') then
    text = text .. '.0'
  end
  return text
end

---A literal of type `t` from a list of numbers. A short list repeats its last number.
---@param values number[]?
---@param t Shader.Type
---@param lang Shader.Lang
---@return string
function M.literal (values, t, lang)
  local list = values or {}
  local n = M.dim (t)
  if n == 1 then
    -- WGSL reads a bare 0.5 as an abstract number, and a call on nothing but those is
    -- worked out while the shader is made. The suffix keeps it an f32 like the rest.
    local text = M.number (tonumber (list[1]) or 0)
    return lang == 'wgsl' and (text .. 'f') or text
  end
  local parts = {} ---@type string[]
  local same = true
  for i = 1, n do
    local v = tonumber (list[i] or list[#list]) or 0
    parts[i] = M.number (v)
    if parts[i] ~= parts[1] then
      same = false
    end
  end
  if same then
    return M.name (t, lang) .. '(' .. parts[1] .. ')'
  end
  return M.name (t, lang) .. '(' .. table.concat (parts, ', ') .. ')'
end

---True when an expression can take a swizzle or sit beside an operator as it is: a name,
---a call, or a name with a field.
---@param expr string
---@return boolean
local function is_atom (expr)
  return expr:match ('^[%a_][%w_%.]*$') ~= nil
    or expr:match ('^[%a_][%w_]*%b()$') ~= nil
    or expr:match ('^[%a_][%w_]*%b()%.[xyzw]+$') ~= nil
end

---An expression of type `from` turned into type `to`.
---@param expr string
---@param from Shader.Type
---@param to Shader.Type
---@param lang Shader.Lang
---@return string
function M.convert (expr, from, to, lang)
  local a, b = M.dim (from), M.dim (to)
  if a == b then
    return expr
  end
  local atom = is_atom (expr) and expr or ('(' .. expr .. ')')
  if a == 1 then
    return M.name (to, lang) .. '(' .. expr .. ')'
  end
  if b < a then
    return atom .. '.' .. table.concat (SWIZZLE, '', 1, b)
  end
  -- Longer: pad with zeros, and alpha 1 for a fourth component.
  local pad = {} ---@type string[]
  for i = a + 1, b do
    pad[#pad + 1] = i == 4 and '1.0' or '0.0'
  end
  return M.name (to, lang)
    .. '('
    .. expr
    .. ', '
    .. table.concat (pad, ', ')
    .. ')'
end

return M
