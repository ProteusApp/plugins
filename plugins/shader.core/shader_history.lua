-- Undo and redo for a shader graph. The history keeps whole documents, and each shares the
-- nodes it did not change with the one before, so a step costs only what changed.
-- Quick changes with the same key, such as the steps of one slider drag, make one step.

local LIMIT = 100
local MERGE_MS = 800

local M = {}

---@param doc Shader.Doc
---@return Shader.History
function M.new (doc)
  return { past = {}, future = {}, doc = doc }
end

---Records a new document. `key` and `now` let quick changes to one thing merge.
---@param h Shader.History
---@param doc Shader.Doc
---@param key? string
---@param now? number Milliseconds.
function M.push (h, doc, key, now)
  local merge = key
    and h.last_key == key
    and now
    and h.last_time
    and now - h.last_time < MERGE_MS
  if not merge then
    h.past[#h.past + 1] = h.doc
    if #h.past > LIMIT then
      table.remove (h.past, 1)
    end
  end
  h.doc = doc
  h.future = {}
  h.last_key, h.last_time = key, now
end

---@param h Shader.History
---@return boolean changed
function M.undo (h)
  local prev = table.remove (h.past)
  if not prev then
    return false
  end
  h.future[#h.future + 1] = h.doc
  h.doc = prev
  h.last_key = nil
  return true
end

---@param h Shader.History
---@return boolean changed
function M.redo (h)
  local nxt = table.remove (h.future)
  if not nxt then
    return false
  end
  h.past[#h.past + 1] = h.doc
  h.doc = nxt
  h.last_key = nil
  return true
end

return M
