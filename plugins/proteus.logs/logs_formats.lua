-- logs_formats: the log viewer's formats. The user defines a format, a regular expression with
-- a named group for each field or the fields to pick from JSON or logfmt lines, and gives it
-- to a source. The list then shows the fields as columns, sorts by them, and the filter reads
-- `field:value`. The formats are kept in the store, and each source keeps the name of its
-- format. The log viewer's init.lua attaches it to the context its modules share.

local lf = require ('log_filter') --[[@as Logs.FilterModule]]

local SAMPLE = 500 -- lines looked at to suggest fields
local SUGGEST = 6 -- fields suggested
local REGEX_EXAMPLE = '^(?<time>\\S+) (?<level>\\w+) (?<msg>.*)$'

---@class Logs.FormatsModule
local M = {}

---Adds the formats to `ctx`.
---@param ctx Logs.Ctx
function M.attach (ctx)
  local app, picker = ctx.app, ctx.picker
  local say, say_error = ctx.say, ctx.say_error

  ctx.formats = lf.clean_formats (app.store.get ('formats', {}))
  -- Each format made ready, by name, or false for one that does not compile.
  local cache = {} ---@type table<string, Logs.Parser|false>

  ---@param name? string
  ---@return Logs.Format?
  local function format_named (name)
    for _, f in ipairs (ctx.formats) do
      if f.name == name then
        return f
      end
    end
    return nil
  end

  ---The parser of a format, or nil when there is no such format.
  ---@param name? string
  ---@return Logs.Parser?
  local function parser_for (name)
    if not name then
      return nil
    end
    local hit = cache[name]
    if hit == nil then
      local format = format_named (name)
      hit = format and lf.compile_format (format) or false
      cache[name] = hit
    end
    return hit or nil
  end

  ---Reads every line of a source again with its format.
  ---@param src Logs.Source
  local function apply_to (src)
    src.parser = parser_for (src.spec.format)
    for i = 1, src.lines:count () do
      local line = src.lines:get (i)
      if line then
        lf.apply_format (line, src.parser)
      end
    end
  end

  ---Gives a source a format, or takes its format away when `name` is nil.
  ---@param src Logs.Source
  ---@param name? string
  local function set_format (src, name)
    src.spec.format = name
    apply_to (src)
    ctx.save_open ()
    ctx.redraw_list ()
  end

  local function save_formats ()
    app.store.set ('formats', ctx.formats)
    cache = {}
    for _, src in ipairs (ctx.sources) do
      if src.spec.format then
        if not format_named (src.spec.format) then
          src.spec.format = nil
        end
        apply_to (src)
      end
    end
    ctx.save_open ()
    ctx.redraw_list ()
  end

  ---The last lines of a source, to suggest fields from and to try a format on.
  ---@param src? Logs.Source
  ---@return Logs.Line[]
  local function sample (src)
    local out = {} ---@type Logs.Line[]
    if not src then
      return out
    end
    local count = src.lines:count ()
    for i = math.max (1, count - SAMPLE + 1), count do
      local line = src.lines:get (i)
      if line then
        out[#out + 1] = line
      end
    end
    return out
  end

  ---Says how many of the sample lines a format reads.
  ---@param parser Logs.Parser
  ---@param lines Logs.Line[]
  ---@return string
  local function coverage (parser, lines)
    if #lines == 0 then
      return ''
    end
    local n = 0
    for _, line in ipairs (lines) do
      if parser.extract (line.plain) then
        n = n + 1
      end
    end
    return ' It reads '
      .. lf.group (n)
      .. ' of the last '
      .. lf.group (#lines)
      .. ' lines.'
  end

  ---Asks for the name and the fields of a format, saves it, and gives it to `src`. With
  ---`old`, it changes that format.
  ---@param kind Logs.FormatKind
  ---@param src? Logs.Source
  ---@param old? Logs.Format
  local function ask_format (kind, src, old)
    local p = picker
    if not p then
      return
    end
    local lines = sample (src)
    ---@param format Logs.Format
    local function keep (format)
      local parser, err = lf.compile_format (format)
      if not parser then
        say_error (err or 'The format does not work.')
        return
      end
      local list = {} ---@type Logs.Format[]
      for _, f in ipairs (ctx.formats) do
        if f.name ~= format.name and (not old or f.name ~= old.name) then
          list[#list + 1] = f
        end
      end
      list[#list + 1] = format
      if old and old.name ~= format.name then
        for _, other in ipairs (ctx.sources) do
          if other.spec.format == old.name then
            other.spec.format = format.name
          end
        end
      end
      ctx.formats = list
      if src then
        src.spec.format = format.name
      end
      save_formats ()
      say ('Saved the format ' .. format.name .. '.' .. coverage (parser, lines))
    end
    p.input ({
      prompt = 'Name of the format',
      placeholder = 'Such as: My app',
      value = old and old.name or '',
      validate = function (text)
        if not text:match ('%S') then
          return 'Give the format a name.'
        end
        return nil
      end,
      on_submit = function (text)
        local name = lf.trim (text)
        if kind == 'regex' then
          p.input ({
            prompt = 'Regular expression, with a named group for each field',
            placeholder = 'Such as: ' .. REGEX_EXAMPLE,
            value = old and old.pattern or '',
            validate = function (pattern)
              local _, err = lf.compile_format ({
                name = name,
                kind = 'regex',
                pattern = pattern,
                fields = {},
              })
              return err
            end,
            on_submit = function (pattern)
              keep ({
                name = name,
                kind = 'regex',
                pattern = pattern,
                fields = {},
              })
            end,
          })
          return
        end
        local found = lf.discover_fields (lines, kind, 24)
        local suggested = {} ---@type string[]
        for i = 1, math.min (SUGGEST, #found) do
          suggested[i] = found[i]
        end
        p.input ({
          prompt = 'Fields to show as columns, separated by commas',
          placeholder = #found > 0
              and ('Found: ' .. table.concat (found, ', '))
            or 'Such as: level, msg, user.id',
          value = old and table.concat (old.fields, ', ')
            or table.concat (suggested, ', '),
          validate = function (fields)
            if #lf.split_names (fields) == 0 then
              return 'Name at least one field.'
            end
            return nil
          end,
          on_submit = function (fields)
            keep ({ name = name, kind = kind, fields = lf.split_names (fields) })
          end,
        })
      end,
    })
  end

  ---Asks what kind of format to make, then makes it and gives it to `src`.
  ---@param src? Logs.Source
  local function new_format (src)
    local p = picker
    if not p then
      say_error ('Making a format needs the palette plugin.')
      return
    end
    local lines = sample (src)
    local json = #lf.discover_fields (lines, 'json', 1) > 0
    local logfmt = #lf.discover_fields (lines, 'logfmt', 1) > 0
    p.pick ({
      placeholder = 'What the lines hold',
      items = {
        {
          label = lf.FORMAT_KINDS.regex,
          detail = 'Named groups, such as ' .. REGEX_EXAMPLE,
          icon = 'regex',
          value = 'regex',
        },
        {
          label = lf.FORMAT_KINDS.json,
          detail = json and 'These lines hold JSON'
            or 'Each line ends with a JSON object',
          icon = 'braces',
          value = 'json',
        },
        {
          label = lf.FORMAT_KINDS.logfmt,
          detail = logfmt and 'These lines hold key=value fields'
            or 'Such as level=warn msg="disk full"',
          icon = 'list',
          value = 'logfmt',
        },
      },
      on_pick = function (item)
        ask_format (item.value, src)
      end,
    })
  end

  ---Picks a format for a source: none, one of the saved ones, or a new one.
  ---@param src Logs.Source
  local function choose_format (src)
    local p = picker
    if not p then
      return
    end
    local items = {
      {
        label = 'No Format',
        detail = 'Show the lines as they are',
        icon = 'text',
        hint = src.spec.format == nil and 'In use' or nil,
        value = false,
      },
    } ---@type Proteus.PickItem[]
    for _, f in ipairs (ctx.formats) do
      items[#items + 1] = {
        label = f.name,
        detail = lf.FORMAT_KINDS[f.kind]
          .. ': '
          .. (
            f.kind == 'regex' and (f.pattern or '')
            or table.concat (f.fields, ', ')
          ),
        icon = 'table',
        hint = src.spec.format == f.name and 'In use' or nil,
        value = f.name,
      }
    end
    items[#items + 1] = { label = 'New Format…', icon = 'plus', value = true }
    p.pick ({
      items = items,
      placeholder = 'Format of ' .. src.name,
      on_pick = function (item)
        if item.value == true then
          new_format (src)
        elseif item.value == false then
          set_format (src, nil)
        else
          set_format (src, item.value)
        end
      end,
    })
  end

  ---Picks a saved format and runs `fn` with it.
  ---@param placeholder string
  ---@param fn fun(format: Logs.Format)
  local function pick_format (placeholder, fn)
    local p = picker
    if not p then
      return
    end
    local items = {} ---@type Proteus.PickItem[]
    for _, f in ipairs (ctx.formats) do
      items[#items + 1] = {
        label = f.name,
        detail = lf.FORMAT_KINDS[f.kind],
        icon = 'table',
        value = f,
      }
    end
    p.pick ({
      items = items,
      placeholder = placeholder,
      empty = 'No formats yet',
      on_pick = function (item)
        fn (item.value)
      end,
    })
  end

  local function edit_format ()
    pick_format ('Change a format', function (format)
      ask_format (format.kind, ctx.shown, format)
    end)
  end

  local function delete_format ()
    pick_format ('Delete a format', function (format)
      local list = {} ---@type Logs.Format[]
      for _, f in ipairs (ctx.formats) do
        if f ~= format then
          list[#list + 1] = f
        end
      end
      ctx.formats = list
      save_formats ()
      say ('Deleted the format ' .. format.name .. '.')
    end)
  end

  ctx.parser_for = parser_for
  ctx.set_format = set_format
  ctx.choose_format = choose_format
  ctx.new_format = new_format
  ctx.edit_format = edit_format
  ctx.delete_format = delete_format
end

return M
