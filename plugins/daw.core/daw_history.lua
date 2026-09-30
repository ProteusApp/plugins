-- daw_history: undo and redo for songs. Songs never change in place, so the history keeps
-- whole songs, and two neighbours share most of their tables.

local M = {}

-- Changes with the same key closer together than this make one undo step.
local COALESCE_MS = 1200

---@param limit? integer
---@param now? fun(): number Milliseconds, for grouping quick changes.
---@return Daw.History
function M.new (limit, now)
  local max = limit or 200
  local clock = now or function ()
    return os.clock () * 1000
  end
  local past = {} ---@type Daw.Song[]
  local future = {} ---@type Daw.Song[]
  local last_key = nil ---@type string?
  local last_time = 0

  ---@type Daw.History
  local h = {
    push = function (song, key)
      local t = clock ()
      future = {}
      if key and key == last_key and t - last_time < COALESCE_MS then
        last_time = t
        return
      end
      past[#past + 1] = song
      if #past > max then
        table.remove (past, 1)
      end
      last_key = key
      last_time = t
    end,
    undo = function (current)
      local song = table.remove (past)
      if not song then
        return nil
      end
      future[#future + 1] = current
      last_key = nil
      return song
    end,
    redo = function (current)
      local song = table.remove (future)
      if not song then
        return nil
      end
      past[#past + 1] = current
      last_key = nil
      return song
    end,
    can_undo = function ()
      return #past > 0
    end,
    can_redo = function ()
      return #future > 0
    end,
    clear = function ()
      past, future, last_key = {}, {}, nil
    end,
    seal = function ()
      last_key = nil
    end,
  }
  return h
end

return M
