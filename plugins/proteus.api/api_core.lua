-- api_core: the parts of the API client that need no screen and no service, so its tests
-- reach them: where a folder keeps its sign-in, the name and folder of a request's file, the
-- row a key and value grid's event is about, when an OAuth 2 token is still good, what keeps
-- a request from going out, and how an answer from app.net.fetch is kept.

-- The file in a folder that holds the sign-in its requests inherit.
local FOLDER_FILE = '.folder.json'
-- A token this close to its end counts as ended, so it does not run out on the way.
local TOKEN_MARGIN = 30 * 1000

---What came back from one send.
---@class ApiApp.Result
---@field status? integer Nil when no answer came.
---@field headers table<string, string>
---@field list Proteus.HttpHeader[] Every header in the order it came.
---@field body string The text, or base64 when `binary` is true.
---@field binary boolean True when the body is bytes that are not text.
---@field size integer The body's length in bytes.
---@field ms number
---@field url? string The address that answered, when a redirect led there.
---@field redirects integer
---@field error? string
---@field warning? string
---@field note? string A line to show instead of an answer, such as after Cancel.
---@field pretty? string The body formatted, made the first time it shows.
---@field shown? string What the body view shows, for a binary body its hex.

---An OAuth 2 token the client got, and when it ends.
---@class ApiApp.Token
---@field token string
---@field ends? number Milliseconds since 1970, or nil when the answer did not say.

---@class ApiApp.Core
local M = {}

M.FOLDER_FILE = FOLDER_FILE

