-- Builds a shader into files that stand on their own: the complete GLSL vertex and fragment
-- shaders, the WGSL module, the code of each buffer, a page that runs them in any browser, a
-- JSON list of the uniforms and channels, and a README that says how to feed them.

local file = require ('shader_file') --[[@as Shader.FileModule]]
local pages = require ('shader_pages') --[[@as Shader.PagesModule]]
local passes = require ('shader_passes') --[[@as Shader.PassesModule]]

local M = {}

---A value as JavaScript, safe inside a script element.
---@param value any
---@return string
local function js (value)
  return (file.encode (value):gsub ('</', '<\\/'))
end

---A file name from a shader's name.
---@param name string
---@return string
function M.stem (name)
  local s = tostring (name or ''):lower ():gsub ('[^%w%-_]+', '-')
  s = s:gsub ('^%-+', ''):gsub ('%-+$', '')
  return s ~= '' and s or 'shader'
end

---@param list Shader.Uniform[]
---@return table[]
local function uniform_rows (list)
  local out = file.array ({}) ---@type table[]
  for _, u in ipairs (list) do
    out[#out + 1] = {
      key = u.key,
      glsl = u.glsl,
      offset = u.offset,
      type = u.type,
      value = u.value,
      min = u.min,
      max = u.max,
      color = u.color or nil,
    }
  end
  return out
end

---What a page needs of a channel's source: no grant, since the image sits beside the page.
---@param src Shader.ChannelSource?
---@return table?
local function page_source (src)
  if not src or src.kind == 'none' then
    return nil
  end
  return {
    kind = src.kind,
    buffer = src.buffer,
    name = src.name,
    filter = src.filter,
    wrap = src.wrap,
  }
end

---The channels a program reads, each with what it shows, for a page.
---@param p Shader.Program
---@param sources table<integer, Shader.ChannelSource>?
---@return table[]
local function page_channels (p, sources)
  local out = file.array ({}) ---@type table[]
  for _, c in ipairs (p.channels or {}) do
    out[#out + 1] = {
      index = c.index,
      names = file.array (c.names),
      source = page_source ((sources or {})[c.index]),
    }
  end
  return out
end

---One pass of the GLSL page.
---@param id Shader.PassId
---@param p Shader.Program
---@param sources table<integer, Shader.ChannelSource>?
---@return table
local function glsl_pass (id, p, sources)
  return {
    id = id,
    vertex = p.vertex or '',
    fragment = p.source,
    uniforms = uniform_rows (p.uniforms),
    channels = page_channels (p, sources),
  }
end

---One pass of the WGSL page.
---@param id Shader.PassId
---@param p Shader.Program
---@param sources table<integer, Shader.ChannelSource>?
---@return table
local function wgsl_pass (id, p, sources)
  return {
    id = id,
    module = p.source,
    vertex_entry = p.vertex_entry or 'vs_main',
    fragment_entry = p.fragment_entry or 'fs_main',
    layout = {
      size = p.layout and p.layout.size or 16,
      fields = file.array (p.layout and p.layout.fields or {}),
    },
    uniforms = uniform_rows (p.uniforms),
    bindings = file.array (p.bindings or {}),
    channels = page_channels (p, sources),
  }
end

