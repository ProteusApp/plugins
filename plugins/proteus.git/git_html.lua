-- git_html: draws the Changes lists, the history, a diff, a commit and the welcome screen
-- as HTML strings, and reads back the `data-item` values they carry. It calls no host
-- function, so the tests reach all of it.

local A = require ('git_args') --[[@as Git.ArgsModule]]
local paths = require ('git_paths') --[[@as Git.PathsModule]]

---A piece of a changed line, for the word-level diff.
---@class Git.Segment
---@field text string
---@field changed boolean True for the words the other side of the pair does not have.

---@class Git.DiffOptions
---@field buttons? boolean Adds a Stage Hunk or Unstage Hunk button to each hunk.
---@field lines? boolean With `buttons`, each added or removed line can be picked, and a Stage Lines or Unstage Lines button stages the picked ones.
---@field picked? table<string, table<integer, boolean>> The picked lines, by `'<file>:<hunk>'`, then by line position. A hunk with any shows its Stage Lines button.
---@field staged? boolean The buttons unstage instead of stage.
---@field max_lines? integer How many diff lines to draw. 5,000 when nil.
---@field label? string A tag beside each file path, such as `'Staged'`.
---@field empty? string The text to show when there is no file.
---@field cut? boolean True when `parse_diff` stopped at `max_lines`, so there is more.
---@field split? boolean Draws the old and the new file side by side.
---@field highlight? fun(code: string, lang: string): string Colors code as HTML, as `app.util.highlight` does. The lines stay plain when nil.
---@field language? fun(path: string): string? The language to color a file in, or nil to leave it plain.

---A piece of a line's text and the `syn-*` classes that color it, `''` for none.
---@class Git.SyntaxRun
---@field text string
---@field class string

---@class Git.LogOptions
---@field more? boolean Ends the list in a Load More row.
---@field graph? string[] SVG to draw at the start of each row, as `git_graph.rows_svg` gives.
---@field empty? string What to say when there is no commit.

---@class Git.ListOptions
---@field selected? string The key of the selected row, such as `'u:src/a.txt'`.
---@field icons? table<string, string> SVG for the row buttons: `stage`, `unstage` and `discard`.
---@field limit? integer How many rows each list draws before a Show All row. `LIST_LIMIT` when nil.
---@field all? table<string, boolean> Lists to draw whole, by `'s'` or `'u'`.

---@class Git.HtmlModule
local M = {}

-- How many rows each list in the Changes view draws until Show All is clicked. A repository
-- with thousands of new files stays quick to draw.
M.LIST_LIMIT = 500

---@type table<Git.Kind, string>
local KIND_TITLE = {
  modified = 'Modified',
  added = 'Added',
  deleted = 'Deleted',
  renamed = 'Renamed',
  copied = 'Copied',
  typechange = 'Type changed',
  untracked = 'Untracked',
  conflicted = 'Conflict',
}

---@type table<string, string>
local HTML_ESCAPES = {
  ['&'] = '&amp;',
  ['<'] = '&lt;',
  ['>'] = '&gt;',
  ['"'] = '&quot;',
  ["'"] = '&#39;',
}

---------------------------------------------------------------------------------------------
-- HTML
---------------------------------------------------------------------------------------------

---Escapes text for HTML, attribute values included.
---@param s any
---@return string
function M.escape (s)
  local out = tostring (s):gsub ('[&<>"\']', HTML_ESCAPES)
  return out
end

---Writes 5000 as `'5,000'`.
---@param n integer
---@return string
function M.thousands (n)
  local s = tostring (n):reverse ():gsub ('(%d%d%d)', '%1,'):reverse ()
  local out = s:gsub ('^,', '')
  return out
end

local esc = M.escape

---@param text string
---@return string
local function note (text)
  return '<div class="git-note">' .. esc (text) .. '</div>'
end

---@param f Git.FileDiff
---@return string
local function empty_file_text (f)
  if f.old_mode and f.new_mode and f.old_mode ~= f.new_mode then
    return 'The file mode changed from '
      .. f.old_mode
      .. ' to '
      .. f.new_mode
      .. '.'
  end
  if f.renamed then
    return 'Renamed with no changes inside.'
  end
  if f.new_file then
    return 'An empty file.'
  end
  return 'No changes to show.'
end

