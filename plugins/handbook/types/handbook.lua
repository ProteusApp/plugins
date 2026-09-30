---@meta

-- Types for the `handbook` service. Get it with `app.try_use('handbook')`, and list `handbook`
-- in `optional`. Most plugins need none of this: a `handbook` folder of Markdown files in the
-- plugin's own folder adds its pages by itself.

---A page a plugin adds from code.
---
---```lua
---local handbook = app.try_use('handbook') --[[@as Handbook.Service?]]
---if handbook then
---  handbook.add({ id = 'status', title = 'Build status', markdown = '# Build status' })
---end
---```
---@class Handbook.PageSpec
---@field id string Unique within the plugin, such as `'status'`. The page's id is the plugin's id, a `/`, and this.
---@field markdown string The page's text.
---@field title? string The page's name. The first `# ` heading names it when nil.
---@field section? string The group it is listed under. The plugin's name when nil.
---@field order? number Sorts it within its section, lowest first. 100 when nil.
---@field keywords? string Words search finds it by, beyond its title, headings and text.

---A page added from code.
---@class Handbook.PageHandle
---@field id string The page's id, such as `'my.plugin/status'`.
---@field set fun(markdown: string) Replaces the page's text.
---@field remove fun() Takes the page away now instead of when the plugin stops.

---@class Handbook.PageInfo
---@field id string Such as `'core.commands/commands'`.
---@field title string
---@field section string
---@field origin 'file'|'code'|'types' Where the page comes from.
---@field active boolean False when its plugin is not running.

---@class Handbook.SearchHit
---@field id string The page's id.
---@field anchor? string The heading's anchor, for a match in a heading or under one.
---@field label string The page's title or the heading's text.
---@field context string The section, or the title of the page the heading is on.
---@field snippet? string Text around the match, for a match in a page's text.

---The Handbook: documentation pages every plugin can add to.
---@class Handbook.Service
local Handbook = {}

---Adds a page. It goes away when the plugin stops.
---@param spec Handbook.PageSpec
---@return Handbook.PageHandle
function Handbook.add (spec) end

---Shows the Handbook at a page, such as `'core.commands/commands#register'`, or at its
---contents when `ref` is nil. Returns false when there is no such page.
---@param ref? string
---@return boolean
function Handbook.open (ref) end

---Every page, in the order of the contents.
---@return Handbook.PageInfo[]
function Handbook.pages () end

---Finds pages and headings, best first.
---@param query string
---@param limit? integer 20 when nil.
---@return Handbook.SearchHit[]
function Handbook.find (query, limit) end
