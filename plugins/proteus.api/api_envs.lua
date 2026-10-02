-- api_envs: the API client's environments, the sets of values for {{variables}}. It shows the
-- active one in the toolbar or the status bar, lets the user pick another, and edits
-- environments.json in a view of its own, saving the text once it is valid. The client's
-- init.lua attaches it to the context its modules share.

---@class ApiApp.EnvsModule
local M = {}

---Adds the environments to `ctx`.
---@param ctx ApiApp.Ctx
function M.attach (ctx)
  local app, ui, http, views = ctx.app, ctx.ui, ctx.http, ctx.views
  local status, picker, toolbar = ctx.status, ctx.picker, ctx.toolbar
  local DIR, ENV_PATH = ctx.DIR, ctx.ENV_PATH
  local say, complain = ctx.say, ctx.complain
  local change_files, load_envs = ctx.change_files, ctx.load_envs

  local env_label = ui.span ({ class = 'toolbar-text' })
  local env_btn = ui.h ('button', {
    class = 'toolbar-button api-env',
    title = 'Choose an environment',
    ui.icon ('variable', 16),
    env_label,
  })
  local st_env = nil ---@type Proteus.StatusItem?
  if toolbar then
    toolbar.add (env_btn, { order = 10 })
  elseif status then
    st_env = status.add ({
      id = 'api.env',
      text = '',
      icon = 'variable',
      align = 'left',
      order = 20,
      command = 'api.environment',
    })
  end

  local function render_env ()
    local label = ctx.envs.active ~= '' and ctx.envs.active or 'No environment'
    env_label:text (label)
    env_btn:class ('on', ctx.envs.active ~= '')
    env_btn:set (
      'title',
      ctx.env_problem
          and ('The environments file has a problem. ' .. ctx.env_problem)
        or 'Choose an environment'
    )
    if st_env then
      st_env.set (label)
    end
  end

  local env_view = nil ---@type Proteus.View?
  local env_msg = ui.div ({ class = 'api-env-msg' })
  local env_host = ui.div ({ class = 'api-code' })

  ---Saves the environments text when it is valid, and shows the problem when it is not.
  ---@return boolean saved
  local function check_env_text ()
    ctx.env_timer = nil
    local code = ctx.env_code
    if not code then
      return true
    end
    local text = code:widget ('get_text')
    local parsed, err = http.parse_envs (text)
    if not parsed then
      env_msg:text (err or 'This is not valid.')
      env_msg:class ('bad', true)
      return false
    end
    env_msg:class ('bad', false)
    if text ~= (app.fs.read (ENV_PATH) or '') then
      if
        not change_files ('Could not save the environments', function ()
          app.fs.write (ENV_PATH, text)
        end)
      then
        return false
      end
    end
    env_msg:text ('Saved. Write a name as {{name}} anywhere in a request.')
    ctx.envs = parsed
    ctx.env_problem = nil
    render_env ()
    return true
  end

  local function close_envs ()
    if ctx.env_timer then
      ctx.env_timer ()
    end
    if not check_env_text () then
      complain (
        'The environments are not saved. Fix the problem under the text first.'
      )
      return
    end
    if env_view then
      env_view.remove ()
      env_view = nil
    end
    views.show ('api.requests')
  end

  local env_side = ui.div ({
    class = 'api-side api-envs',
    ui.div ({
      class = 'api-side-bar',
      ui.span ({ class = 'api-side-title', DIR .. '/environments.json' }),
      ui.span ({ class = 'api-grow' }),
      ui.button ({
        'Done',
        icon = 'check',
        variant = 'ghost',
        class = 'api-small',
        onclick = function ()
          close_envs ()
          return nil
        end,
      }),
    }),
    env_host,
    env_msg,
  })

  local function edit_envs ()
    local text = app.fs.read (ENV_PATH) or http.ENV_TEMPLATE
    if not ctx.env_code then
      ctx.env_code = ui.widget ('code', {
        language = 'json',
        text = text,
        on_change = function ()
          if ctx.env_timer then
            ctx.env_timer ()
          end
          ctx.env_timer = app.timer.after (400, check_env_text)
        end,
      })
      env_host:append (ctx.env_code)
    elseif not env_view then
      -- The view was closed, so the text starts again from the file.
      ctx.env_code:widget ('set_text', text)
    end
    if not env_view then
      env_msg:class ('bad', ctx.env_problem ~= nil)
      env_msg:text (ctx.env_problem or 'Changes save once the text is valid.')
      env_view = views.add ('left', {
        id = 'api.envs',
        title = 'Environments',
        icon = 'variable',
        order = 3,
        content = env_side,
      })
    end
    views.show ('api.envs')
  end

  ---@param name string
  local function set_env (name)
    if name == ctx.envs.active then
      return
    end
    local text = app.fs.read (ENV_PATH)
    if not text or http.trim (text) == '' then
      return
    end
    local next_text, err = http.set_active (text, name)
    if not next_text then
      complain ('The environments file has a problem. ' .. tostring (err))
      edit_envs ()
      return
    end
    if
      change_files ('Could not save the environments', function ()
        app.fs.write (ENV_PATH, next_text)
      end)
    then
      load_envs ()
      if ctx.env_code and not ctx.env_timer then
        ctx.env_code:widget ('set_text', next_text)
      end
      say (
        name == '' and 'No environment is active.'
          or ('The "' .. name .. '" environment is active.')
      )
    end
  end

  local function choose_env ()
    if not picker then
      return
    end
    local items = {} ---@type Proteus.PickItem[]
    for _, name in ipairs (ctx.envs.names) do
      local count = 0
      for _ in pairs (ctx.envs.environments[name]) do
        count = count + 1
      end
      items[#items + 1] = {
        label = name,
        detail = count == 1 and '1 variable' or (count .. ' variables'),
        icon = name == ctx.envs.active and 'check' or 'variable',
        value = name,
      }
    end
    items[#items + 1] = {
      label = 'No environment',
      icon = ctx.envs.active == '' and 'check' or 'circle-slash',
      value = '',
    }
    items[#items + 1] =
      { label = 'Edit environments…', icon = 'pencil', value = false }
    picker.pick ({
      placeholder = ctx.env_problem
          and 'The environments file has a problem. Pick Edit to fix it.'
        or 'Choose an environment',
      items = items,
      on_pick = function (item)
        if item.value == false then
          edit_envs ()
        else
          set_env (tostring (item.value))
        end
      end,
    })
  end

  env_btn:on ('click', function ()
    choose_env ()
    return nil
  end)

  ctx.render_env = render_env
  ctx.edit_envs = edit_envs
  ctx.choose_env = choose_env
end

return M