---@param f Git.FileDiff
---@param opts Git.DiffOptions
---@return string
local function file_head (f, opts)
  local out = { '<div class="git-file-head"><span class="git-file-path">' }
  if f.renamed and f.old_path and f.old_path ~= f.path then
    out[#out + 1] = '<span class="git-file-old">'
      .. esc (f.old_path)
      .. '</span> → '
  end
  out[#out + 1] = esc (f.path) .. '</span>'
  local tags = {} ---@type string[]
  if opts.label then
    tags[#tags + 1] = opts.label
  end
  if f.new_file then
    tags[#tags + 1] = 'New'
  elseif f.deleted then
    tags[#tags + 1] = 'Deleted'
  elseif f.renamed then
    tags[#tags + 1] = 'Renamed'
  end
  for _, t in ipairs (tags) do
    out[#out + 1] = '<span class="git-file-tag">' .. esc (t) .. '</span>'
  end
  out[#out + 1] = '<span class="git-file-stat"><span class="git-stat-add">+'
    .. f.added
    .. '</span><span class="git-stat-del">−'
    .. f.removed
    .. '</span></span></div>'
  return table.concat (out)
end

---@type table<Git.LineKind, string>
local SIGN = { add = '+', del = '−', ctx = '', meta = '' }

-- Two lines whose token counts multiply past this are compared whole, not word by word.
local WORD_LIMIT = 40000

---Splits a line into words, runs of spaces, and single other characters.
---@param s string
---@return string[]
local function tokens (s)
  local out = {} ---@type string[]
  local i = 1
  while i <= #s do
    local a, b = s:find ('^[%w_]+', i)
    if not a then
      a, b = s:find ('^%s+', i)
    end
    if not a then
      a, b = s:find ('^[%z\1-\127\194-\244][\128-\191]*', i)
    end
    if not a or not b then
      a, b = i, i
    end
    out[#out + 1] = s:sub (a, b)
    i = b + 1
  end
  return out
end

---Joins tokens into segments, one for each run that is changed or not.
---@param list string[]
---@param same table<integer, boolean>
---@return Git.Segment[]
local function segments (list, same)
  local out = {} ---@type Git.Segment[]
  for i, t in ipairs (list) do
    local changed = not same[i]
    local last = out[#out]
    if last and last.changed == changed then
      last.text = last.text .. t
    else
      out[#out + 1] = { text = t, changed = changed }
    end
  end
  return out
end

---Compares a removed line with the added line that replaced it, word by word. Returns the
---pieces of each, or nil when they share no word or are too long to compare.
---@param a string
---@param b string
---@return Git.Segment[]? old
---@return Git.Segment[]? new
function M.word_diff (a, b)
  local x, y = tokens (a), tokens (b)
  local n, k = #x, #y
  if n == 0 or k == 0 or n * k > WORD_LIMIT then
    return nil, nil
  end
  -- len[i][j]: the longest run of tokens x[i..] and y[j..] have in common, in order.
  local len = {} ---@type integer[][]
  for i = n + 1, 1, -1 do
    local row = {} ---@type integer[]
    len[i] = row
    for j = k + 1, 1, -1 do
      if i > n or j > k then
        row[j] = 0
      elseif x[i] == y[j] then
        row[j] = len[i + 1][j + 1] + 1
      else
        row[j] = math.max (len[i + 1][j], row[j + 1])
      end
    end
  end
  local same_x, same_y = {}, {} ---@type table<integer, boolean>, table<integer, boolean>
  local words = 0
  local i, j = 1, 1
  while i <= n and j <= k do
    if x[i] == y[j] then
      same_x[i], same_y[j] = true, true
      if x[i]:find ('%S') then
        words = words + 1
      end
      i, j = i + 1, j + 1
    elseif len[i + 1][j] >= len[i][j + 1] then
      i = i + 1
    else
      j = j + 1
    end
  end
  if words == 0 then
    return nil, nil
  end
  return segments (x, same_x), segments (y, same_y)
end

---Pairs each run of removed lines with the run of added lines right after it, line by line,
---and compares each pair word by word.
---@param h Git.Hunk
---@return table<integer, Git.Segment[]> by line position in the hunk
local function hunk_words (h)
  local out = {} ---@type table<integer, Git.Segment[]>
  local dels = {} ---@type integer[]
  local adds = {} ---@type integer[]
  local function flush ()
    for p = 1, math.min (#dels, #adds) do
      local d, a = h.lines[dels[p]], h.lines[adds[p]]
      local old, new = M.word_diff (d.text, a.text)
      if old and new then
        out[dels[p]], out[adds[p]] = old, new
      end
    end
    dels, adds = {}, {}
  end
  for i, l in ipairs (h.lines) do
    if l.kind == 'del' then
      if #adds > 0 then
        flush ()
      end
      dels[#dels + 1] = i
    elseif l.kind == 'add' and #dels > 0 then
      adds[#adds + 1] = i
    else
      flush ()
    end
  end
  flush ()
  return out
end

---------------------------------------------------------------------------------------------
-- Syntax colors
---------------------------------------------------------------------------------------------

---@type table<string, string>
local ENTITIES = { amp = '&', lt = '<', gt = '>', quot = '"', apos = "'" }

---Reads the entities `app.util.highlight` writes back into text, or nil for one it does not.
---@param s string
---@return string?
local function unescape (s)
  local bad = false
  local out = s:gsub ('&(#?)([xX]?)(%w+);', function (hash, hex, name)
    if hash == '' then
      if hex ~= '' or not ENTITIES[name] then
        bad = true
        return ''
      end
      return ENTITIES[name]
    end
    local code = tonumber (name, hex ~= '' and 16 or 10)
    if not code or code > 127 then
      bad = true
      return ''
    end
    return string.char (code)
  end)
  if bad then
    return nil
  end
  return out
end

---Keeps the `syn-*` classes of a class list, so nothing else from the colored HTML reaches
---the page.
---@param list string
---@return string
local function syntax_class (list)
  local keep = {} ---@type string[]
  for word in list:gmatch ('%S+') do
    if word:find ('^syn%-[%w%-]+$') then
      keep[#keep + 1] = word
    end
  end
  return table.concat (keep, ' ')
end

---Reads colored HTML back into its lines, each a list of runs of plain text and their
---classes. Nil when the HTML holds anything but text and flat `<span class>` pieces.
---@param html string
---@return Git.SyntaxRun[][]?
function M.syntax_lines (html)
  local lines = { {} } ---@type Git.SyntaxRun[][]
  ---@param class string
  ---@param text string
  local function add (class, text)
    local first = true
    for piece in (text .. '\n'):gmatch ('([^\n]*)\n') do
      if not first then
        lines[#lines + 1] = {}
      end
      first = false
      if piece ~= '' then
        local line = lines[#lines]
        line[#line + 1] = { text = piece, class = class }
      end
    end
  end
  local i = 1
  while i <= #html do
    local _, b, class, inner =
      html:find ('^<span class="([^"<>]*)">([^<]*)</span>', i)
    if not b then
      class = ''
      _, b, inner = html:find ('^([^<]+)', i)
    end
    if not b then
      return nil
    end
    local text = unescape (inner)
    if not text then
      return nil
    end
    add (syntax_class (class), text)
    i = b + 1
  end
  return lines
end

-- The colors worked out for each hunk, so picking a line does not color it all again.
local syntax_cache = setmetatable ({}, { __mode = 'k' }) ---@type table<Git.Hunk, { lang: string, runs: table<integer, Git.SyntaxRun[]> }>

---Colors a hunk's lines in `lang`. The old side, its context and removed lines, is colored
---as one text, and so is the new side, so a string or comment over several lines of a hunk
---keeps its color. A line whose colored text does not match it stays plain.
---@param h Git.Hunk
---@param lang string
---@param highlight fun(code: string, lang: string): string
---@return table<integer, Git.SyntaxRun[]> by line position in the hunk
function M.hunk_syntax (h, lang, highlight)
  local cached = syntax_cache[h]
  if cached and cached.lang == lang then
    return cached.runs
  end
  local runs = {} ---@type table<integer, Git.SyntaxRun[]>
  for _, skip in ipairs ({ 'add', 'del' }) do
    local at, texts = {}, {} ---@type integer[], string[]
    for li, l in ipairs (h.lines) do
      if l.kind ~= skip and l.kind ~= 'meta' then
        at[#at + 1] = li
        texts[#texts + 1] = l.text
      end
    end
    local lines = nil ---@type Git.SyntaxRun[][]?
    if #at > 0 then
      local ok, html = pcall (highlight, table.concat (texts, '\n'), lang)
      lines = ok and type (html) == 'string' and M.syntax_lines (html) or nil
    end
    if lines then
      for k, li in ipairs (at) do
        local line = lines[k] or {}
        local joined = {} ---@type string[]
        for _, run in ipairs (line) do
          joined[#joined + 1] = run.text
        end
        if table.concat (joined) == h.lines[li].text then
          runs[li] = line
        end
      end
    end
  end
  syntax_cache[h] = { lang = lang, runs = runs }
  return runs
end

---A run of text as HTML, in a span with its classes when it has any.
---@param class string
---@param text string
---@return string
local function run_html (class, text)
  if class == '' then
    return esc (text)
  end
  return '<span class="' .. class .. '">' .. esc (text) .. '</span>'
end

---A line's text as HTML, colored when `runs` is given, with the changed words marked when
---there are any. A changed word keeps its colors inside its mark.
---@param l Git.Line
---@param words? Git.Segment[]
---@param runs? Git.SyntaxRun[]
---@return string
local function code_html (l, words, runs)
  local out = {} ---@type string[]
  if not runs then
    if not words then
      return esc (l.text)
    end
    for _, seg in ipairs (words) do
      if seg.changed then
        out[#out + 1] = '<span class="git-w">' .. esc (seg.text) .. '</span>'
      else
        out[#out + 1] = esc (seg.text)
      end
    end
    return table.concat (out)
  end
  if not words then
    for _, run in ipairs (runs) do
      out[#out + 1] = run_html (run.class, run.text)
    end
    return table.concat (out)
  end
  -- Both lists cover the same text, so walk them together, cutting the runs at the edges of
  -- the words.
  local r, used = 1, 0
  for _, seg in ipairs (words) do
    local need = #seg.text
    local parts = {} ---@type string[]
    while need > 0 and runs[r] do
      local run = runs[r]
      local take = math.min (need, #run.text - used)
      parts[#parts + 1] =
        run_html (run.class, run.text:sub (used + 1, used + take))
      used, need = used + take, need - take
      if used >= #run.text then
        r, used = r + 1, 0
      end
    end
    if seg.changed then
      out[#out + 1] = '<span class="git-w">'
        .. table.concat (parts)
        .. '</span>'
    else
      out[#out + 1] = table.concat (parts)
    end
  end
  return table.concat (out)
end

---One diff line. With `pick`, its line numbers carry `data-item="<pick>"`, so a click on
---them picks the line, and `on` marks it picked.
---@param l Git.Line
---@param pick? string
---@param words? Git.Segment[]
---@param on? boolean
---@param runs? Git.SyntaxRun[]
---@return string
local function line_html (l, pick, words, on, runs)
  local gutter = '<span class="git-ln">'
    .. (l.old or '')
    .. '</span><span class="git-ln">'
    .. (l.new or '')
    .. '</span><span class="git-sign">'
    .. SIGN[l.kind]
    .. '</span>'
  if pick then
    gutter = '<span class="git-gutter" data-item="'
      .. pick
      .. '" title="Pick this line">'
      .. gutter
      .. '</span>'
  end
  return '<div class="git-line git-l-'
    .. l.kind
    .. (on and ' git-picked' or '')
    .. '">'
    .. gutter
    .. '<span class="git-code">'
    .. code_html (l, words, runs)
    .. '</span></div>'
end

---One side of a row in the side-by-side diff. `side` picks the line number to show.
---@param l Git.Line?
---@param side 'old'|'new'
---@param pick? string
---@param words? Git.Segment[]
---@param on? boolean
---@param runs? Git.SyntaxRun[]
---@return string
local function half_html (l, side, pick, words, on, runs)
  if not l then
    return '<div class="git-half git-half-empty"></div>'
  end
  local gutter = '<span class="git-ln">'
    .. ((side == 'old' and l.old or l.new) or '')
    .. '</span><span class="git-sign">'
    .. SIGN[l.kind]
    .. '</span>'
  if pick then
    gutter = '<span class="git-gutter" data-item="'
      .. pick
      .. '" title="Pick this line">'
      .. gutter
      .. '</span>'
  end
  return '<div class="git-half git-l-'
    .. l.kind
    .. (on and ' git-picked' or '')
    .. '">'
    .. gutter
    .. '<span class="git-code">'
    .. code_html (l, words, runs)
    .. '</span></div>'
end

---Pairs a hunk's lines into side-by-side rows: context on both sides, and each run of removed
---lines beside the run of added lines after it. Each row holds line positions in the hunk.
---@param h Git.Hunk
---@return { old?: integer, new?: integer }[]
function M.split_rows (h)
  local rows = {} ---@type { old?: integer, new?: integer }[]
  local dels, adds = {}, {} ---@type integer[], integer[]
  local function flush ()
    for k = 1, math.max (#dels, #adds) do
      rows[#rows + 1] = { old = dels[k], new = adds[k] }
    end
    dels, adds = {}, {}
  end
  for i, l in ipairs (h.lines) do
    if l.kind == 'del' then
      if #adds > 0 then
        flush ()
      end
      dels[#dels + 1] = i
    elseif l.kind == 'add' then
      adds[#adds + 1] = i
    elseif l.kind == 'meta' then
      -- The marker belongs to the line before it, on that line's side.
      local prev = h.lines[i - 1]
      if prev and prev.kind == 'del' then
        dels[#dels + 1] = i
      elseif prev and prev.kind == 'add' then
        adds[#adds + 1] = i
      else
        flush ()
        rows[#rows + 1] = { old = i, new = i }
      end
    else
      flush ()
      rows[#rows + 1] = { old = i, new = i }
    end
  end
  flush ()
  return rows
end

---The diff for the main area, as one HTML string. Each hunk button carries
---`data-item="hunk:<file>:<hunk>"`, both counted from 1.
---@param files Git.FileDiff[]
---@param opts? Git.DiffOptions
---@return string
function M.diff_html (files, opts)
  opts = opts or {}
  local max = opts.max_lines or 5000
  local total = 0
  for _, f in ipairs (files) do
    for _, h in ipairs (f.hunks) do
      total = total + #h.lines
    end
  end
  local out = {
    opts.split and '<div class="git-diff git-diff-split">'
      or '<div class="git-diff">',
  }
  if #files == 0 then
    out[#out + 1] = note (opts.empty or 'No changes.')
  end
  local shown = 0
  local cut = false
  for fi, f in ipairs (files) do
    if cut then
      break
    end
    out[#out + 1] = '<div class="git-file">'
    out[#out + 1] = file_head (f, opts)
    local colors = opts.highlight
    local lang = colors
        and not f.binary
        and opts.language
        and opts.language (f.path)
      or nil
    if f.binary then
      out[#out + 1] = note ('Binary file')
    elseif #f.hunks == 0 then
      out[#out + 1] = note (empty_file_text (f))
    end
    for hi, h in ipairs (f.hunks) do
      if shown >= max then
        cut = true
        break
      end
      local stageable = opts.buttons
        and not f.combined
        and not f.binary
        and not h.partial
      local pickable = stageable and opts.lines
      local on = pickable and opts.picked and opts.picked[fi .. ':' .. hi] or {}
      out[#out + 1] = '<div class="git-hunk'
        .. (next (on) and ' git-hunk-picked' or '')
        .. '"><div class="git-hunk-head"><span class="git-hunk-text">'
        .. esc (h.header)
        .. '</span>'
      if pickable then
        out[#out + 1] = '<button class="git-hunk-btn git-lines-btn" data-item="lines:'
          .. fi
          .. ':'
          .. hi
          .. '">'
          .. (opts.staged and 'Unstage Lines' or 'Stage Lines')
          .. '</button>'
      end
      if stageable then
        out[#out + 1] = '<button class="git-hunk-btn" data-item="hunk:'
          .. fi
          .. ':'
          .. hi
          .. '">'
          .. (opts.staged and 'Unstage Hunk' or 'Stage Hunk')
          .. '</button>'
      end
      out[#out + 1] = '</div>'
      local words = f.combined and {} or hunk_words (h)
      local syntax = (lang and colors) and M.hunk_syntax (h, lang, colors) or {}
      ---@param li integer
      ---@return string?
      local function pick_of (li)
        local kind = h.lines[li].kind
        if pickable and (kind == 'add' or kind == 'del') then
          return 'line:' .. fi .. ':' .. hi .. ':' .. li
        end
        return nil
      end
      if opts.split and not f.combined then
        for _, row in ipairs (M.split_rows (h)) do
          if shown >= max then
            cut = true
            break
          end
          local a, b = row.old, row.new
          local left = a and h.lines[a] or nil
          local right = b and h.lines[b] or nil
          out[#out + 1] = '<div class="git-split">'
            .. half_html (
              left,
              'old',
              a ~= b and a and pick_of (a) or nil,
              a and words[a],
              a and on[a],
              a and syntax[a]
            )
            .. half_html (
              right,
              'new',
              a ~= b and b and pick_of (b) or nil,
              b and words[b],
              b and on[b],
              b and syntax[b]
            )
            .. '</div>'
          shown = shown + ((a and b and a ~= b) and 2 or 1)
        end
      else
        for li, l in ipairs (h.lines) do
          if shown >= max then
            cut = true
            break
          end
          out[#out + 1] =
            line_html (l, pick_of (li), words[li], on[li], syntax[li])
          shown = shown + 1
        end
      end
      out[#out + 1] = '</div>'
    end
    out[#out + 1] = '</div>'
  end
  if opts.cut then
    out[#out + 1] = note (
      'Showing the first '
        .. M.thousands (shown)
        .. ' lines. The rest is left out.'
    )
  elseif cut then
    out[#out + 1] = note (
      'Showing the first '
        .. M.thousands (max)
        .. ' of '
        .. M.thousands (total)
        .. ' lines.'
    )
  end
  out[#out + 1] = '</div>'
  return table.concat (out)
end

---The commit header above a commit's diff: the whole message, the author and the date.
---@param c Git.CommitInfo
---@return string
function M.commit_html (c)
  local out = {
    '<div class="git-commit-view"><div class="git-commit-title">',
    esc (c.subject),
    '</div>',
  }
  if c.body ~= '' then
    out[#out + 1] = '<div class="git-commit-body">' .. esc (c.body) .. '</div>'
  end
  out[#out + 1] = '<div class="git-commit-info"><span>'
    .. esc (c.author)
    .. ' &lt;'
    .. esc (c.email)
    .. '&gt;</span><span>'
    .. esc (c.date)
    .. (c.relative ~= '' and (' (' .. esc (c.relative) .. ')') or '')
    .. '</span><span class="git-hash">'
    .. esc (c.hash)
    .. '</span></div>'
  if #c.parents > 1 then
    local shorts = {} ---@type string[]
    for _, p in ipairs (c.parents) do
      shorts[#shorts + 1] = esc (p:sub (1, 7))
    end
    out[#out + 1] = '<div class="git-commit-info">A merge of '
      .. table.concat (shorts, ' and ')
      .. '. The changes shown are against the first.</div>'
  end
  out[#out + 1] = '</div>'
  return table.concat (out)
end

---The header above a stash's diff: its message, its name and when it was made.
---@param st Git.Stash
---@return string
function M.stash_html (st)
  return '<div class="git-commit-view"><div class="git-commit-title">'
    .. esc (st.message)
    .. '</div><div class="git-commit-info"><span class="git-hash">'
    .. esc (st.ref)
    .. '</span><span>'
    .. esc (st.date)
    .. '</span></div></div>'
end

---Reads a `data-item` value such as `'stage:u:src/a.txt'` into its action, its list (`'s'` or
---`'u'`) and its path.
---@param item string?
---@return string? action
---@return string? group
---@return string? path
function M.parse_item (item)
  if not item then
    return nil, nil, nil
  end
  local action, group, path = item:match ('^([%w_-]+):([su]):(.*)$')
  if action then
    return action, group, path
  end
  return item, nil, nil
end

---@param e Git.Entry
---@param opts Git.ListOptions
---@return string
local function row_html (e, opts)
  local group = e.staged and 's' or 'u'
  local key = group .. ':' .. e.path
  local name, dir = paths.split_path (e.path)
  local icons = opts.icons or {}
  local tools = {} ---@type string[]
  ---@param action string
  ---@param title string
  ---@param icon string
  local function tool (action, title, icon)
    tools[#tools + 1] = '<button class="git-tool" data-item="'
      .. esc (action .. ':' .. key)
      .. '" title="'
      .. esc (title)
      .. '">'
      .. (icons[icon] or esc (title:sub (1, 1)))
      .. '</button>'
  end
  if e.staged then
    tool ('unstage', 'Unstage', 'unstage')
  elseif e.kind == 'conflicted' then
    tool ('stage', 'Mark Resolved', 'stage')
  else
    if A.discard_args (e) then
      tool ('discard', 'Discard Changes', 'discard')
    end
    tool ('stage', 'Stage', 'stage')
  end
  local title = e.old_path and (e.old_path .. ' → ' .. e.path) or e.path
  return '<div class="git-row'
    .. (opts.selected == key and ' active' or '')
    .. '" data-item="'
    .. esc ('open:' .. key)
    .. '" title="'
    .. esc (title .. ' (' .. KIND_TITLE[e.kind] .. ')')
    .. '"><span class="git-letter git-k-'
    .. e.kind
    .. '">'
    .. esc (e.letter)
    .. '</span><span class="git-name">'
    .. esc (name)
    .. '</span><span class="git-dir">'
    .. esc (dir)
    .. '</span><span class="git-tools">'
    .. table.concat (tools)
    .. '</span></div>'
end

---@param title string
---@param count integer
---@param action string
---@param label string
---@return string
local function group_head (title, count, action, label)
  return '<div class="git-group"><span class="git-group-title">'
    .. esc (title)
    .. '</span><span class="ui-badge">'
    .. count
    .. '</span><button class="git-group-btn" data-item="'
    .. action
    .. '">'
    .. esc (label)
    .. '</button></div>'
end

---Draws the rows of one list, up to the limit, then a Show All row.
---@param out string[]
---@param list Git.Entry[]
---@param group string
---@param opts Git.ListOptions
local function rows_html (out, list, group, opts)
  local limit = opts.limit or M.LIST_LIMIT
  if opts.all and opts.all[group] then
    limit = #list
  end
  for i, e in ipairs (list) do
    if i > limit then
      out[#out + 1] = '<div class="git-row git-more" data-item="show-all-'
        .. group
        .. '">Show all '
        .. M.thousands (#list)
        .. ' files</div>'
      return
    end
    out[#out + 1] = row_html (e, opts)
  end
end

---The Staged and Changes lists as one HTML string. A row carries
---`data-item="open:<s|u>:<path>"` and its buttons `stage:`, `unstage:` or `discard:`. A list
---longer than `opts.limit` ends in a `show-all-<s|u>` row.
---@param st Git.Status
---@param opts? Git.ListOptions
---@return string
function M.changes_html (st, opts)
  opts = opts or {}
  local out = {} ---@type string[]
  if #st.staged > 0 then
    out[#out + 1] =
      group_head ('Staged', #st.staged, 'unstage-all', 'Unstage All')
    rows_html (out, st.staged, 's', opts)
  end
  local conflicts, changes = {}, {} ---@type Git.Entry[], Git.Entry[]
  for _, e in ipairs (st.unstaged) do
    if e.kind == 'conflicted' then
      conflicts[#conflicts + 1] = e
    else
      changes[#changes + 1] = e
    end
  end
  if #conflicts > 0 then
    out[#out + 1] = '<div class="git-group"><span class="git-group-title">Merge Changes</span>'
      .. '<span class="ui-badge">'
      .. #conflicts
      .. '</span></div>'
    rows_html (out, conflicts, 'u', opts)
  end
  if #changes > 0 then
    out[#out + 1] = group_head ('Changes', #changes, 'stage-all', 'Stage All')
    rows_html (out, changes, 'u', opts)
  end
  if #out == 0 then
    out[1] = '<div class="ui-empty">No changes</div>'
  end
  return table.concat (out)
end

---The history list as one HTML string. Each row carries `data-item="<hash>"`, and the Load
---More row `data-item="more"`.
---@param commits Git.Commit[]
---@param selected? string The hash of the selected commit.
---@param opts? Git.LogOptions
---@return string
function M.log_html (commits, selected, opts)
  local o = opts or {}
  if #commits == 0 then
    return '<div class="ui-empty">'
      .. esc (o.empty or 'No commits yet')
      .. '</div>'
  end
  local out = {} ---@type string[]
  local graph = o.graph
  if graph then
    out[1] = '<div class="git-graph-list">'
  end
  for i, c in ipairs (commits) do
    local refs = {} ---@type string[]
    for _, r in ipairs (c.refs) do
      refs[#refs + 1] = '<span class="git-ref git-ref-'
        .. r.kind
        .. (r.current and ' git-ref-current' or '')
        .. '">'
        .. esc (r.name)
        .. '</span>'
    end
    out[#out + 1] = '<div class="git-commit'
      .. (c.hash == selected and ' active' or '')
      .. '" data-item="'
      .. esc (c.hash)
      .. '">'
      .. (graph and graph[i] or '')
      .. '<div class="git-commit-text"><div class="git-commit-subject">'
      .. table.concat (refs)
      .. '<span class="git-subject-text">'
      .. esc (c.subject)
      .. '</span></div><div class="git-commit-meta"><span class="git-hash">'
      .. esc (c.short)
      .. '</span><span>'
      .. esc (c.author)
      .. '</span><span>'
      .. esc (c.date)
      .. '</span></div></div></div>'
  end
  if graph then
    out[#out + 1] = '</div>'
  end
  if o.more then
    out[#out + 1] =
      '<div class="git-row git-more" data-item="more">Load more commits</div>'
  end
  return table.concat (out)
end

---The screen with no repository open: a button to open one, then the recent ones. The button
---carries `data-item="open"` and each recent row `data-item="recent:<path>"`.
---@param recent string[]
---@param icon? string SVG to show at the top.
---@return string
function M.welcome_html (recent, icon)
  local out = {
    '<div class="git-welcome">',
    icon and ('<div class="git-welcome-icon">' .. icon .. '</div>') or '',
    '<div class="git-welcome-title">No repository open</div>',
    '<div class="git-welcome-text">Open a folder that holds a Git repository.</div>',
    '<button class="ui-button primary" data-item="open">Open Repository</button>',
  }
  if #recent > 0 then
    out[#out + 1] = '<div class="git-recent-title">Recent</div>'
    for _, path in ipairs (recent) do
      local name = paths.split_path (path)
      out[#out + 1] = '<div class="git-recent" data-item="'
        .. esc ('recent:' .. path)
        .. '"><span class="git-recent-name">'
        .. esc (name)
        .. '</span><span class="git-recent-path">'
        .. esc (path)
        .. '</span></div>'
    end
  end
  out[#out + 1] = '</div>'
  return table.concat (out)
end

---A plain message for the main area, such as when Git is missing.
---@param title string
---@param text string
---@return string
function M.message_html (title, text)
  return '<div class="git-welcome"><div class="git-welcome-title">'
    .. esc (title)
    .. '</div><div class="git-welcome-text">'
    .. esc (text)
    .. '</div></div>'
end

---------------------------------------------------------------------------------------------
-- Conflicts
---------------------------------------------------------------------------------------------

---What each side of a conflict did, in words, such as `'Both changed it'`.
---@type table<string, string>
local CONFLICT_TEXT = {
  UU = 'Both sides changed this file.',
  AA = 'Both sides added this file.',
  DD = 'Both sides deleted this file.',
  AU = 'The current branch added this file, and the incoming side changed it.',
  UA = 'The incoming side added this file, and the current branch changed it.',
  DU = 'The current branch deleted this file, and the incoming side changed it.',
  UD = 'The incoming side deleted this file, and the current branch changed it.',
}

---The bar above a conflicted file's diff, with a button for each way to resolve it. Each
---carries `data-item="conflict:<ours|theirs|resolved|open>"`.
---@param e Git.Entry
---@return string
function M.conflict_html (e)
  ---@param action string
  ---@param label string
  ---@param title string
  ---@param primary? boolean
  ---@return string
  local function button (action, label, title, primary)
    return '<button class="ui-button'
      .. (primary and ' primary' or '')
      .. '" data-item="conflict:'
      .. action
      .. '" title="'
      .. M.escape (title)
      .. '">'
      .. M.escape (label)
      .. '</button>'
  end
  local out = {
    '<div class="git-conflict"><div class="git-conflict-text">',
    M.escape (CONFLICT_TEXT[e.code] or 'This file has a conflict.'),
    ' Edit it to keep what you want, then mark it resolved, or take one side whole.</div>',
    '<div class="git-conflict-btns">',
    button (
      'ours',
      e.code:sub (1, 1) == 'D' and 'Accept Current (delete)' or 'Accept Current',
      "Keep the current branch's version"
    ),
    button (
      'theirs',
      e.code:sub (2, 2) == 'D' and 'Accept Incoming (delete)'
        or 'Accept Incoming',
      'Take the version coming in'
    ),
    button ('resolved', 'Mark Resolved', 'Stage the file as it is now', true),
  }
  if e.code ~= 'DD' and e.code:sub (1, 1) ~= 'D' then
    out[#out + 1] = button ('open', 'Open File', 'Edit the file')
  end
  out[#out + 1] = '</div></div>'
  return table.concat (out)
end

return M
