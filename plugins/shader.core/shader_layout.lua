-- Where each field of a WGSL uniform struct sits in its buffer, by WGSL's alignment rules,
-- and the words both languages keep for themselves.

---@type table<Shader.UniformType, { align: integer, size: integer }>
local SIZES = {
  float = { align = 4, size = 4 },
  int = { align = 4, size = 4 },
  uint = { align = 4, size = 4 },
  vec2 = { align = 8, size = 8 },
  vec3 = { align = 16, size = 12 },
  vec4 = { align = 16, size = 16 },
}

-- WGSL's keywords and reserved words. A struct field cannot take one as its name.
local WGSL_RESERVED = {} ---@type table<string, boolean>
for word in
  ([[
alias break case const const_assert continue continuing default diagnostic discard else
enable false fn for if let loop override requires return struct switch true var while
NULL Self abstract active alignas alignof as asm asm_fragment async attribute auto await
become binding_array cast catch class co_await co_return co_yield coherent column_major
common compile compile_fragment concept const_cast consteval constexpr constinit crate
debugger decltype delete demote demote_to_helper do dynamic_cast enum explicit export
extends extern external fallthrough filter final finally friend from fxgroup get goto
groupshared highp impl implements import inline instanceof interface layout lowp macro
macro_rules match mediump meta mod module move mut mutable namespace new nil noexcept
noinline nointerpolation noperspective null nullptr of operator package packoffset
partition pass patch pixelfragment precise precision premerge priv protected pub public
readonly ref regardless register reinterpret_cast require resource restrict self set
shared sizeof smooth snorm static static_assert static_cast std subroutine super target
template this thread_local throw trait try type typedef typeid typename typeof union
unless unorm unsafe unsized use using varying virtual volatile wgsl where with writeonly
yield f32 f16 i32 u32 bool vec2 vec3 vec4 mat2x2 mat3x3 mat4x4 array ptr sampler
]]):gmatch ('%S+')
do
  WGSL_RESERVED[word] = true
end

local M = {}

M.sizes = SIZES

---True when WGSL keeps the word for itself.
---@param word string
---@return boolean
function M.reserved (word)
  return WGSL_RESERVED[word] == true
end

---@param n integer
---@param align integer
---@return integer
local function round_up (n, align)
  return math.ceil (n / align) * align
end

---Lays fields out one after another. Each field gets its `offset`, and the struct its size.
---@param fields { name: string, type: Shader.UniformType }[]
---@return Shader.Layout
function M.layout (fields)
  local offset, align = 0, 16
  local out = {} ---@type Shader.LayoutField[]
  for _, f in ipairs (fields) do
    local s = SIZES[f.type] or SIZES.float
    offset = round_up (offset, s.align)
    out[#out + 1] = { name = f.name, type = f.type, offset = offset }
    offset = offset + s.size
    align = math.max (align, s.align)
  end
  return { fields = out, size = math.max (16, round_up (offset, align)) }
end

return M
