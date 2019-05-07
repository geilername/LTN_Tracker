local defs = defs
local tab_names = defs.tabs
local egm = egm
local C = C
local mod_gui = require("mod-gui")
local gui_data = {  -- cached global table data
  windows = {},
  alert_popup = {},
  show_alerts = {},
  is_ltnc_active = false,
  is_ltnc_open = {},
  station_select_mode = {},
  last_refresh_tick = {},
  refresh_interval = {},
}
gui = {}

------------------------------------------------------------------------------------
-- load ui sub-modules
------------------------------------------------------------------------------------
require(defs.pathes.modules.action_definitions)

local build_funcs, update_funcs = {}, {}
build_funcs[tab_names.depot], update_funcs[tab_names.depot] = unpack(require(defs.pathes.modules.depot_tab))
local inventory_funcs = require(defs.pathes.modules.inventory_tab)
build_funcs[tab_names.inventory] = inventory_funcs.build
update_funcs[tab_names.inventory] = inventory_funcs.update
--build_funcs[tab_names.requests], update_funcs[tab_names.requests] = unpack(require(defs.pathes.modules.request_tab))
local station_funcs = require(defs.pathes.modules.station_tab)
build_funcs[tab_names.station] = station_funcs.build
update_funcs[tab_names.station] = station_funcs.update
build_funcs[tab_names.history], update_funcs[tab_names.history] = unpack(require(defs.pathes.modules.history_tab))
build_funcs[tab_names.alert], update_funcs[tab_names.alert] = unpack(require(defs.pathes.modules.alert_tab))

------------------------------------------------------------------------------------
-- gui module functions
------------------------------------------------------------------------------------
local function build(pind)--[[ --> custom egm_window
Creates the GUI for the given player.

Parameters:
  player_index :: uint
Return value
  the LTNT main window
]]
  local frame_flow
  local player = game.players[pind]
  local height = util.get_setting(defs.settings.window_height, player)
  if util.get_setting(defs.settings.window_location, player) == "left" then
    frame_flow = mod_gui.get_frame_flow(player)
    height = height < 710 and height or 710
  else
    frame_flow = player.gui.center
  end

  local preexisting_window = frame_flow[defs.names.window]
  if preexisting_window and preexisting_window.valid then
    preexisting_window.destroy()
  end
  egm.manager.delete_player_data(pind)

  local window = egm.window.build(frame_flow, {
    name = defs.names.window,
    caption = {"ltnt.mod-name"},
    height = height,
    width = C.window.width,
    direction = "vertical",
  })
  window.root.visible = false
  egm.window.add_button(window, {
    type = "sprite-button",
    style = defs.styles.shared.default_button,
    sprite = "utility/refresh",
    tooltip = {"ltnt.refresh-bt"},
  },
  {action = defs.actions.refresh_button})

  window.pane = egm.tabs.build(window.content, {direction = "vertical"})

  window.tabs = {}
  window.tabs[tab_names.depot] = build_funcs[tab_names.depot](window)
  window.tabs[tab_names.station] = build_funcs[tab_names.station](window)
  --window.tabs[tab_names.requests] = build_funcs[tab_names.requests](window)
  window.tabs[tab_names.inventory] = build_funcs[tab_names.inventory](window)
  window.tabs[tab_names.history] =  build_funcs[tab_names.history](window)
  window.tabs[tab_names.alert] =  build_funcs[tab_names.alert](window)
  gui_data.windows[pind] = window
  return window
end
gui.build = build


local function get(pind)--[[  --> custom egm_window
Returns the GUI for the given player if it exists. Creates it otherwise.

Parameters
  player_index :: uint
Return value
  the LTNT main window
]]
  local window = gui_data.windows[pind]
  if window and window.content and window.content.valid then
    return window
  else
    return build(pind)
  end
end
gui.get = get

local function update_tab(event)--[[
Updates the currently visible tab for the player given by event.player_index. Does
nothing if GUI is closed.

Parameters
  table with fields:
    player_index :: uint
]]
  local pind = event.player_index
  local window = get(pind)
  local tab_index = window.root.visible and window.pane.active_tab
  if update_funcs[tab_index] then
    update_funcs[tab_index](window.tabs[tab_index], global.data)
    gui_data.last_refresh_tick[pind] = game.tick
  end
end
gui.update_tab = update_tab

