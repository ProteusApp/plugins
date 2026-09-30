-- daw.devices: the list of instruments and effects. It holds no device of its own: plugins
-- such as daw.instruments and daw.effects register theirs, and a device goes away with the
-- plugin that registered it. A song that names a device no plugin provides keeps it, and
-- the track plays without it until the plugin comes back.
--
-- A Web Audio Module device names its module instead of a patch, and learns its parameters
-- from the engine through `describe` once the module loads.

---@type Proteus.Plugin
return {
  name = 'DAW devices',
  description = 'The registry of instruments and effects that plugins add to the DAW.',
  version = '1.1.0',
  requires = { proteus = '>=0.2.0', features = { 'permissions' } },
  permissions = {},
  depends = { 'daw.core' },
  activate = function (app)
    local daw = app.use ('daw') --[[@as Daw.Core]]
    local specs = {} ---@type table<string, Daw.DeviceSpec>
    local order = {} ---@type string[]

    local function changed ()
      app.emit ('daw:devices')
    end

    ---@param id string
    local function drop (id)
      specs[id] = nil
      for i, other in ipairs (order) do
        if other == id then
          table.remove (order, i)
          break
        end
      end
    end

    app.provide_scoped ('daw.devices', function (consumer)
      ---@type Daw.Devices
      local service = {
        register = function (spec)
          local clean, err = daw.device.check (spec)
          if not clean then
            error ('daw.devices: ' .. tostring (err), 2)
          end
          clean.owner = consumer.id
          if specs[clean.id] then
            drop (clean.id)
          end
          specs[clean.id] = clean
          order[#order + 1] = clean.id
          consumer.dispose (function ()
            if specs[clean.id] == clean then
              drop (clean.id)
              changed ()
            end
          end)
          changed ()
          return clean
        end,
        get = function (id)
          return specs[id]
        end,
        list = function (role)
          local out = {} ---@type Daw.DeviceSpec[]
          for _, id in ipairs (order) do
            local spec = specs[id]
            if spec and (not role or spec.role == role) then
              out[#out + 1] = spec
            end
          end
          return out
        end,
        ref = function (id, preset)
          local spec = specs[id]
          return spec and daw.device.ref (spec, preset) or nil
        end,
        describe = function (id, info)
          local spec = specs[id]
          if not spec or not spec.wam then
            return
          end
          local params = daw.device.from_wam (info)
          -- The same parameters again change nothing, so no screen draws twice.
          local same = #params == #spec.params
          for i, p in ipairs (params) do
            same = same and spec.params[i] and spec.params[i].key == p.key
          end
          if not same then
            spec.params = params
            changed ()
          end
        end,
      }
      return service
    end)
  end,
}
