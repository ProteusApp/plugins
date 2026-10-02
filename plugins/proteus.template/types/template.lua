---@meta

-- Types for the `template` service. lua-language-server reads them to check the code of a
-- plugin that uses the service, and the Handbook makes a Reference page from them. Nothing
-- here runs.

---------------------------------------------------------------------------------------------
-- template (proteus.template)
---------------------------------------------------------------------------------------------

---Greetings, from another plugin. Get it with `app.try_use ('template')`, and list
---`proteus.template` in `optional`.
---
---```lua
---local greetings = app.try_use ('template') --[[@as Template.Service?]]
---if greetings then
---  greetings.greet ('Ada')
---end
---```
---@class Template.Service
local Template = {}

---Says a greeting to `name`, or to the world when it is nil, the way the command does: the
---panel lists it and the file holds it.
---@param name? string
---@return string text The greeting, such as `Hello, Ada!`.
function Template.greet (name) end

---Every greeting said so far, newest first.
---@return string[]
function Template.list () end