local function update_tab_no_spam(event)--[[
Updates the currently visible tab for the player given by event.player_index. Does
nothing if GUI is closed or if the last update happened less than 60 ticks ago

Parameters
  table with fields:
    player_index :: uint
]]
  local pind = event.player_index
  local tick = game.tick
  if tick - gui_data.last_refresh_tick[pind] > 60 then
    local window = get(pind)
    local tab_index = window.root.visible and window.pane.active_tab
    if update_funcs[tab_index] then
      update_funcs[tab_index](window.tabs[tab_index], global.data)
      gui_data.last_refresh_tick[pind] = tick
    end
  end
end

local function on_toggle_button_click(event)--[[
Toggles the visibility of the GUI window player given by event.player_index.

Parameters
  table with fields:
    player_index :: uint
]]
  local pind = event.player_index
  local new_state = egm.window.toggle(get(pind))
  if new_state then
    game.players[pind].opened = get(pind).root
    game.players[pind].set_shortcut_toggled(defs.controls.shortcut, true)
    gui.update_tab(event)
  else
    game.players[pind].set_shortcut_toggled(defs.controls.shortcut, false)
  end
end

function gui.clear_station_filter()--[[
Resets station tab's cached filter results. Forces a cache rebuild next time the
station tab is updated.
]]
  for pind in pairs(game.players) do
    local filter = get(pind).tabs[defs.tabs.station].filter
    filter.cache = {}
    filter.last = nil
  end
end

local function build_alert_popup(pind)--[[  -> custom egm_window
Creates the alert popup for the given player.

Parameters:
  player_index :: uint
Return value
  the alert popup window
]]
  local frame_flow = mod_gui.get_frame_flow(game.players[pind])
  local preexisting_window = frame_flow[defs.names.alert_popup]
  if preexisting_window and preexisting_window.valid then
    egm.manager.unregister(preexisting_window)
    preexisting_window.destroy()
  end
  local alert_popup = egm.window.build(frame_flow, {
      frame_style = defs.styles.alert_notice.frame,
      title_style = defs.styles.alert_notice.frame_caption,
      width = 160,
      caption = {"alert.popup-caption"},
      name = defs.names.alert_popup,
    }
  )
  local button = egm.window.add_button(alert_popup, {
      type = "sprite-button",
      style = defs.styles.shared.large_close_button,
      sprite = "utility/go_to_arrow",
      tooltip = {"alert.open-button"},
    },
    {action = defs.actions.show_alerts, window = alert_popup}
  )
  egm.window.add_button(alert_popup, {
      type = "sprite-button",
      style = defs.styles.shared.large_close_button,
      sprite = "utility/close_black",
      tooltip = {"alert.close-button"},
    },
    {action = defs.actions.close_popup, window = alert_popup}
  )
  gui_data.alert_popup[pind] = alert_popup
  return alert_popup
end

local function get_alert_popup(pind)--[[ --> custom egm_window
Returns the alert popup window for the given player if it exists. Creates it otherwise.

Parameters
  player_index :: uint

Return value
  the alert popup window
]]
  local window = gui_data.alert_popup[pind]
  if window and window.content and window.content.valid then
    egm.window.clear(window)
    return window
  else
    return build_alert_popup(pind)
  end
end

local function on_new_alert(event)--[[
Opens alert pop-up for all players.

Parameters
  table with fields:
    type :: string: name of the alert
    loco :: LuaEntity: a locomotive entity
    delivery :: Table: delivery data as received from LTN
    cargo :: Table: [item] = count
]]
  for pind in pairs(gui_data.show_alerts) do
    if get(pind).root.visible then
      event.player_index = pind
      update_tab(event)
    else
      local alert_popup = get_alert_popup(pind)
      alert_popup.root.visible = true
      alert_popup.content.add{
        type = "label",
        style = "tooltip_heading_label",
        caption = defs.errors[event.type].caption,
        tooltip = defs.errors[event.type].tooltip,
      }.style.single_line = false
    end
  end
end

local function player_init(pind)--[[
Initializes global table for given player and builds GUI.

Parameters
  player_index :: uint
]]
  local player = game.players[pind]
  if debug_mode then log2("Building UI for player", player.name) end
  -- set UI state globals
  gui_data.show_alerts[pind] = util.get_setting(defs.settings.show_alerts, player)  or nil
  gui_data.last_refresh_tick[pind] = 0
  local refresh_interval = util.get_setting(defs.settings.refresh_interval, player)
  if refresh_interval > 0 then
    gui_data.refresh_interval[pind] = refresh_interval * 60
  else
    gui_data.refresh_interval[pind] = nil
  end
  gui_data.station_select_mode[pind] = tonumber(util.get_setting(defs.settings.station_click_action, player))

  build(pind)
