local crates = require ('lib.crates') --[[@as LangRust.CratesModule]]

test ('edition_of reads the edition a Cargo.toml sets', function ()
  eq (crates.edition_of ('[package]\nname = "a"\nedition = "2024"\n'), '2024')
  eq (crates.edition_of ('[package]\n  edition = "2018"'), '2018')
  eq (crates.edition_of ('[package]\nedition.workspace = true\n'), nil)
  eq (crates.edition_of (''), nil)
end)

---A fake app over a folder tree of Cargo.toml files, counting each read.
---@param files table<string, string>
---@param dirs? table<string, string[]> What list_dir gives for a folder.
---@return Proteus.App app
---@return table<string, integer> reads
---@return table<string, fun(...)> listeners
local function fake_app (files, dirs)
  local reads = {} ---@type table<string, integer>
  local listeners = {} ---@type table<string, fun(...)>
  local app = {
    on = function (event, fn)
      listeners[event] = fn
    end,
    fs = {
      read_file = function (path, cb)
        reads[path] = (reads[path] or 0) + 1
        cb (files[path])
      end,
      list_dir = function (path, cb)
        cb ((dirs or {})[path])
      end,
    },
  }
  return app, --[[@as Proteus.App]]
    reads,
    listeners
end

---@param fn fun(cb: fun(value: any))
---@return any
local function answer (fn)
  local got = 'unanswered' ---@type any
  fn (function (value)
    got = value
  end)
  return got
end

test ('of finds the nearest Cargo.toml at or above a folder', function ()
  local app = fake_app ({
    ['/w/Cargo.toml'] = '[workspace]',
    ['/w/crates/a/Cargo.toml'] = '[package]',
  })
  local c = crates.new (app)
  eq (
    answer (function (cb)
      c.of ('/w/crates/a/src/bin', cb)
    end),
    '/w/crates/a'
  )
  eq (
    answer (function (cb)
      c.of ('/w/docs', cb)
    end),
    '/w'
  )
  local none = crates.new (fake_app ({}))
  eq (
    answer (function (cb)
      none.of ('/x/y', cb)
    end),
    nil
  )
end)

test ('the edition comes from the first Cargo.toml up that sets one', function ()
  local app = fake_app ({
    ['/w/Cargo.toml'] = '[workspace.package]\nedition = "2024"',
    ['/w/a/Cargo.toml'] = '[package]\nedition.workspace = true',
    ['/old/Cargo.toml'] = '[package]',
  })
  local c = crates.new (app)
  eq (
    answer (function (cb)
      c.edition ('/w/a/src', cb)
    end),
    '2024'
  )
  eq (
    answer (function (cb)
      c.edition ('/old/src', cb)
    end),
    crates.DEFAULT_EDITION
  )
end)

test ('below finds a crate in the folder or one level down', function ()
  local app = fake_app ({
    ['/app/src-tauri/Cargo.toml'] = '[package]',
    ['/app/target/Cargo.toml'] = '[package]',
  }, {
    ['/app'] = {
      '.git/',
      'node_modules/',
      'target/',
      'README.md',
      'src-tauri/',
    },
  })
  local c = crates.new (app)
  eq (
    answer (function (cb)
      c.below ('/app', cb)
    end),
    '/app/src-tauri'
  )
  local empty = crates.new (fake_app ({}, { ['/e'] = { 'a/' } }))
  eq (
    answer (function (cb)
      empty.below ('/e', cb)
    end),
    nil
  )
end)

test ('each Cargo.toml is read once, until one changes on disk', function ()
  local files = { ['/w/Cargo.toml'] = '[package]\nedition = "2018"' }
  local app, reads, listeners = fake_app (files)
  local c = crates.new (app)
  local edition = function ()
    return answer (function (cb)
      c.edition ('/w', cb)
    end)
  end
  eq (edition (), '2018')
  eq (edition (), '2018')
  eq (reads['/w/Cargo.toml'], 1)

  files['/w/Cargo.toml'] = '[package]\nedition = "2021"'
  listeners['code:disk_changed'] ({ { path = '/w/src/main.rs' } })
  eq (edition (), '2018', 'another file changed')
  listeners['code:disk_changed'] ({ { path = '/w/Cargo.toml' } })
  eq (edition (), '2021')
  eq (reads['/w/Cargo.toml'], 2)
end)
