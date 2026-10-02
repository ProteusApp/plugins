-- logs_detail: the log viewer's detail panel. It shows the line picked in the list whole, with
-- its number, level and time, the fields its format shows as columns, and lays out the JSON
-- the line ends with. The arrow keys move the pick up and down the list. The log viewer's
-- init.lua attaches it to the context its modules share.

local lf = require ('log_filter') --[[@as Logs.FilterModule]]

---@class Logs.DetailModule
local M = {}

---Adds the detail panel to `ctx`.
---@param ctx Logs.Ctx
function M.attach (ctx)
  local ui = ctx.ui
  local LEVEL_NAMES = ctx.level_names
  local detail, detail_title = ctx.detail, ctx.detail_title
  local detail_text, json_box = ctx.detail_text, ctx.json_box
  local selection_css = ctx.selection_css
  local set_follow = ctx.set_follow
  local reveal, locate, id_of, tag_of =
    ctx.reveal, ctx.locate, ctx.id_of, ctx.tag_of

  local json_view = nil ---@type Proteus.El?

  local function close_detail ()
    ctx.selected = nil
    selection_css:set ('')
    detail:show (false)
  end

  ---@param line Logs.Line
  local function open_detail (line)
    ctx.selected = line
    selection_css:set (
      '.logs-list .logs-row[data-item="'
        .. id_of (line)
        .. '"] { background: var(--selection); }'
    )
    local from = nil ---@type string?
    if ctx.merged then
      local tag = tag_of (line)
      from = tag and tag.name or nil
    end
    detail_title:text (
      (from and (from .. '  ·  ') or '')
        .. 'Line '
        .. line.n
        .. '  ·  '
        .. LEVEL_NAMES[line.level]
        .. (line.err and '  ·  stderr' or '')
        .. (
          line.time
            and ('  ·  ' .. os.date (
              '!%Y-%m-%d %H:%M:%S',
              math.floor (line.time / 1000)
            ) .. (line.stamped and '' or ' (from the line above)'))
          or ''
        )
    )
    local text = line.plain
    local fields = line.fields
    if fields then
      -- The fields the list shows as columns, one to a line.
      local parts = {} ---@type string[]
      for _, name in ipairs (ctx.col_names) do
        if fields[name] then
          parts[#parts + 1] = name .. ': ' .. fields[name]
        end
      end
      if #parts > 0 then
        text = text .. '\n\n' .. table.concat (parts, '\n')
      end
    end
    detail_text:text (text)
    local pretty = nil ---@type string?
    local json = lf.find_json (line.plain)
    if json then
      pretty = lf.pretty_json (json)
    end
    detail:class ('logs-has-json', pretty ~= nil)
    json_box:show (pretty ~= nil)
    detail:show (true)
    -- The editor measures itself when it is made, so it is made once the panel shows.
    if pretty then
      if json_view then
        json_view:widget ('set_text', pretty)
      else
        json_view = ui.widget ('code', {
          text = pretty,
          language = 'json',
          readonly = true,
          wrap = true,
        })
        json_box:append (json_view)
      end
    end
  end

  ---@param id integer
  local function select_line (id)
    local line = ctx.by_id[id]
    if not line then
      return
    end
    if ctx.follow then
      set_follow (false)
    end
    open_detail (line)
    reveal (id)
  end

  ---@param step integer 1 moves down and -1 moves up.
  local function move_selection (step)
    if #ctx.chunks == 0 then
      return
    end
    local target = nil ---@type integer?
    local ci, ri = nil, nil ---@type integer?, integer?
    if ctx.selected then
      ci, ri = locate (id_of (ctx.selected))
    end
    if ci and ri then
      local ns = ctx.chunks[ci].ns
      local next_chunk, prev_chunk = ctx.chunks[ci + 1], ctx.chunks[ci - 1]
      if ns[ri + step] then
        target = ns[ri + step]
      elseif step > 0 and next_chunk then
        target = next_chunk.ns[1]
      elseif step < 0 and prev_chunk then
        target = prev_chunk.ns[#prev_chunk.ns]
      end
    elseif step > 0 then
      target = ctx.chunks[1].ns[1]
    else
      local last = ctx.chunks[#ctx.chunks].ns
      target = last[#last]
    end
    if target then
      select_line (target)
    end
  end

  ctx.close_detail = close_detail
  ctx.open_detail = open_detail
  ctx.select_line = select_line
  ctx.move_selection = move_selection
end

return M
