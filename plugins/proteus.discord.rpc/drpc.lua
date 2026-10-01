-- drpc: one connection to the Discord desktop app, which shows a presence sent as a table.
--
-- Discord listens on a local named pipe, which a plugin cannot open. A small PowerShell
-- script passes messages between this module and the pipe, so this works on Windows only.
-- The presence goes away when the connection closes, because the pipe closes with the
-- script. Protocol:
-- https://github.com/discord/discord-rpc/blob/master/documentation/hard-mode.md

---@class Discord.Client
---@field set fun(presence: Proteus.DiscordPresence) Shows the presence as soon as Discord answers.
---@field clear fun() Takes the presence away.
---@field close fun() Takes the presence away and disconnects.
---@field connected fun(): boolean

---@class Discord.RpcModule
---@field connect fun(app: Proteus.App, client_id: string): Discord.Client

local OP_HANDSHAKE = 0
local OP_FRAME = 1
local OP_CLOSE = 2
local OP_PING = 3
local OP_PONG = 4

-- How long to wait before trying again when Discord is closed or restarts.
local RETRY_SECONDS = 15

-- Each line in or out is a frame type, a space, and the JSON. The script first prints
-- "open <pid>", or "error <message>" when no Discord pipe answers.
local BRIDGE = [==[
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$utf8 = New-Object Text.UTF8Encoding $false
[Console]::OutputEncoding = $utf8
function Say ([string] $line) { [Console]::Out.WriteLine($line); [Console]::Out.Flush() }

$pipe = $null
foreach ($i in 0..9) {
  $p = New-Object IO.Pipes.NamedPipeClientStream '.', "discord-ipc-$i", 'InOut', 'Asynchronous'
  try { $p.Connect(200); $pipe = $p; break } catch { $p.Dispose() }
}
if ($null -eq $pipe) { Say 'error Discord is not running'; exit 1 }
Say "open $PID"

function Fill ([byte[]] $buf, [int] $got) {
  while ($got -lt $buf.Length) {
    $n = $pipe.Read($buf, $got, $buf.Length - $got)
    if ($n -le 0) { return $false }
    $got += $n
  }
  return $true
}

try {
  $in = New-Object IO.StreamReader ([Console]::OpenStandardInput()), $utf8
  $header = New-Object byte[] 8
  $lineTask = $in.ReadLineAsync()
  $headTask = $pipe.ReadAsync($header, 0, 8)
  while ($true) {
    $which = [Threading.Tasks.Task]::WaitAny([Threading.Tasks.Task[]] @($lineTask, $headTask))
    if ($which -eq 0) {
      $line = $lineTask.Result
      if ($null -eq $line) { break }
      $space = $line.IndexOf(' ')
      $body = $utf8.GetBytes($line.Substring($space + 1))
      $frame = New-Object byte[] (8 + $body.Length)
      [BitConverter]::GetBytes([int] $line.Substring(0, $space)).CopyTo($frame, 0)
      [BitConverter]::GetBytes([int] $body.Length).CopyTo($frame, 4)
      $body.CopyTo($frame, 8)
      $pipe.Write($frame, 0, $frame.Length)
      $pipe.Flush()
      $lineTask = $in.ReadLineAsync()
    } else {
      if (-not (Fill $header $headTask.Result)) { break }
      $body = New-Object byte[] ([BitConverter]::ToInt32($header, 4))
      if (-not (Fill $body 0)) { break }
      Say ('{0} {1}' -f [BitConverter]::ToInt32($header, 0), ($utf8.GetString($body) -replace '[\r\n]', ' '))
      $headTask = $pipe.ReadAsync($header, 0, 8)
    }
  }
} catch {
  Say ('error ' + $_.Exception.GetBaseException().Message)
} finally {
  $pipe.Dispose()
}
]==]

local B64 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'

