local flib_train = require("__flib__.train")
local flib_misc = require("__flib__.misc")

local get_main_locomotive = flib_train.get_main_locomotive
local get_distance_squared = flib_misc.get_distance_squared
local format = string.format

message_level = tonumber(settings.global["ltn-interface-console-level"].value)

local function check_delivery_reset_setting(report_to)
  	if settings.global["ltn-dispatcher-requester-delivery-reset"].value then
		report_to.print({ "se-ltn-glue-message.requester-delivery-reset-should-be-disabled", { "mod-setting-name.ltn-dispatcher-requester-delivery-reset"} })
	end
end

script.on_event(defines.events.on_runtime_mod_setting_changed, function(event)
	if not event then return end

  	if event.setting == "ltn-interface-console-level" then
    	message_level = tonumber(settings.global["ltn-interface-console-level"].value)
  	elseif event.setting == "ltn-dispatcher-requester-delivery-reset" then
		check_delivery_reset_setting(game)
	end
end)

local function add_closest_elevator_to_schedule(entity, schedule_records)
	local found_stop = nil
	local distance = 2147483647 -- maxint

	-- TODO could be optimized with a lookup per surface but there aren't that many per surface
	-- TODO make use of new surface_connections field in event
	for _, elevator_stop in pairs(entity.surface.find_entities_filtered { name = "se-space-elevator-train-stop" }) do
		local stop_distance = get_distance_squared(elevator_stop.position, entity.position)
		if (not found_stop) or (stop_distance < distance) then
			found_stop = elevator_stop
			distance = stop_distance
		end
	end

	if found_stop then
		table.insert(schedule_records, {
			station = found_stop.backer_name
		})
	end
end

local function train_richtext(train)
	local loco = get_main_locomotive(train)
	if loco and loco.valid then
		return format("[train=%d] %s", loco.unit_number, loco.backer_name)
	else
		return "[train=]"
	end
end

local function register_event_handlers()
	script.on_event(remote.call("space-exploration", "get_on_train_teleport_started_event"), function(event)
		if message_level >= 3 then
			game.print({"se-ltn-glue-message.re-assign-delivery", train_richtext(event.train)})
		end
		remote.call("logistic-train-network", "reassign_delivery", event.old_train_id_1, event.train)
	end)

	script.on_event(remote.call("logistic-train-network", "on_delivery_created"), function(event)
		local new_records = {}

		local loco = get_main_locomotive(event.train)
		if not loco or not loco.valid then
			return -- a train without a locomotive won't go anywhere, don't waste any effort on it
		end

		-- TODO these fields might not make it into on_delivery_created
		local from_stop = event.from_stop
		local to_stop = event.to_stop

		if loco.surface == from_stop.surface and loco.surface == to_stop.surface then
			return -- normal intra surface delivery, do nothing
		end

		local passage_count = 0

		for _, record in pairs(event.train.schedule.records) do
			if record.station == event.from and loco.surface ~= from_stop.surface then
				-- different surfaces implies no temp-stop before this record to consider
				add_closest_elevator_to_schedule(loco, new_records)
				passage_count = passage_count + 1
			end

			if record.station == event.to and from_stop.surface ~= to_stop.surface then
				-- different surfaces implies no temp-stop before this record to consider
				add_closest_elevator_to_schedule(from_stop, new_records)
				passage_count = passage_count + 1
			end

			table.insert(new_records, record)

			if record.station == event.to and passage_count < 2 then
				-- train is not yet on the surface it came from
				add_closest_elevator_to_schedule(to_stop, new_records)
				passage_count = passage_count + 1
			end
		end

		event.train.schedule = {
			current = event.train.schedule.current,
			records = new_records,
		}
	end)
end

script.on_init(register_event_handlers)
script.on_load(register_event_handlers)

script.on_event(defines.events.on_player_created, function(event)
	local player = game.get_player(event.player_index)
	if player and player.connected then
		check_delivery_reset_setting(player)
	end
end)

script.on_event(defines.events.on_player_joined_game, function(event)
	local player = game.get_player(event.player_index)
	if player and player.connected then
		check_delivery_reset_setting(player)
	end
end)

script.on_configuration_changed(function()
	check_delivery_reset_setting(game)
end)
