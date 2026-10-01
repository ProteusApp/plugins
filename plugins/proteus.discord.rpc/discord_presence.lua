-- discord_presence: works out what Discord shows. It picks the running app, fills the words
-- in that app's lines, and lays each plugin's own presence on top. It calls no host
-- function, so the tests load it directly.

---One line of text, or a list of lines where the first one whose words are all known wins.
---@alias Discord.Lines string|string[]

---What one app shows when no plugin says otherwise.
---@class Discord.Preset
---@field id string Also the name looked up in the `images` setting.
---@field name string
---@field plugins string[] The app runs when any of these plugins runs.
---@field details Discord.Lines
---@field state Discord.Lines
---@field image_text? Discord.Lines Shown when the pointer rests on the image.

---A presence one plugin set, kept apart so it can be taken away again.
---@class Discord.Layer
---@field owner string The plugin id.
---@field presence Proteus.DiscordPresence

---@class Discord.BuildOptions
---@field idle boolean
---@field start? integer
---@field image? string

---@class Discord.PresenceModule
---@field APPS Discord.Preset[]
---@field FALLBACK Discord.Preset
---@field detect fun(profile_id: string, active: table<string, boolean>): Discord.Preset
---@field fill fun(line: string, vars: table<string, string>): string?
---@field pick fun(lines: Discord.Lines?, vars: table<string, string>): string?
---@field build fun(preset: Discord.Preset, layers: Discord.Layer[], vars: table<string, string>, opts: Discord.BuildOptions): Proteus.DiscordPresence

-- Discord refuses a line shorter than 2 bytes or longer than 128.
local MAX_BYTES = 128

local M = {}

-- Checked in this order, so an app plugin wins over the editor that a profile may also run.
---@type Discord.Preset[]
M.APPS = {
  {
    id = 'git',
    name = 'Git',
    plugins = { 'proteus.git' },
    details = { 'Working on {repo}', 'Managing a Git repository' },
    state = { 'On branch {branch}', 'Git' },
  },
  {
    id = 'api',
    name = 'API Client',
    plugins = { 'proteus.api' },
    details = 'Testing an API',
    state = 'API Client',
  },
  {
    id = 'logs',
    name = 'Logs',
    plugins = { 'proteus.logs' },
    details = 'Reading logs',
    state = 'Logs',
  },
  {
    id = 'sheet',
    name = 'Sheet',
    plugins = { 'proteus.sheet' },
    details = 'Working in a spreadsheet',
    state = 'Sheet',
  },
  {
    id = 'kanban',
    name = 'Kanban',
    plugins = { 'proteus.kanban', 'proteus.kanban.classic' },
    details = 'Moving cards along',
    state = 'Kanban',
  },
  {
    id = 'notes',
    name = 'Notes',
    plugins = { 'proteus.notes', 'proteus.notes.classic' },
    details = 'Writing notes',
    state = 'Notes',
  },
  {
    id = 'todo',
    name = 'Todo',
    plugins = { 'proteus.todo' },
    details = 'Checking off tasks',
    state = { '{left} left to do', 'All done' },
  },
  {
    id = 'code',
    name = 'Code Editor',
    plugins = { 'proteus.code.project' },
    details = { 'Editing {file}', 'Working on {project}', 'Writing code' },
    state = { 'In {project}', 'Code Editor' },
    image_text = { 'Writing {language}', 'Proteus Code Editor' },
  },
  {
    id = 'editor',
    name = 'Editor',
    plugins = { 'proteus.ws.explorer' },
    details = { 'Editing {file}', 'Browsing the workspace' },
    state = { 'In {plugin}', 'Building with Proteus' },
    image_text = { 'Writing {language}', 'Plugin Editor' },
  },
  {
    id = 'nodal',
    name = 'Nodal',
    plugins = { 'proteus.nodal.app' },
    details = { 'Wiring {file}', 'Wiring blocks together' },
    state = 'Nodal',
  },
}

---@type Discord.Preset
M.FALLBACK = {
  id = 'default',
  name = 'ProteusApp',
  plugins = {},
  details = { 'Using {profile}', 'Using Proteus' },
  state = 'ProteusApp',
  image_text = 'ProteusApp',
}

---Picks the app by the profile's id, or else by the plugins that run, as in a copy of a
---builtin profile.
---@param profile_id string
---@param active table<string, boolean> Running plugin ids.
---@return Discord.Preset
function M.detect (profile_id, active)
  for _, preset in ipairs (M.APPS) do
    if preset.id == profile_id then
      return preset
    end
  end
  for _, preset in ipairs (M.APPS) do
    for _, id in ipairs (preset.plugins) do
      if active[id] then
        return preset
      end
    end
  end
  return M.FALLBACK
end

---Cuts text to Discord's limit without splitting a character, and pads a one-byte line.
---@param text string
---@return string
local function clip (text)
  if #text > MAX_BYTES then
    local cut = MAX_BYTES - 3
    -- A byte from 0x80 to 0xBF continues a character, so back off to where one starts.
    local after = text:byte (cut + 1) ---@type integer
    while cut > 0 and after >= 0x80 and after < 0xC0 do
      cut = cut - 1
      after = text:byte (cut + 1)
    end
    return text:sub (1, cut) .. '...'
  end
  if #text < 2 then
    return text .. ' '
  end
  return text
end

---Fills each `{word}` from `vars`. Returns nil when a word has no value.
---@param line string
---@param vars table<string, string>
---@return string?
function M.fill (line, vars)
  local missing = false
  local text = line:gsub ('{([%w_]+)}', function (word)
    local value = vars[word]
    if value == nil or value == '' then
      missing = true
      return ''
    end
    return value
  end)
  if missing then
    return nil
  end
  return text
end

---@param lines Discord.Lines?
---@param vars table<string, string>
---@return string?
function M.pick (lines, vars)
  if type (lines) == 'string' then
    return M.fill (lines, vars)
  end
  for _, line in ipairs (lines or {}) do
    local text = M.fill (line, vars)
    if text then
      return text
    end
  end
  return nil
end

local TEXT_FIELDS = { 'details', 'state', 'large_text', 'small_text' }

---Works out the presence to send. Each layer's fields replace the app's, newest last. A
---field whose words are not all known stays as the layer underneath had it.
---@param preset Discord.Preset
---@param layers Discord.Layer[] Oldest first.
---@param vars table<string, string>
---@param opts Discord.BuildOptions
---@return Proteus.DiscordPresence
function M.build (preset, layers, vars, opts)
  local image_text = nil ---@type string?
  if opts.image then
    image_text = M.pick (preset.image_text, vars) or ('Proteus ' .. preset.name)
  end
  local out = {
    details = opts.idle and 'Idle' or M.pick (preset.details, vars),
    state = M.pick (preset.state, vars),
    start = opts.start,
    large_image = opts.image,
    large_text = image_text,
  } ---@type table<string, any>
  -- While idle, the app's own lines show and what plugins set waits.
  local shown = opts.idle and {} or layers ---@type Discord.Layer[]
  for _, layer in ipairs (shown) do
    for key, value in
      pairs (layer.presence --[[@as table<string, any>]])
    do
      if type (value) == 'string' then
        out[key] = M.fill (value, vars) or out[key]
      else
        out[key] = value
      end
    end
  end
  for _, key in ipairs (TEXT_FIELDS) do
    local value = out[key]
    if type (value) == 'string' then
      out[key] = clip (value)
    end
  end
  return out --[[@as Proteus.DiscordPresence]]
end

return M