---The script as PowerShell's -EncodedCommand takes it: base64 of UTF-16 text. The script
---is plain ASCII, so a zero byte after each character makes it UTF-16.
---@return string
local function encoded_bridge ()
  local bytes = BRIDGE:gsub ('.', '%0\0')
  local out = {} ---@type string[]
  for i = 1, #bytes, 3 do
    local a, b, c = bytes:byte (i, i + 2)
    local n = a * 65536 + (b or 0) * 256 + (c or 0)
    for k, shift in ipairs ({ 262144, 4096, 64, 1 }) do
      local present = k <= 2 or (k == 3 and b) or (k == 4 and c)
      local d = math.floor (n / shift) % 64
      out[#out + 1] = present and B64:sub (d + 1, d + 1) or '='
    end
  end
  return table.concat (out)
end

---Turns the presence table into the activity Discord expects.
---@param presence Proteus.DiscordPresence
---@return table<string, any>
local function activity_of (presence)
  local activity = {
    details = presence.details,
    state = presence.state,
  } ---@type table<string, any>
  local timestamps = { start = presence.start, ['end'] = presence.finish }
  if next (timestamps) then
    activity.timestamps = timestamps
  end
  local assets = {
    large_image = presence.large_image,
    large_text = presence.large_text,
    small_image = presence.small_image,
    small_text = presence.small_text,
  }
  if next (assets) then
    activity.assets = assets
  end
  if presence.buttons and #presence.buttons > 0 then
    activity.buttons = presence.buttons
  end
  return activity
end

---@param app Proteus.App
---@param client_id string
---@return Discord.Client
local function connect (app, client_id)
  local proc = nil ---@type Proteus.ProcessHandle?
  local pid = 0
  local ready = false
  local stopped = false
  local refused = false
  local warned = false
  local activity = nil ---@type table<string, any>?
  local nonce = 0
  local cancel_retry = nil ---@type fun()?

  ---@param message string
  local function warn (message)
    app.warn ('Discord: ' .. message)
  end

  ---@param op integer
  ---@param payload any
  local function send (op, payload)
    if proc then
      proc.write (op .. ' ' .. app.json.encode (payload))
    end
  end

  local function push ()
    if not ready then
      return
    end
    nonce = nonce + 1
    send (OP_FRAME, {
      cmd = 'SET_ACTIVITY',
      args = { pid = pid, activity = activity },
      nonce = tostring (nonce),
    })
  end

  ---@param line string
  local function on_line (line)
    local head, rest = line:match ('^(%S+) (.*)$')
    if head == 'open' then
      pid = math.floor (tonumber (rest) or 0)
      send (OP_HANDSHAKE, { v = 1, client_id = client_id })
      return
    end
    if head == 'error' then
      if not warned then
        warned = true
        warn (
          tostring (rest)
            .. '. Trying again every '
            .. RETRY_SECONDS
            .. ' seconds.'
        )
      end
      return
    end
    local ok, msg = pcall (app.json.decode, rest or '')
    if not ok or type (msg) ~= 'table' then
      return
    end
    local op = tonumber (head)
    if op == OP_PING then
      send (OP_PONG, msg)
    elseif op == OP_CLOSE then
      -- A close before READY means Discord refused the handshake, usually over a wrong
      -- client ID. Trying again would get the same answer.
      refused = not ready
      warn (tostring (msg.message or 'Discord closed the connection'))
    elseif op == OP_FRAME and msg.evt == 'READY' then
      ready = true
      warned = false
      if activity then
        push ()
      end
    elseif op == OP_FRAME and msg.evt == 'ERROR' then
      local data = msg.data or {}
      warn (tostring (data.message or 'Discord refused the presence'))
    end
  end

  local encoded = nil ---@type string?
  local start ---@type fun()

  local function retry_later ()
    if stopped or refused or cancel_retry then
      return
    end
    cancel_retry = app.timer.after (RETRY_SECONDS * 1000, function ()
      cancel_retry = nil
      start ()
    end)
  end

  start = function ()
    if proc or stopped then
      return
    end
    encoded = encoded or encoded_bridge ()
    proc = app.process.spawn ('powershell', {
      '-NoLogo',
      '-NoProfile',
      '-NonInteractive',
      '-EncodedCommand',
      encoded,
    }, {
      framing = 'lines',
      on_message = on_line,
      on_stderr = function (line)
        app.log ('Discord bridge: ' .. line)
      end,
      on_exit = function ()
        proc = nil
        ready = false
        retry_later ()
      end,
      on_error = function (err)
        proc = nil
        ready = false
        warn ('PowerShell did not start: ' .. err)
      end,
    })
  end

  ---@type Discord.Client
  local client = {
    set = function (presence)
      activity = activity_of (presence)
      push ()
    end,
    clear = function ()
      activity = nil
      push ()
    end,
    close = function ()
      stopped = true
      ready = false
      if cancel_retry then
        cancel_retry ()
        cancel_retry = nil
      end
      if proc then
        proc.kill ()
        proc = nil
      end
    end,
    connected = function ()
      return ready
    end,
  }

  if app.platform ~= 'tauri' or app.os ~= 'windows' then
    warn ('Rich Presence needs the desktop app on Windows.')
    stopped = true
    return client
  end
  start ()
  return client
end

---@type Discord.RpcModule
return { connect = connect }
