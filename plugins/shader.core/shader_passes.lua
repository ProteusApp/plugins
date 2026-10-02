-- Channels and passes, the way Shadertoy has them. A shader reads up to four pictures, the
-- channels iChannel0 to iChannel3, each from a source: a noise or checker texture, an image
-- the user picks, or a buffer. A buffer is another pass of the same shader, drawn into a
-- picture of its own before the image each frame. `x.buffer-a.frag` is Buffer A of the shader
-- `x.frag`, and `x.buffer-b.shader.json` is Buffer B of the graph `x.shader.json`.
--
-- In code, a note in a comment shapes a channel:
--
--   uniform sampler2D u_tex; // @channel 1         u_tex reads iChannel1
--   // @channel 0 buffer-a nearest clamp           iChannel0 starts on Buffer A
--
-- In WGSL a channel is a texture_2d<f32> named iChannel0 to iChannel3, or noted the same way.
-- A sampler named after its texture, such as iChannel0_sampler, filters as that channel says.

local M = {}

M.COUNT = 4

---@type Shader.PassId[]
M.BUFFERS = { 'a', 'b', 'c', 'd' }

-- The endings a pass's file can have, in the order they are looked for.
M.ENDINGS = { '.shader.json', '.frag', '.glsl', '.wgsl' }

---@type table<Shader.SourceKind, boolean>
local KINDS =
  { none = true, noise = true, checker = true, image = true, buffer = true }

---A source from a note's words, such as `buffer-a`, `noise nearest` or `none`. Nil when the
---words name no kind of source.
---@param words string
---@return Shader.ChannelSource?
function M.parse_source (words)
  local kind, buffer, filter, wrap ---@type Shader.SourceKind?, Shader.PassId?, ('linear'|'nearest')?, ('repeat'|'clamp')?
  for word in tostring (words or ''):lower ():gmatch ('[%w%-]+') do
    local letter = word:match ('^buffer%-([a-d])$')
    if letter then
      kind, buffer = 'buffer', letter --[[@as Shader.PassId]]
    elseif word == 'none' or word == 'noise' or word == 'checker' then
      kind = word --[[@as Shader.SourceKind]]
    elseif word == 'linear' or word == 'nearest' then
      filter = word
    elseif word == 'clamp' or word == 'repeat' then
      wrap = word
    end
  end
  if not kind then
    return nil
  end
  return { kind = kind, buffer = buffer, filter = filter, wrap = wrap }
end

---A source as it was stored, checked, or nil when it does not read.
---@param value any
---@return Shader.ChannelSource?
function M.clean_source (value)
  if type (value) ~= 'table' or not KINDS[value.kind] then
    return nil
  end
  ---@type Shader.ChannelSource
  local out = { kind = value.kind }
  if value.kind == 'buffer' then
    local letter = tostring (value.buffer or ''):lower ()
    if not letter:match ('^[a-d]$') then
      return nil
    end
    out.buffer = letter --[[@as Shader.PassId]]
  elseif value.kind == 'image' then
    out.grant = type (value.grant) == 'string' and value.grant or nil
    out.name = type (value.name) == 'string' and value.name or nil
  end
  if value.filter == 'linear' or value.filter == 'nearest' then
    out.filter = value.filter
  end
  if value.wrap == 'repeat' or value.wrap == 'clamp' then
    out.wrap = value.wrap
  end
  return out
end

---How a source reads to a person, such as `Buffer A` or `Noise`.
---@param src Shader.ChannelSource?
---@return string
function M.label (src)
  if not src or src.kind == 'none' then
    return 'Nothing'
  elseif src.kind == 'buffer' then
    return 'Buffer ' .. tostring (src.buffer):upper ()
  elseif src.kind == 'image' then
    return src.name or 'An image'
  end
  return src.kind:sub (1, 1):upper () .. src.kind:sub (2)
end

---How a pass reads to a person: `Image` or `Buffer A`.
---@param pass Shader.PassId
---@return string
function M.pass_label (pass)
  if pass == 'image' then
    return 'Image'
  end
  return 'Buffer ' .. pass:upper ()
end