---The README's lines about the channels of one pass.
---@param label string
---@param p Shader.Program
---@param sources table<integer, Shader.ChannelSource>?
---@param into string[]
local function channel_lines (label, p, sources, into)
  for _, c in ipairs (p.channels or {}) do
    local src = (sources or {})[c.index]
    local what = passes.label (src)
    if src and src.kind == 'image' then
      what = '`'
        .. tostring (src.name or 'an image')
        .. '`, which goes beside the page'
    end
    into[#into + 1] = '| '
      .. label
      .. ' | `iChannel'
      .. c.index
      .. '` | `'
      .. table.concat (c.names, '`, `')
      .. '` | '
      .. what
      .. ' |'
  end
end

---The files a build writes, by name.
---@param input Shader.BuildInput
---@return table<string, string>
function M.files (input)
  local stem = M.stem (input.name)
  local title = tostring (input.name or stem):gsub ('[<>&]', '')
  local out = {} ---@type table<string, string>
  local buffers = input.buffers or {}
  -- A language builds only when every pass has code in it.
  ---@param lang Shader.Lang
  ---@return Shader.Program?
  local function whole (lang)
    local p = input[lang] ---@type Shader.Program?
    if not p then
      return nil
    end
    for _, b in ipairs (buffers) do
      if not b[lang] then
        return nil
      end
    end
    return p
  end
  local glsl = whole ('glsl')
  local wgsl = whole ('wgsl')
  ---@type string[]
  local readme = {
    '# ' .. title,
    '',
    'Built with the Proteus shader builder. Every file here stands on its own.',
    '',
    '| File | What it holds |',
    '|------|---------------|',
  }
  if glsl then
    out[stem .. '.frag'] = glsl.source
    out[stem .. '.vert'] = glsl.vertex or ''
    local list = file.array ({}) ---@type table[]
    for _, b in ipairs (buffers) do
      out[stem .. '.buffer-' .. b.id .. '.frag'] = b.glsl.source
      list[#list + 1] =
        glsl_pass (b.id, b.glsl --[[@as Shader.Program]], b.channels)
    end
    list[#list + 1] = glsl_pass ('image', glsl, input.channels)
    out['index.html'] =
      pages.fill (pages.GLSL, { TITLE = title, PASSES = js (list) })
    readme[#readme + 1] = '| `'
      .. stem
      .. '.frag` | The GLSL ES 3.00 fragment shader, for WebGL 2 and OpenGL ES 3 |'
    readme[#readme + 1] = '| `'
      .. stem
      .. '.vert` | Its vertex shader: one triangle over the whole picture, from `gl_VertexID`. Draw 3 vertices with no attributes |'
    for _, b in ipairs (buffers) do
      readme[#readme + 1] = '| `'
        .. stem
        .. '.buffer-'
        .. b.id
        .. '.frag` | '
        .. passes.pass_label (b.id)
        .. ' in GLSL, with the same vertex shader |'
    end
  end
  if wgsl then
    out[stem .. '.wgsl'] = wgsl.source
    local list = file.array ({}) ---@type table[]
    for _, b in ipairs (buffers) do
      out[stem .. '.buffer-' .. b.id .. '.wgsl'] = b.wgsl.source
      list[#list + 1] =
        wgsl_pass (b.id, b.wgsl --[[@as Shader.Program]], b.channels)
    end
    list[#list + 1] = wgsl_pass ('image', wgsl, input.channels)
    out[glsl and 'webgpu.html' or 'index.html'] =
      pages.fill (pages.WGSL, { TITLE = title, PASSES = js (list) })
    readme[#readme + 1] = '| `'
      .. stem
      .. '.wgsl` | The WGSL module for WebGPU, with the vertex entry point `'
      .. (wgsl.vertex_entry or 'vs_main')
      .. '` and the fragment entry point `'
      .. (wgsl.fragment_entry or 'fs_main')
      .. '`. Draw 3 vertices |'
    for _, b in ipairs (buffers) do
      readme[#readme + 1] = '| `'
        .. stem
        .. '.buffer-'
        .. b.id
        .. '.wgsl` | '
        .. passes.pass_label (b.id)
        .. ' in WGSL |'
    end
  end
  if glsl then
    readme[#readme + 1] =
      '| `index.html` | Runs the GLSL shader in a browser with WebGL 2 |'
    if wgsl then
      readme[#readme + 1] =
        '| `webgpu.html` | Runs the WGSL shader in a browser with WebGPU |'
    end
  elseif wgsl then
    readme[#readme + 1] =
      '| `index.html` | Runs the WGSL shader in a browser with WebGPU |'
  end
  readme[#readme + 1] = '| `uniforms.json` | Each uniform: '
    .. (glsl and 'its GLSL name, ' or '')
    .. (wgsl and 'its byte offset in the WGSL buffer, ' or '')
    .. 'its type and its value |'
  readme[#readme + 1] = ''
  readme[#readme + 1] = '## Uniforms'
  readme[#readme + 1] = ''
  if glsl and glsl.shadertoy then
    readme[#readme + 1] =
      'Set these every frame: `iResolution` (pixels, and 1), `iTime` (seconds), `iTimeDelta`, `iFrame` and `iMouse`, as Shadertoy does.'
  elseif glsl then
    readme[#readme + 1] =
      'Set these every frame: `u_resolution` (pixels), `u_time` (seconds), `u_frame`, and `u_mouse` (x and y in pixels from the bottom left, z is 1 while the button is down).'
  end
  if wgsl then
    readme[#readme + 1] = (
      glsl and 'WGSL reads the same values from' or 'Set these every frame in'
    )
      .. ' the `resolution`, `time`, `frame` and `mouse` fields of its `Uniforms` struct, bound at group 0, binding 0. `uniforms.json` gives the offset of each field in the buffer.'
  end
  local main = glsl or wgsl
  local list = main and main.uniforms or {}
  if #list > 0 then
    readme[#readme + 1] = ''
    readme[#readme + 1] = '| Name | Type | Value | Range |'
    readme[#readme + 1] = '|------|------|-------|-------|'
    for _, u in ipairs (list) do
      local values = {} ---@type string[]
      for i, v in ipairs (u.value) do
        values[i] = string.format ('%g', v)
      end
      readme[#readme + 1] = '| `'
        .. (u.glsl or u.key)
        .. '` | '
        .. u.type
        .. (u.color and ' (colour)' or '')
        .. ' | '
        .. table.concat (values, ', ')
        .. ' | '
        .. (u.color and '0 to 1' or string.format ('%g to %g', u.min, u.max))
        .. ' |'
    end
  end
  -- Passes and channels, when the shader has them.
  local channel_rows = {} ---@type string[]
  if main then
    for _, b in ipairs (buffers) do
      channel_lines (
        passes.pass_label (b.id),
        (glsl and b.glsl or b.wgsl) --[[@as Shader.Program]],
        b.channels,
        channel_rows
      )
    end
    channel_lines ('Image', main, input.channels, channel_rows)
  end
  if #buffers > 0 or #channel_rows > 0 then
    readme[#readme + 1] = ''
    readme[#readme + 1] = '## Passes and channels'
    readme[#readme + 1] = ''
    if #buffers > 0 then
      readme[#readme + 1] =
        'Each frame the buffers draw in order, each into two pictures the size of the canvas that take turns, so a buffer reads its own last frame. Then the image draws on the canvas. A channel that reads a buffer gets its newest picture.'
      readme[#readme + 1] = ''
    end
    if #channel_rows > 0 then
      readme[#readme + 1] = '| Pass | Channel | Read as | Shows |'
      readme[#readme + 1] = '|------|---------|---------|-------|'
      for _, row in ipairs (channel_rows) do
        readme[#readme + 1] = row
      end
      readme[#readme + 1] = ''
      readme[#readme + 1] =
        'Noise and Checker are textures of 256 by 256 pixels the page makes. An image goes beside the page under its own name, and a browser loads it only when the folder is served, such as with `npx serve`, not opened as a file.'
    end
  end
  readme[#readme + 1] = ''
  out['README.md'] = table.concat (readme, '\n')
  ---@param sources table<integer, Shader.ChannelSource>?
  ---@param p Shader.Program
  ---@return table
  local function channel_data (p, sources)
    return page_channels (p, sources)
  end
  local buffer_data = file.array ({}) ---@type table[]
  for _, b in ipairs (buffers) do
    local p = (glsl and b.glsl or b.wgsl) --[[@as Shader.Program?]]
    buffer_data[#buffer_data + 1] = {
      id = b.id,
      glsl = glsl and b.glsl and uniform_rows (b.glsl.uniforms) or nil,
      wgsl = wgsl and b.wgsl and uniform_rows (b.wgsl.uniforms) or nil,
      channels = p and channel_data (p, b.channels) or nil,
    }
  end
  out['uniforms.json'] = file.encode ({
    name = title,
    glsl = glsl and uniform_rows (glsl.uniforms) or nil,
    wgsl = wgsl and {
      buffer_size = wgsl.layout and wgsl.layout.size or 0,
      fields = file.array (wgsl.layout and wgsl.layout.fields or {}),
      uniforms = uniform_rows (wgsl.uniforms),
    } or nil,
    channels = main and #(main.channels or {}) > 0 and channel_data (
      main,
      input.channels
    ) or nil,
    buffers = #buffers > 0 and buffer_data or nil,
  }) .. '\n'
  return out
end

return M
