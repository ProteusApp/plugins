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

---Every plugin id in the registry, sorted. Only the tests in contracts/ have it.
---@return string[]
function plugin_ids () end

---The table a plugin's init.lua returns, loaded as Proteus loads a plugin it does not trust.
---Only the tests in contracts/ have it.
---@param id string
---@return table
function load_plugin (id) end
