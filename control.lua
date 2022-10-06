Train = require("__flib__.train")
Misc = require("__flib__.misc")
Area = require("__flib__.area")
Event = require("__flib__.event")

message_level = tonumber(settings.global["ltn-interface-console-level"].value)

Elevator = require("elevator-connection")

local function initialize()
	global.elevators = global.elevators or {}
	global.players = global.players or {}
end

--- @param entity LuaEntity a carriage or a train-stop
--- @param schedule_records table array of TrainScheduleRecord (Factorio concept)
--- @param surface_connections { entity1 : LuaEntity, entity2 : LuaEntity, network_id : integer }[]
local function add_closest_elevator_to_schedule(entity, schedule_records, surface_connections)
	local found_stop = nil
	local distance = 2147483647 -- maxint

	for _, connection in pairs(surface_connections) do
		-- which entity we use is not important, both map to the same ElevatorData structure
		local elevator = Elevator.from_unit_number(connection.entity1.unit_number)
		if elevator then -- the connection might not belong to se-ltn-glue
			local stop = elevator.ground.stop
			if not (stop and stop.valid and stop.surface == entity.surface) then
				stop = elevator.orbit.stop
			end

			if stop and stop.valid and stop.surface == entity.surface then
				local stop_distance = Misc.get_distance_squared(stop.position, entity.position)
				if (not found_stop) or (stop_distance < distance) then
					found_stop = stop
					distance = stop_distance
				end
			end
		end
	end

	if found_stop then
		-- no temp stops, entities to find the appropriate rail segments are only available in this event
		-- but not when the train arrives on the corresponding surface
		-- just inform the player in the FAQ that elevators with different network_ids need different names
		table.insert(schedule_records, {
			station = found_stop.backer_name
		})
	end
end

--- @param train LuaEntity
local function train_richtext(train)
	local loco = Train.get_main_locomotive(train)
	if loco and loco.valid then
		return string.format("[train=%d] %s", loco.unit_number, loco.backer_name)
	else
		return "[train=]"
	end
end

local function register_event_handlers()
	Event.register(remote.call("space-exploration", "get_on_train_teleport_started_event"), function(e)
		if message_level >= 3 then
			game.print({"se-ltn-glue-message.re-assign-delivery", train_richtext(e.train)})
		end
		remote.call("logistic-train-network", "reassign_delivery", e.old_train_id_1, e.train)
	end)

	Event.register(remote.call("logistic-train-network", "on_delivery_created"), function(e)
		local new_records = {}

		local loco = Train.get_main_locomotive(e.train)
		if not loco or not loco.valid then
			return -- a train without a locomotive won't go anywhere, don't waste any effort on it
		end

		-- TODO these fields might not make it into on_delivery_created
		local from_stop = e.from_stop
		local to_stop = e.to_stop

		if loco.surface == from_stop.surface and loco.surface == to_stop.surface then
			return -- normal intra surface delivery, do nothing
		end

		local passage_count = 0

		for _, record in pairs(e.train.schedule.records) do
			if record.station == e.from and loco.surface ~= from_stop.surface then
				-- different surfaces implies no temp-stop before this record to consider
				add_closest_elevator_to_schedule(loco, new_records, e.surface_connections)
				passage_count = passage_count + 1
			end

			if record.station == e.to and from_stop.surface ~= to_stop.surface then
				-- different surfaces implies no temp-stop before this record to consider
				add_closest_elevator_to_schedule(from_stop, new_records, e.surface_connections)
				passage_count = passage_count + 1
			end

			table.insert(new_records, record)

			if record.station == e.to and passage_count < 2 then
				-- train is not yet on the surface it came from
				add_closest_elevator_to_schedule(to_stop, new_records, e.surface_connections)
				passage_count = passage_count + 1
			end
		end

		e.train.schedule = {
			current = e.train.schedule.current,
			records = new_records,
		}
	end)
end

local function check_delivery_reset_setting(report_to)
	if settings.global["ltn-dispatcher-requester-delivery-reset"].value then
		report_to.print({ "se-ltn-glue-message.requester-delivery-reset-should-be-disabled", { "mod-setting-name.ltn-dispatcher-requester-delivery-reset"} })
    end
end

Event.on_init(function()
	initialize()
	register_event_handlers()
end)

Event.on_load(function()
	register_event_handlers()
end)

Event.on_configuration_changed(function()
	initialize()
	check_delivery_reset_setting(game)
end)

Event.register(defines.events.on_entity_destroyed, Elevator.on_entity_destroyed)

Event.register({defines.events.on_player_created, defines.events.on_player_joined_game}, function(e)
	local player = game.get_player(e.player_index)
	if player and player.connected then
		check_delivery_reset_setting(player)
	end
end)

Event.register(defines.events.on_player_removed, function(e)
	local player_data = global.players[e.player_index]
	if player_data and player_data.elevator_gui then
		player_data.elevator_gui.destroy()
	end
	global.players[e.player_index] = nil
end)

Event.register(defines.events.on_runtime_mod_setting_changed, function(e)
	if not e then return end

	if e.setting == "ltn-interface-console-level" then
		message_level = tonumber(settings.global["ltn-interface-console-level"].value)
	elseif e.setting == "ltn-dispatcher-requester-delivery-reset" then
		check_delivery_reset_setting(game)
	end
end)

local function safe_destroy(maybe_entity)
	if maybe_entity and maybe_entity.valid then
		maybe_entity.destroy()
	end
end

remote.add_interface("se-ltn-glue", {
	reset = function()
		for _, data in pairs(global.elevators) do
			safe_destroy(data.connector)
			if data.ground then
				safe_destroy(data.ground.connector)
			end
			if data.orbit then
				safe_destroy(data.orbit.connector)
			end
		end
		for _, data in pairs(global.players) do
			if data.elevator_gui then
				data.elevator_gui.destroy()
			end
		end
		global.elevators = {}
		global.players = {}
	end,

	-- TODO remove when the GUI works

	connect_elevator = function(elevator_entity, network_id)
		local data = Elevator.from_entity(elevator_entity)
		if data then
			data.network_id = network_id
			data.ltn_enabled = true
			Elevator.update_connection(data)
		end
	end,

	disconnect_elevator = function(elevator_entity)
		local data = Elevator.from_unit_number(elevator_entity.unit_number)
		if data then
			data.ltn_enabled = false
			Elevator.update_connection(data)
		end
	end,
})

if script.active_mods["gvv"] then require("__gvv__.gvv")() end
