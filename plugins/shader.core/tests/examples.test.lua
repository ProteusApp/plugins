-- The example shaders in shader.docs/examples: the graphs match the Lua that builds them, and every
-- example, graph or code, gives the preview something to run.

local compile = require ('shader_compile') --[[@as Shader.CompileModule]]
local examples = require ('shader_examples') --[[@as Shader.ExamplesModule]]
local file = require ('shader_file') --[[@as Shader.FileModule]]
local source = require ('shader_source') --[[@as Shader.SourceModule]]

local EXAMPLES = 'plugins/shader.docs/examples/'

test ('each example graph matches shader_examples.lua', function ()
  for _, name in ipairs (examples.names) do
    local path = EXAMPLES .. name .. file.EXTENSION
    local want = file.save (examples.build (name) --[[@as Shader.Doc]])
    if update then
      write (path, want)
    end
    ok (
      read (path) == want,
      path .. ' is out of date. Run npm test -- --update to write it again.'
    )
  end
end)

test ('each example graph compiles cleanly', function ()
  for _, name in ipairs (examples.names) do
    local doc = assert (file.load (read (EXAMPLES .. name .. file.EXTENSION)))
    local r = compile.compile (doc)
    ok (r.ok, name .. ': ' .. (r.errors[1] and r.errors[1].message or ''))
  end
end)

test ('each example code shader has what the preview needs', function ()
  for _, name in ipairs ({ 'waves.frag', 'raymarch.frag', 'shadertoy.frag' }) do
    local _, errors = source.glsl_program (read (EXAMPLES .. name))
    eq (errors, {}, name)
  end
  local p, errors = source.wgsl_program (read (EXAMPLES .. 'tunnel.wgsl'))
  eq (errors, {})
  ok (#p.uniforms > 0)
end)
