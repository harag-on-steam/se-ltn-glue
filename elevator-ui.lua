local Gui = require("__flib__.gui")

local ElevatorUI = {}

local function lazy_subtable(a_table, key)
	local subtable = a_table[key]
	if not subtable then
		subtable = {}
		a_table[key] = subtable
	end
	return subtable
end

--- @param player LuaPlayer
--- @param elevator LuaEntity
function ElevatorUI.open(player, elevator)
	local player_data = lazy_subtable(storage.players, player.index)

	-- Re-create the UI every time it is opened.
	-- This is the only time the UI is updated from the model.
	-- The implication is that concurrent changes in multiplayer won't be reflected in the UI.
	if player_data.elevator_ui then
		player_data.elevator_ui.frame.destroy()
	end
	player_data.elevator_ui = ElevatorUI.build(player, elevator, assert(Elevator.from_entity(elevator)))
end

--- @param player LuaPlayer
--- @param elevator LuaEntity
--- @param elevator_data ElevatorData
function ElevatorUI.build(player, elevator, elevator_data)
	local refs = Gui.add(player.gui.relative, {{
		type = "frame", name = "frame",
		tags = { unit_number = elevator.unit_number },
		anchor = { gui = defines.relative_gui_type.assembling_machine_gui, position = defines.relative_gui_position.top },
		direction = "horizontal",
		style_mods = { padding = { 5, 5, 0, 5 } }, -- top right bottom left
		{
			type = "flow",
			{
				type = "label", style = "frame_title", ignored_by_interaction = true,
				style_mods = { top_margin = -3 },
				caption = "LTN",
			},
			{
				type = "switch", name = "connect",
				style_mods = { top_margin = 2 },
				tags = { unit_number = elevator.unit_number },
				allow_none_state = false,
				switch_state = elevator_data.ltn_enabled and "right" or "left",
				right_label_caption = "Connected",
				handler = { [defines.events.on_gui_switch_state_changed] = ElevatorUI.toggle_ltn_connection }
			},
			{
				type = "label",
				style_mods = { margin = { 2, 0, 0, 5 } },
				caption = "[img=virtual-signal/ltn-network-id]",
				tooltip = { "se-ltn-ui-tooltip.network-id" },
			},
			{
				type = "textfield", name = "network_id",
				style_mods = { top_margin = -3, width = 100 },
				tags = { unit_number = elevator.unit_number },
				tooltip = { "se-ltn-ui-tooltip.network-id" },
				numeric = true, allow_negative = true,
				-- string.format("%08X", bit32.band(elevator.network_id)),
				-- ... but built-in support for numbers only supports base-decimal
				text = tostring(elevator_data.network_id),
				handler = { [defines.events.on_gui_confirmed] = ElevatorUI.set_network_id },
			},
			{
				type = "sprite-button", style = "frame_action_button",
				style_mods = { left_margin = 5 },
				sprite = "virtual-signal/informatron",
				tooltip = {"space-exploration.informatron-open-help"},
				tags = { informatron_page = "space_elevators" },
				handler = { [defines.events.on_gui_click] = ElevatorUI.open_informatron },
				visible = false, -- NYI
			},
		}
	}})
	return refs
end

function ElevatorUI.toggle_ltn_connection(e)
	local data = Elevator.from_unit_number(e.element.tags.unit_number)
	if data then
		local new_connected = e.element.switch_state == "right"
		if data.ltn_enabled ~= new_connected then
			data.ltn_enabled = new_connected
			Elevator.update_connection(data)
		end
	end
end

function ElevatorUI.set_network_id(e)
	local data = Elevator.from_unit_number(e.element.tags.unit_number)
	if data then
		local new_network_id = tonumber(e.element.text)
		if new_network_id and new_network_id ~= data.network_id then
			data.network_id = new_network_id
			if data.ltn_enabled then
				Elevator.update_connection(data)
			end
		end
	end
end

-- could be a generic action
function ElevatorUI.open_informatron(e)
	game.print("Open Informatron (not implemented yet)")
end

--- @param player LuaPlayer
function ElevatorUI.close(player)
	local player_data = lazy_subtable(storage.players, player.index)
	if not player_data.elevator_ui then
		return
	end

	player_data.elevator_ui.frame.destroy()
	player_data.elevator_ui = nil
end

local function is_elevator_closed(e)
	local player = assert(game.get_player(e.player_index))
	if e.entity and e.entity.valid and e.entity.name == Elevator.name_elevator then
		ElevatorUI.close(player)
		return true
	end
	return false
end

local function is_elevator_opened(e)
	local player = assert(game.get_player(e.player_index))
	if e.entity and e.entity.valid and e.entity.name == Elevator.name_elevator then
		ElevatorUI.open(player, e.entity)
		return true
	end
	return false
end

Gui.add_handlers({
	toggle_ltn_connection = ElevatorUI.toggle_ltn_connection,
	set_network_id = ElevatorUI.set_network_id,
	open_informatron = ElevatorUI.open_informatron,
})

-- The UI of this mod is attached to the elevator so we need to open when its assembler opens.

script.on_event(defines.events.on_gui_opened, function(e)
	if is_elevator_opened(e) then return end
	Gui.dispatch(e)
end)

script.on_event(defines.events.on_gui_closed, function(e)
	if is_elevator_closed(e) then return end
	Gui.dispatch(e)
end)

-- flib hooks all remaining on_gui_ events with this.
-- A mod can only hook each event once, so this needs to happen last.
Gui.handle_events()

return ElevatorUI