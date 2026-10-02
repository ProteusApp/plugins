---@meta

-- The globals scripts/lua-test.mjs gives a plugin's tests. proteus_tests.yml tells selene the
-- same thing.

---Declares a test.
---@param name string
---@param fn fun()
function test (name, fn) end

---Fails unless the two values are deeply equal, and shows the difference.
---@param actual any
---@param expected any
---@param msg? string
function eq (actual, expected, msg) end

---Fails unless the value is truthy.
---@param value any
---@param msg? string
function ok (value, msg) end

---Reads a file, from the top of the registry.
---@param path string
---@return string
function read (path) end

---Writes a file. Only call it when `update` is true.
---@param path string
---@param text string
function write (path, text) end

---True when the tests run with --update.
---@type boolean
update = false

---Compiles shader code with a real compiler: glslangValidator for GLSL ES, naga for WGSL.
---True when it compiles, false and the compiler's messages when it does not, and nil and why
---when the compiler is not installed. With SHADER_TOOLS=required, a missing compiler fails.
---@param lang 'glsl'|'wgsl'
---@param stage 'fragment'|'vertex' WGSL checks the whole module.
---@param source string
---@return boolean? ok, string? messages
function shader_check (lang, stage, source) end
