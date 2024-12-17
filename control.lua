--- @param player LuaPlayer
local function create_gui(player)
  local window = player.gui.screen.add({ type = "frame", name = "qt_window", style = "slot_window_frame" })
  local inner_panel = window.add({ type = "frame", name = "qt_inner_panel", style = "shortcut_bar_inner_panel" })
  local export_button = inner_panel.add({
    type = "sprite-button",
    name = "qt_export_button",
    style = "shortcut_bar_button_blue",
    sprite = "qt-export-blueprint-white",
    tooltip = { "qt-gui.export" },
  })
  export_button.style.padding = 4
  local import_button = inner_panel.add({
    type = "sprite-button",
    name = "qt_import_button",
    style = "shortcut_bar_button_blue",
    sprite = "qt-import-blueprint-white",
    tooltip = { "qt-gui.import" },
  })
  import_button.style.padding = 4
  window.visible = false
  return { window = window, export_button = export_button, import_button = import_button }
end

--- @param player LuaPlayer
local function setup_player(player)
  local data = create_gui(player)
  storage.players[player.index] = data
end

--- @param player LuaPlayer
--- @param window LuaGuiElement
local function set_gui_location(player, window)
  local resolution = player.display_resolution
  local scale = player.display_scale
  window.location = {
    x = (resolution.width / 2) - ((56 + 258) * scale),
    y = (resolution.height - (56 * scale)),
  }
end

--- @param position MapPosition
--- @param zero_position MapPosition
--- @return integer
local function position_to_index(position, zero_position)
  return math.floor(position.x - zero_position.x) + math.floor(zero_position.y - position.y) * 10 + 1
end

--- @param entities BlueprintEntity[]
local function get_zero_position(entities)
  local result = { x = entities[1].position.x, y = entities[1].position.y }
  for i = 2, 100 do
    local position = entities[i].position
    if result.x > position.x then
      result.x = position.x
    end
    if result.y < position.y then
      result.y = position.y
    end
  end
  return result
end

local ignored_item_names = {
  ["blueprint"] = true,
  ["blueprint-book"] = true,
  ["upgrade-planner"] = true,
  ["deconstruction-planner"] = true,
}

--- @param player LuaPlayer
local function export_quickbar(player)
  local entities = {}
  local pos = { x = -4, y = 4 }
  for i = 1, 100 do
    entities[i] = {
      entity_number = i,
      name = "constant-combinator",
      position = { x = pos.x, y = pos.y },
    }

    local item = player.get_quick_bar_slot(i)
    if item and not ignored_item_names[item.name] then
      entities[i].control_behavior = {
        filters = {
          {
            count = 1,
            index = 1,
            signal = {
              type = "item",
              name = item.name,
              quality = item.quality,
            },
          },
        },
      }
    end

    pos.x = pos.x + 1
    if pos.x == 6 then
      pos.x = -4
      pos.y = pos.y - 1
    end
  end
  return entities
end

--- @param player LuaPlayer
--- @param entities BlueprintEntity[]
--- @param ignore_empty boolean
--- @return boolean # If the transfer was successful.
local function import_quickbar(player, entities, ignore_empty)
  if #entities ~= 100 then
    return false
  end

  --- @type ({name: string, quality: string}?)[]
  local filters = {}
  local zero_position = get_zero_position(entities)
  for i = 1, 100 do
    local entity = entities[i]
    if not entity or entity.name ~= "constant-combinator" then
      return false
    end
    local filter_index = position_to_index(entity.position, zero_position)
    local cb = entity.control_behavior
    if not cb then
      goto continue
    end
    local sections_outer = cb.sections --- @diagnostic disable-line:undefined-field
    if not sections_outer then
      goto continue
    end
    local sections_inner = sections_outer.sections
    if not sections_inner then
      goto continue
    end
    local first_section = sections_inner[1]
    if not first_section then
      goto continue
    end
    local section_filters = first_section.filters
    if not section_filters then
      goto continue
    end
    local first_filter = section_filters[1]
    if not first_filter then
      goto continue
    end
    filters[filter_index] = { name = first_filter.name, quality = first_filter.quality }
    ::continue::
  end

  for i = 1, 100 do
    local filter = filters[i]
    if not ignore_empty or filter then
      player.set_quick_bar_slot(i, filter)
    end
  end

  return true
end

--- @param player LuaPlayer
--- @return BlueprintEntity[]?
local function get_blueprint_entities(player)
  if not player.is_cursor_blueprint() then
    return
  end
  local cursor_stack = player.cursor_stack
  if cursor_stack and cursor_stack.valid_for_read and cursor_stack.type == "blueprint" then
    return cursor_stack.get_blueprint_entities()
  end
  local cursor_record = player.cursor_record
  if cursor_record and cursor_record.type == "blueprint" then
    return cursor_record.get_blueprint_entities()
  end
end

-- EVENT HANDLERS

script.on_init(function()
  storage.players = {}
  for _, player in pairs(game.players) do
    setup_player(player)
  end
end)

script.on_configuration_changed(function()
  for i, player_table in pairs(storage.players) do
    player_table.window.destroy()
    local player = game.get_player(i)
    if player then
      storage.players[i] = create_gui(player)
    else
      storage.players[i] = nil
    end
  end
end)

script.on_event(defines.events.on_player_created, function(e)
  local player = game.players[e.player_index]
  setup_player(player)

  local template = player.mod_settings["qt-default-template"].value --[[@as string]]
  if template == "" then
    return
  end

  local temp_inventory = game.create_inventory(1)
  temp_inventory.insert({ name = "blueprint" })
  local blueprint = temp_inventory[1]

  if blueprint.import_stack(template) == 0 then
    local entities = blueprint.get_blueprint_entities()
    if not entities or not import_quickbar(player, entities, false) then
      player.print({ "qt-message.invalid-default-blueprint" })
    end
  else
    player.print({ "qt-message.invalid-default-blueprint" })
  end

  temp_inventory.destroy()
end)

--- @param e EventData.on_player_cursor_stack_changed
local function on_cursor_stack_changed(e)
  local player = game.players[e.player_index]
  local gui = storage.players[e.player_index]
  if not player.is_cursor_blueprint() then
    gui.window.visible = false
    return
  end
  set_gui_location(player, gui.window)
  local entities = get_blueprint_entities(player)
  if entities then
    gui.export_button.visible = false
    gui.import_button.visible = true
  else
    gui.export_button.visible = true
    gui.import_button.visible = false
  end
  gui.window.visible = true
end
script.on_event(defines.events.on_player_cursor_stack_changed, on_cursor_stack_changed)

script.on_event(
  { defines.events.on_player_display_resolution_changed, defines.events.on_player_display_scale_changed },
  --- @param e EventData.on_player_display_resolution_changed|EventData.on_player_display_scale_changed
  function(e)
    set_gui_location(game.players[e.player_index], storage.players[e.player_index].window)
  end
)

script.on_event(defines.events.on_gui_click, function(e)
  if e.element.name == "qt_export_button" then
    local player = game.players[e.player_index]
    local stack = player.cursor_stack
    if stack and stack.valid_for_read and stack.name == "blueprint" then
      stack.set_blueprint_entities(export_quickbar(player))
      on_cursor_stack_changed(e) --- @diagnostic disable-line:param-type-mismatch
    end
  elseif e.element.name == "qt_import_button" then
    local player = game.players[e.player_index]
    local entities = get_blueprint_entities(player)
    if entities then
      if not import_quickbar(player, entities, e.shift) then
        player.print({ "qt-message.invalid-blueprint" })
      end
    end
  end
end)