---The ending of a shader file: `.shader.json` for a graph, or its last one.
---@param path string
---@return string
local function ending_of (path)
  local lower = path:lower ()
  if lower:sub (-#'.shader.json') == '.shader.json' then
    return path:sub (-#'.shader.json')
  end
  return path:match ('%.[%w]+$') or ''
end

---The shader a file belongs to and which pass it is: `image`, or `a` to `d` for a buffer.
---@param path string
---@return string base, Shader.PassId pass
function M.pass_of (path)
  local stem = path:sub (1, #path - #ending_of (path))
  local base, letter =
    stem:match ('^(.*)%.[Bb][Uu][Ff][Ff][Ee][Rr]%-([a-dA-D])$')
  if base then
    return base, letter:lower () --[[@as Shader.PassId]]
  end
  return stem, 'image'
end

---The paths a pass of the shader `base` can have, in the order they are looked for.
---@param base string
---@param pass Shader.PassId
---@return string[]
function M.pass_paths (base, pass)
  local stem = pass == 'image' and base or (base .. '.buffer-' .. pass)
  local out = {} ---@type string[]
  for i, e in ipairs (M.ENDINGS) do
    out[i] = stem .. e
  end
  return out
end

---The path a new buffer of the shader at `path` gets, keeping its ending.
---@param path string
---@param pass Shader.PassId
---@return string
function M.buffer_path (path, pass)
  local base = M.pass_of (path)
  local e = ending_of (path)
  if e:lower () == '.vert' then
    e = '.frag'
  end
  return base .. '.buffer-' .. pass .. e
end

---The channel a sampler or texture of this name reads, from its name alone.
---@param name string
---@return integer?
function M.channel_of_name (name)
  local n = name:match ('^iChannel([0-3])$')
  return n and tonumber (n) or nil
end

---Reads the channel notes in a line's comment. `@channel N` with the words after it.
---@param comment string
---@return integer? index, Shader.ChannelSource? source, boolean? out_of_range
local function note (comment)
  local n, rest = comment:match ('@channel%s+(%d+)([^@]*)')
  if not n then
    return nil
  end
  local index = tonumber (n) --[[@as integer]]
  if index >= M.COUNT then
    return nil, nil, true
  end
  return index, M.parse_source (rest)
end

---Splits a line into its code and the comment after `//`.
---@param line string
---@return string code, string comment
local function split (line)
  local at = line:find ('//', 1, true)
  if at then
    return line:sub (1, at - 1), line:sub (at + 2)
  end
  return line, ''
end

---Adds a name to a channel in a list kept by index.
---@param by table<integer, Shader.Channel>
---@param index integer
---@param name? string
---@param line? integer
---@return Shader.Channel
local function channel (by, index, name, line)
  local c = by[index]
  if not c then
    c = { index = index, names = {}, line = line }
    by[index] = c
  end
  if name then
    c.names[#c.names + 1] = name
  end
  return c
end

---The channels in a list, by index.
---@param by table<integer, Shader.Channel>
---@return Shader.Channel[]
local function sorted (by)
  local out = {} ---@type Shader.Channel[]
  for i = 0, M.COUNT - 1 do
    if by[i] then
      out[#out + 1] = by[i]
    end
  end
  return out
end

---Applies the sources the notes give to the channels that are read.
---@param by table<integer, Shader.Channel>
---@param defaults table<integer, Shader.ChannelSource>
local function give_defaults (by, defaults)
  for i, src in pairs (defaults) do
    if by[i] then
      by[i].source = src
    end
  end
end

---The channels a GLSL shader reads. Every `uniform sampler2D` reads one, from its name
---iChannel0 to iChannel3 or a note `@channel N`. `extra` names channels read without a
---declaration, such as iChannel0 in a short Shadertoy shader.
---@param text string
---@param extra? integer[]
---@return Shader.Channel[] channels, Shader.CompileError[] errors
function M.glsl_channels (text, extra)
  local by = {} ---@type table<integer, Shader.Channel>
  local defaults = {} ---@type table<integer, Shader.ChannelSource>
  local errors = {} ---@type Shader.CompileError[]
  local line_no = 0
  local in_block = false
  for line in (text .. '\n'):gmatch ('([^\n]*)\n') do
    line_no = line_no + 1
    local code, comment = split (line)
    -- Block comments: what they hold declares nothing.
    if in_block then
      local close = code:find ('*/', 1, true)
      code = close and code:sub (close + 2) or ''
      in_block = close == nil
    end
    code = code:gsub ('/%*.-%*/', ' ')
    local open_at = code:find ('/*', 1, true)
    if open_at then
      code = code:sub (1, open_at - 1)
      in_block = true
    end
    local index, src, too_far = note (comment)
    if too_far then
      errors[#errors + 1] = {
        message = 'There are four channels, @channel 0 to @channel 3.',
        line = line_no,
        severity = 'warning',
      }
    end
    for _, q in ipairs ({ 'highp', 'mediump', 'lowp' }) do
      code = code:gsub ('%f[%w_]' .. q .. '%f[^%w_]', '')
    end
    local ty, names =
      code:match ('^%s*uniform%s+([%w_]*sampler[%w_]*)%s+([%w_%s,%[%]]+);')
    if ty and names then
      for name in tostring (names):gsub ('%b[]', ''):gmatch ('[%w_]+') do
        local i = M.channel_of_name (name) or index
        if ty ~= 'sampler2D' then
          errors[#errors + 1] = {
            message = 'The preview binds only sampler2D, so the '
              .. ty
              .. ' '
              .. name
              .. ' reads nothing.',
            line = line_no,
            severity = 'warning',
          }
        elseif i then
          channel (by, i, name, line_no)
          if src then
            defaults[i] = src
          end
        else
          errors[#errors + 1] = {
            message = 'Nothing is bound to '
              .. name
              .. '. Name it iChannel0 to iChannel3, or add a note such as // @channel 0.',
            line = line_no,
            severity = 'warning',
          }
        end
      end
    elseif index and src then
      defaults[index] = src
    end
  end
  for _, i in ipairs (extra or {}) do
    channel (by, i, 'iChannel' .. i)
  end
  give_defaults (by, defaults)
  return sorted (by), errors
end

---@param text string
---@param word string
---@return integer
local function count_uses (text, word)
  local n = 0
  for _ in text:gmatch ('%f[%w_]' .. word:gsub ('%p', '%%%0') .. '%f[^%w_]') do
    n = n + 1
  end
  return n
end

---The resources a WGSL module binds, and the channels it reads. Every `texture_2d<f32>` reads
---a channel, from its name iChannel0 to iChannel3 or a note `@channel N`. A sampler filters
---as the channel of the texture it is named after, such as iChannel0_sampler, says.
---@param text string The module as written, notes and all.
---@param code string The module with its comments blanked out, for finding uses.
---@return Shader.Binding[] bindings, Shader.Channel[] channels, Shader.CompileError[] errors
function M.wgsl_resources (text, code)
  local bindings = {} ---@type Shader.Binding[]
  local by = {} ---@type table<integer, Shader.Channel>
  local defaults = {} ---@type table<integer, Shader.ChannelSource>
  local errors = {} ---@type Shader.CompileError[]
  local textures = {} ---@type table<string, integer>
  local samplers = {} ---@type { b: Shader.Binding, note?: integer }[]
  local line_no = 0
  for line in (text .. '\n'):gmatch ('([^\n]*)\n') do
    line_no = line_no + 1
    local decl, comment = split (line)
    local index, src, too_far = note (comment)
    if too_far then
      errors[#errors + 1] = {
        message = 'There are four channels, @channel 0 to @channel 3.',
        line = line_no,
        severity = 'warning',
      }
    end
    local group = tonumber (decl:match ('@group%s*%(%s*(%d+)%s*%)'))
    local slot = tonumber (decl:match ('@binding%s*%(%s*(%d+)%s*%)'))
    local name, ty = decl:match ('%f[%w_]var%s+([%w_]+)%s*:%s*([^;=]+)')
    local uniform_name = decl:match ('%f[%w_]var%s*<%s*uniform%s*>%s*([%w_]+)')
    local found = false
    if uniform_name and not (group and slot) then
      found = true
      errors[#errors + 1] = {
        message = 'Give '
          .. uniform_name
          .. ' its @group and @binding on the same line, so the preview can bind it.',
        line = line_no,
        severity = 'warning',
      }
    elseif uniform_name then
      found = true
      bindings[#bindings + 1] = {
        group = group --[[@as integer]],
        binding = slot --[[@as integer]],
        kind = 'uniforms',
        name = uniform_name,
        used = count_uses (code, uniform_name) > 1,
      }
    elseif name and ty then
      ty = ty:gsub ('%s+', '')
      if ty == 'texture_2d<f32>' or ty == 'sampler' then
        found = true
        if not (group and slot) then
          errors[#errors + 1] = {
            message = 'Give '
              .. name
              .. ' its @group and @binding on the same line, so the preview can bind it.',
            line = line_no,
            severity = 'warning',
          }
        else
          ---@type Shader.Binding
          local b = {
            group = group,
            binding = slot,
            kind = ty == 'sampler' and 'sampler' or 'texture',
            name = name,
            used = count_uses (code, name) > 1,
          }
          bindings[#bindings + 1] = b
          if b.kind == 'texture' then
            local i = M.channel_of_name (name) or index
            if i then
              b.channel = i
              textures[name] = i
              channel (by, i, name, line_no)
              if src then
                defaults[i] = src
              end
            else
              errors[#errors + 1] = {
                message = 'Nothing is bound to '
                  .. name
                  .. '. Name it iChannel0 to iChannel3, or add a note such as // @channel 0.',
                line = line_no,
                severity = 'warning',
              }
            end
          else
            samplers[#samplers + 1] = { b = b, note = index }
          end
        end
      elseif ty:match ('^texture') or ty:match ('^sampler') then
        found = true
        errors[#errors + 1] = {
          message = 'The preview binds only texture_2d<f32> and sampler, so '
            .. name
            .. ' reads nothing.',
          line = line_no,
          severity = 'warning',
        }
      end
    end
    if not found and index and src then
      defaults[index] = src
    end
  end
  -- A sampler filters as the channel it names, or as the one its note gives.
  for _, s in ipairs (samplers) do
    local own = s.b.name
    local tex = own:match ('^(.-)_?[Ss]ampler$')
    s.b.channel = (tex and textures[tex]) or s.note
  end
  give_defaults (by, defaults)
  return bindings, sorted (by), errors
end

return M
