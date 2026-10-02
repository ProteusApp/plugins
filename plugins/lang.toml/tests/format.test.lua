local format = require ('lib.format') --[[@as LangToml.FormatModule]]

---@class FormatTest.Run
---@field format fun(text: string): string? Formats a document at /w/conf/app.toml.
---@field runs { program: string, args: string[], opts: table }[]
---@field logs string[]
---@field notes string[]

---Installs the formatter against a fake app, Taplo and settings.
---@param opts { enabled?: boolean, program?: string|false, result?: table, err?: string }
---@return FormatTest.Run
local function install (opts)
  local state = { runs = {}, logs = {}, notes = {} }
  local run = state --[[@as FormatTest.Run]]
  local formatter ---@type fun(doc: table, text: string, done: fun(text: string?))
  local ctx = {
    app = {
      process = {
        run = function (program, args, o, cb)
          run.runs[#run.runs + 1] = { program = program, args = args, opts = o }
          cb (opts.result, opts.err)
        end,
      },
    },
    settings = {
      get = function (key)
        assert (key == 'toml.format', key)
        return opts.enabled ~= false
      end,
    },
    editor = {
      add_formatter = function (language, fn)
        assert (language == 'toml', language)
        formatter = fn
      end,
    },
    to_disk = function ()
      return '/w/conf/app.toml'
    end,
    notify = function (text)
      run.notes[#run.notes + 1] = text
    end,
  }
  local tool = {
    locate = function (cb)
      cb (opts.program ~= false and (opts.program or '/bin/taplo') or nil)
    end,
    log = function (level, text)
      run.logs[#run.logs + 1] = level .. ': ' .. text
    end,
  }
  format.install (
    ctx --[[@as LangToml.Context]],
    tool --[[@as Proteus.ToolHandle]]
  )
  run.format = function (text)
    local out = 'unanswered' ---@type string?
    formatter ({ path = 'conf/app.toml' }, text, function (formatted)
      out = formatted
    end)
    return out
  end
  return run
end

test ('Taplo formats the text from stdin, in the file’s folder', function ()
  local run =
    install ({ result = { code = 0, stdout = 'a = 1\n', stderr = '' } })
  eq (run.format ('a=1'), 'a = 1\n')
  eq (run.runs, {
    {
      program = '/bin/taplo',
      args = { 'fmt', '--stdin-filepath', '/w/conf/app.toml', '-' },
      opts = { cwd = '/w/conf', stdin = 'a=1' },
    },
  })
  eq (run.logs, { 'info: formatted conf/app.toml' })
end)

test (
  'nothing is formatted while the setting is off, or without Taplo',
  function ()
    local off = install ({ enabled = false })
    eq (off.format ('a=1'), nil)
    eq (off.runs, {})
    local missing = install ({ program = false })
    eq (missing.format ('a=1'), nil)
    eq (missing.runs, {})
  end
)

test (
  'a file Taplo cannot read is left as it is, and the user hears why',
  function ()
    local run = install ({
      result = { code = 1, stdout = '', stderr = 'expected value\n\n' },
    })
    eq (run.format ('a='), nil)
    eq (run.logs, { 'err: conf/app.toml: expected value' })
    eq (
      run.notes,
      { 'Taplo could not format app.toml. The Tools panel has its message.' }
    )
  end
)

test ('a program that does not run leaves the text as it is', function ()
  local run = install ({ err = 'no such file' })
  eq (run.format ('a=1'), nil)
  eq (run.logs, { 'err: no such file' })
  eq (run.notes, {})
end)