---The settings files of a folder and of each folder around it, from the folder itself out to
---the top. `folder` is a path under `dir`, such as `pets/cats`, or an empty string.
---@param dir string
---@param folder string
---@return string[]
function M.folder_files (dir, folder)
  local out = {} ---@type string[]
  local parts = {} ---@type string[]
  for part in folder:gmatch ('[^/]+') do
    parts[#parts + 1] = part
  end
  for n = #parts, 0, -1 do
    local path = dir
    for i = 1, n do
      path = path .. '/' .. parts[i]
    end
    out[#out + 1] = path .. '/' .. FOLDER_FILE
  end
  return out
end

---The folder a settings file belongs to, as the list names it: a path under `dir`, or an
---empty string for `dir` itself.
---@param dir string
---@param path string
---@return string
function M.folder_of_file (dir, path)
  local inner = path:sub (#dir + 2)
  return inner:match ('^(.*)/' .. FOLDER_FILE:gsub ('%p', '%%%0') .. '$') or ''
end

---True for a file the request list leaves out: a folder's settings and other hidden files.
---@param name string
---@return boolean
function M.hidden (name)
  return name:sub (1, 1) == '.'
end

---The name of a request from its file's path, without the folder or `.json`.
---@param path string
---@return string
function M.stem (path)
  return path:match ('([^/]+)%.json$') or path
end

---The folder a file or folder under `dir` sits in, as a path under `dir`, or an empty string
---for `dir` itself.
---@param dir string
---@param path string
---@return string
function M.folder_of (dir, path)
  return path:sub (#dir + 2):match ('^(.*)/[^/]*$') or ''
end

---The path of the request file `name` in a folder under `dir`.
---@param dir string
---@param folder string
---@param name string
---@return string
function M.path_for (dir, folder, name)
  return dir
    .. '/'
    .. (folder ~= '' and (folder .. '/') or '')
    .. name
    .. '.json'
end

---The row and the field a key and value grid's `data-item` names, such as `3:value`.
---@param item string?
---@return integer?
---@return string?
function M.grid_item (item)
  local n, field = (item or ''):match ('^(%d+):(%a+)$')
  if not n then
    return nil, nil
  end
  return math.floor (tonumber (n) or 0), field
end

---True while a token can still be sent.
---@param entry ApiApp.Token?
---@param now number
---@return boolean
function M.token_fresh (entry, now)
  if not entry or entry.token == '' then
    return false
  end
  return entry.ends == nil or now < entry.ends - TOKEN_MARGIN
end

---A token as kept, from what the token address said.
---@param token string
---@param seconds number?
---@param now number
---@return ApiApp.Token
function M.keep_token (token, seconds, now)
  return {
    token = token,
    ends = seconds and seconds > 0 and (now + seconds * 1000) or nil,
  }
end

---A random hex text, for a Digest cnonce.
---@param n integer How many characters.
---@param random fun(m: integer, n: integer): integer
---@return string
function M.random_hex (n, random)
  local out = {} ---@type string[]
  for i = 1, n do
    out[i] = string.format ('%x', random (0, 15))
  end
  return table.concat (out)
end

---What keeps a built request from going out, or nil.
---@param built { unpicked: string[], problems: string[] }
---@return string?
function M.send_problem (built)
  if built.problems[1] then
    return built.problems[1]
  end
  local names = built.unpicked
  if #names == 0 then
    return nil
  end
  if names[1] == 'the body' then
    return 'Pick the file to send in the Body tab first.'
  end
  local list = names[1]
  if #names > 1 then
    list = table.concat (names, ', ', 1, #names - 1) .. ' and ' .. names[#names]
  end
  return 'Pick the file for '
    .. list
    .. ' in the Body tab first, or switch '
    .. (#names == 1 and 'that row' or 'those rows')
    .. ' off.'
end

---The time limit typed in the Options tab, in seconds: 0 for none typed, or nil when the text
---is not a number from 0 to 3600.
---@param text string
---@return number?
function M.parse_timeout (text)
  local trimmed = text:gsub ('^%s+', ''):gsub ('%s+$', '')
  if trimmed == '' then
    return 0
  end
  local n = tonumber (trimmed)
  if not n or n ~= n or n < 0 or n > 3600 then
    return nil
  end
  return n
end

---How a time limit shows in the Options tab: empty for none.
---@param seconds number
---@return string
function M.timeout_text (seconds)
  if seconds <= 0 then
    return ''
  end
  if seconds == math.floor (seconds) then
    return string.format ('%d', seconds)
  end
  return tostring (seconds)
end

---An answer from app.net.fetch as the client keeps it. Fields that are missing, as from an
---older app, get what they can from the rest.
---@param reply Proteus.HttpReply
---@param sent_url string
---@param ms number The time measured here, for an answer that does not say.
---@param warning? string
---@return ApiApp.Result
function M.result_of (reply, sent_url, ms, warning)
  local headers = type (reply.headers) == 'table' and reply.headers or {}
  local list = {} ---@type Proteus.HttpHeader[]
  if type (reply.header_list) == 'table' then
    for _, h in ipairs (reply.header_list) do
      if type (h) == 'table' and type (h.name) == 'string' then
        list[#list + 1] = { name = h.name, value = tostring (h.value or '') }
      end
    end
  else
    local names = {} ---@type string[]
    for k in pairs (headers) do
      names[#names + 1] = tostring (k)
    end
    table.sort (names)
    for _, k in ipairs (names) do
      list[#list + 1] = { name = k, value = tostring (headers[k]) }
    end
  end
  local body = type (reply.body) == 'string' and reply.body or ''
  local url = type (reply.url) == 'string'
      and reply.url ~= sent_url
      and reply.url
    or nil
  return {
    status = math.floor (tonumber (reply.status) or 0),
    headers = headers,
    list = list,
    body = body,
    binary = reply.encoding == 'base64',
    size = math.floor (tonumber (reply.size) or #body),
    ms = tonumber (reply.ms) or ms,
    url = url,
    redirects = math.floor (tonumber (reply.redirects) or 0),
    warning = warning,
  }
end

---A result that holds no answer: an error, or a note such as after Cancel.
---@param fields { error?: string, note?: string, warning?: string, ms?: number }
---@return ApiApp.Result
function M.empty_result (fields)
  return {
    headers = {},
    list = {},
    body = '',
    binary = false,
    size = 0,
    ms = fields.ms or 0,
    redirects = 0,
    error = fields.error,
    note = fields.note,
    warning = fields.warning,
  }
end

return M