end
gui.player_init = player_init
------------------------------------------------------------------------------------
-- event registration
------------------------------------------------------------------------------------
script.on_event({  -- gui interactions handling is done by egm manager module
    defines.events.on_gui_click,
    defines.events.on_gui_text_changed,
  },
  egm.manager.on_gui_input
)

script.on_event(defines.events.on_train_alert, on_new_alert)
script.on_event(defs.controls.toggle_hotkey, on_toggle_button_click)
script.on_event(defs.controls.toggle_filter, function(event)
  local window = get(event.player_index)
  if window.root.visible and window.pane.active_tab == defs.tabs.station then
    station_funcs.focus_filter(window)
  end
end)
script.on_event(defines.events.on_player_created, player_init)

-- different sources triggering tab update
script.on_event({
    defines.events.on_tab_changed,
    defines.events.on_textbox_valid_value_changed,
  },
  update_tab
)
script.on_event(defs.controls.refresh_hotkey, update_tab_no_spam)
egm.manager.define_action(defs.actions.refresh_button, update_tab_no_spam)

script.on_event(defines.events.on_gui_closed,
--[[ on_gui_closed(event)
Closes LTNT GUI or LTNC GUI, depending on which one is open.

Parameters
  table with fields:
    player_index :: uint
    element :: LuaGuiElement
]]
  function(event)
    -- event triggers whenever any UI element is closed, so check if it is actually the ltnt UI that is supposed to close
    if not (event.element and event.element.valid) then return end
    local pind = event.player_index
    local window = get(pind)
    if event.element.index == window.root.index then
      if gui_data.is_ltnc_active and gui_data.is_ltnc_open[pind] then
        gui_data.is_ltnc_open[pind] = nil
        remote.call(defs.remote.ltnc_interface, defs.remote.ltnc_close, pind)
        game.players[pind].opened = window.root
        update_tab(event)
      else
        egm.window.hide(window)
        game.players[pind].set_shortcut_toggled(defs.controls.shortcut, false)
      end
    end
  end
)

script.on_event(defines.events.on_lua_shortcut,
  function(event)
    if event.prototype_name == defs.controls.shortcut then
      on_toggle_button_click(event)
    end
  end
)

script.on_event(defines.events.on_data_updated,
  function(event)
    local tick = game.tick
    for pind, interval in pairs(gui_data.refresh_interval) do
      if tick - gui_data.last_refresh_tick[pind] > interval  then
        gui_data.last_refresh_tick[pind] = tick
        update_tab({player_index = pind})
      end
    end
  end
)
------------------------------------------------------------------------------------
-- initialization and configuration (called from control.lua)
------------------------------------------------------------------------------------
function gui.on_init()
  global.gui_data = global.gui_data or gui_data
  egm.manager.on_init()
  gui_data.is_ltnc_active = game.active_mods[defs.names.ltnc] and true or false
  for pind in pairs(game.players) do
    player_init(pind)
  end
end

function gui.on_load()
  gui_data = global.gui_data
  egm.manager.on_load()
end

function gui.on_settings_changed(event)
  local pind = event.player_index
  local setting = event.setting
  if     setting == defs.settings.window_height
      or setting == defs.settings.window_location then
    build(pind)
    return true
  end
  local player = game.players[pind]
  if setting == defs.settings.refresh_interval then
    local refresh_interval = util.get_setting(setting, player)
    if refresh_interval > 0 then
      gui_data.refresh_interval[pind] = refresh_interval * 60
    else
      gui_data.refresh_interval[pind] = nil
    end
    return true
  end
  if setting == defs.settings.fade_timeout then
    inventory_funcs.set_fadeout_time(pind)
    return true
  end
  if setting == defs.settings.station_click_action then
    gui_data.station_select_mode[pind] = tonumber(util.get_setting(setting, player))
    return true
  end
  if setting == defs.settings.show_alerts then
    gui_data.show_alerts[pind] = util.get_setting(defs.settings.show_alerts) or nil
    return true
  end
  return false
end

function gui.on_configuration_changed(data)
   -- handle changes to LTN-Combinator
  local reset = true  -- TODO implement proper logic for UI reset
  if data.mod_changes[defs.names.ltnc] then
    local was_active = gui_data.is_ltnc_active
    local is_active = game.active_mods[defs.names.ltnc] and true or false
    if is_active ~= was_active then
      gui_data.is_ltnc_active = is_active
      reset = true
    end
  end
  -- handles changes to LTNT
  if data.mod_changes[defs.names.mod_name] and data.mod_changes[defs.names.mod_name].old_version then
    reset = true
  end
  if reset then
    gui.clear_station_filter()
    for pind in pairs(game.players) do
      build(pind)
    end
  end
end

return gui