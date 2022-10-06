Train = require("__flib__.train")
Misc = require("__flib__.misc")
Area = require("__flib__.area")
Event = require("__flib__.event")

message_level = tonumber(settings.global["ltn-interface-console-level"].value)

Elevator = require("elevator-connection")
Delivery = require("ltn-delivery")

local function initialize()
	global.elevators = global.elevators or {}
	global.players = global.players or {}
end

local function register_event_handlers()
	Event.register(remote.call("space-exploration", "get_on_train_teleport_started_event"), Delivery.on_train_teleport_started)
	Event.register(remote.call("logistic-train-network", "on_delivery_created"), Delivery.on_delivery_created)
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
